import Combine
import FluidAudio
import Foundation

enum ParakeetDownloadStage: Equatable {
    case listing
    case downloading
    case compiling
}

enum ParakeetModelState: Equatable {
    case notInstalled
    case partial
    case installed
    case validating
    case downloading(progress: Double, stage: ParakeetDownloadStage)
    case ready
    case deleting
    case failed(String)
}

enum ParakeetModelInspection: Equatable {
    case notInstalled
    case partial
    case candidate
}

enum ParakeetModelStore {
    static let requiredRelativePaths = [
        "Preprocessor.mlmodelc",
        "Encoder.mlmodelc",
        "Decoder.mlmodelc",
        "JointDecisionv3.mlmodelc",
        "parakeet_vocab.json",
    ]

    static func inspect(at modelDirectory: URL, fileManager: FileManager = .default) -> ParakeetModelInspection {
        guard fileManager.fileExists(atPath: modelDirectory.path) else {
            return .notInstalled
        }

        let hasPartialFile = fileManager.enumerator(
            at: modelDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )?.contains { item in
            guard let url = item as? URL else { return false }
            return url.lastPathComponent.hasSuffix(".partial") || url.lastPathComponent.hasSuffix(".partial.etag")
        } ?? false

        if hasPartialFile {
            return .partial
        }

        let presentCount = requiredRelativePaths.reduce(into: 0) { count, relativePath in
            let path = modelDirectory.appendingPathComponent(relativePath)
            let isComplete: Bool
            if relativePath.hasSuffix(".mlmodelc") {
                var isDirectory: ObjCBool = false
                isComplete = fileManager.fileExists(atPath: path.path, isDirectory: &isDirectory)
                    && isDirectory.boolValue
                    && fileManager.fileExists(atPath: path.appendingPathComponent("coremldata.bin").path)
            } else {
                let size = (try? path.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                isComplete = fileManager.fileExists(atPath: path.path) && size > 0
            }

            if isComplete {
                count += 1
            }
        }

        if presentCount == requiredRelativePaths.count {
            return .candidate
        }
        return presentCount == 0 ? .notInstalled : .partial
    }
}

actor ParakeetFluidAudioOperations {
    static let shared = ParakeetFluidAudioOperations()

    private var operationInFlight = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func download(
        to directory: URL,
        model: ParakeetModel = .v3,
        force: Bool,
        progressHandler: ProgressHandler?
    ) async throws -> URL {
        await acquire()
        defer { release() }
        try Task.checkCancellation()

        let previousOfflineMode = ModelHub.offlineMode
        ModelHub.offlineMode = false
        defer { ModelHub.offlineMode = previousOfflineMode }
        return try await AsrModels.download(
            to: directory,
            force: force,
            version: model.fluidAudioVersion,
            encoderPrecision: .int8,
            progressHandler: progressHandler
        )
    }

    func load(
        from directory: URL,
        model: ParakeetModel = .v3,
        progressHandler: ProgressHandler? = nil
    ) async throws -> AsrModels {
        await acquire()
        defer { release() }
        try Task.checkCancellation()

        let previousOfflineMode = ModelHub.offlineMode
        ModelHub.offlineMode = true
        defer { ModelHub.offlineMode = previousOfflineMode }
        return try await AsrModels.load(
            from: directory,
            version: model.fluidAudioVersion,
            encoderPrecision: .int8,
            progressHandler: progressHandler
        )
    }

    func withLoadedModels<Result: Sendable>(
        from directory: URL,
        model: ParakeetModel = .v3,
        progressHandler: ProgressHandler? = nil,
        operation: @Sendable (AsrModels) async throws -> Result
    ) async throws -> Result {
        await acquire()
        defer { release() }
        try Task.checkCancellation()

        let previousOfflineMode = ModelHub.offlineMode
        ModelHub.offlineMode = true
        defer { ModelHub.offlineMode = previousOfflineMode }

        let models: AsrModels
        do {
            models = try await AsrModels.load(
                from: directory,
                version: model.fluidAudioVersion,
                encoderPrecision: .int8,
                progressHandler: progressHandler
            )
        } catch {
            if error is CancellationError || Task.isCancelled {
                throw CancellationError()
            }
            throw ParakeetFluidAudioError.modelLoadFailed(error.localizedDescription)
        }
        try Task.checkCancellation()
        return try await operation(models)
    }

    func deleteModel(at directory: URL) async throws {
        await acquire()
        defer { release() }

        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private func acquire() async {
        if !operationInFlight {
            operationInFlight = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            operationInFlight = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

private extension ParakeetModel {
    var fluidAudioVersion: AsrModelVersion {
        switch self {
        case .ultra: return .ultra
        case .v3: return .v3
        }
    }
}

enum ParakeetFluidAudioError: LocalizedError {
    case modelLoadFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let message): return message
        }
    }
}

@MainActor
final class ParakeetModelManager: ObservableObject {
    static let shared = ParakeetModelManager()

    @Published private(set) var selectedModel: ParakeetModel
    @Published private(set) var state: ParakeetModelState = .notInstalled
    @Published private var activeOperationID: UUID?
    private var downloadTask: Task<Void, Never>?

    var isBusy: Bool { activeOperationID != nil }

    var isModelInstalled: Bool {
        ParakeetModelStore.inspect(at: Storage.parakeetModelDirectory(for: selectedModel)) == .candidate
    }

    private init() {
        selectedModel = Storage.shared.loadSettings().parakeetModel
        ModelHub.offlineMode = true
        refresh()
    }

    func selectModel(_ model: ParakeetModel) {
        guard selectedModel != model else { return }
        selectedModel = model
        state = stateForCurrentFiles()
    }

    func refresh() {
        guard !isBusy else { return }
        state = stateForCurrentFiles()
    }

    func markReady(for model: ParakeetModel) {
        guard !isBusy, selectedModel == model else { return }
        state = isModelInstalled ? .ready : stateForCurrentFiles()
    }

    func markModelLoadFailed(_ message: String, for model: ParakeetModel) {
        guard !isBusy, selectedModel == model else { return }
        state = .failed(message)
    }

    func download(force: Bool = false) {
        guard !isBusy else { return }
        guard ParakeetTranscriber.isAppleSilicon else {
            state = .failed("Parakeet requires Apple Silicon.")
            return
        }

        let model = selectedModel
        let directory = Storage.parakeetModelDirectory(for: model)
        let operationID = UUID()
        activeOperationID = operationID
        state = .downloading(progress: 0, stage: .listing)

        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await ParakeetFluidAudioOperations.shared.download(
                    to: directory,
                    model: model,
                    force: force
                ) { [weak self] progress in
                    Task { @MainActor in
                        guard self?.activeOperationID == operationID, self?.selectedModel == model else { return }
                        let stage: ParakeetDownloadStage
                        switch progress.phase {
                        case .listing: stage = .listing
                        case .downloading: stage = .downloading
                        case .compiling: stage = .compiling
                        }
                        self?.state = .downloading(progress: progress.fractionCompleted, stage: stage)
                    }
                }
                try Task.checkCancellation()
                let result = await self.validate(model: model, at: directory, operationID: operationID)
                self.finish(operationID: operationID, model: model, state: result)
            } catch is CancellationError {
                self.finish(operationID: operationID, model: model, state: self.stateForFiles(at: directory))
            } catch {
                let result: ParakeetModelState
                if Task.isCancelled || ParakeetModelStore.inspect(at: directory) == .partial {
                    result = self.stateForFiles(at: directory)
                } else {
                    result = .failed(error.localizedDescription)
                }
                self.finish(operationID: operationID, model: model, state: result)
            }
        }
    }

    func validate() async {
        guard !isBusy else { return }
        let model = selectedModel
        let directory = Storage.parakeetModelDirectory(for: model)
        let operationID = UUID()
        activeOperationID = operationID
        let result = await validate(model: model, at: directory, operationID: operationID)
        finish(operationID: operationID, model: model, state: result)
    }

    private func validate(model: ParakeetModel, at directory: URL, operationID: UUID) async -> ParakeetModelState {
        guard ParakeetModelStore.inspect(at: directory) == .candidate else {
            return stateForFiles(at: directory)
        }

        if activeOperationID == operationID, selectedModel == model {
            state = .validating
        }
        do {
            _ = try await ParakeetFluidAudioOperations.shared.load(from: directory, model: model)
            try Task.checkCancellation()
            return .ready
        } catch is CancellationError {
            return stateForFiles(at: directory)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    func deleteModel() {
        guard !isBusy else { return }
        let model = selectedModel
        let directory = Storage.parakeetModelDirectory(for: model)
        let operationID = UUID()
        activeOperationID = operationID
        state = .deleting

        Task { [weak self] in
            guard let self else { return }
            do {
                try await ParakeetFluidAudioOperations.shared.deleteModel(at: directory)
                self.finish(operationID: operationID, model: model, state: .notInstalled)
            } catch {
                self.finish(operationID: operationID, model: model, state: .failed(error.localizedDescription))
            }
        }
    }

    private func finish(operationID: UUID, model: ParakeetModel, state result: ParakeetModelState) {
        guard activeOperationID == operationID else { return }
        activeOperationID = nil
        downloadTask = nil
        state = selectedModel == model ? result : stateForCurrentFiles()
    }

    private func stateForCurrentFiles() -> ParakeetModelState {
        stateForFiles(at: Storage.parakeetModelDirectory(for: selectedModel))
    }

    private func stateForFiles(at directory: URL) -> ParakeetModelState {
        switch ParakeetModelStore.inspect(at: directory) {
        case .notInstalled: return .notInstalled
        case .partial: return .partial
        case .candidate: return .ready
        }
    }
}
