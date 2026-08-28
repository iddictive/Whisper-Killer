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
            version: .v3,
            encoderPrecision: .int8,
            progressHandler: progressHandler
        )
    }

    func load(
        from directory: URL,
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
            version: .v3,
            encoderPrecision: .int8,
            progressHandler: progressHandler
        )
    }

    func withLoadedModels<Result: Sendable>(
        from directory: URL,
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
                version: .v3,
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

    @Published private(set) var state: ParakeetModelState = .notInstalled
    private var downloadTask: Task<Void, Never>?
    private var activeOperationID: UUID?

    var isModelInstalled: Bool {
        ParakeetModelStore.inspect(at: Storage.parakeetModelDirectory) == .candidate
    }

    private init() {
        ModelHub.offlineMode = true
        refresh()
    }

    func refresh() {
        guard activeOperationID == nil else { return }
        state = stateForCurrentFiles()
    }

    func markReady() {
        guard activeOperationID == nil else { return }
        state = isModelInstalled ? .ready : stateForCurrentFiles()
    }

    func markModelLoadFailed(_ message: String) {
        guard activeOperationID == nil else { return }
        state = .failed(message)
    }

    func download(force: Bool = false) {
        guard downloadTask == nil else { return }
        guard ParakeetTranscriber.isAppleSilicon else {
            state = .failed("Parakeet TDT v3 requires Apple Silicon.")
            return
        }

        let operationID = UUID()
        activeOperationID = operationID
        state = .downloading(progress: 0, stage: .listing)

        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await ParakeetFluidAudioOperations.shared.download(
                    to: Storage.parakeetModelDirectory,
                    force: force
                ) { [weak self] progress in
                    Task { @MainActor in
                        guard self?.activeOperationID == operationID else { return }
                        let stage: ParakeetDownloadStage
                        switch progress.phase {
                        case .listing:
                            stage = .listing
                        case .downloading:
                            stage = .downloading
                        case .compiling:
                            stage = .compiling
                        }
                        self?.state = .downloading(
                            progress: progress.fractionCompleted,
                            stage: stage
                        )
                    }
                }
                try Task.checkCancellation()
                guard self.activeOperationID == operationID else { return }
                await self.validate(operationID: operationID)
                guard self.activeOperationID == operationID else { return }
                self.activeOperationID = nil
                self.downloadTask = nil
            } catch is CancellationError {
                guard self.activeOperationID == operationID else { return }
                self.downloadTask = nil
                self.activeOperationID = nil
                self.state = self.stateForCurrentFiles()
            } catch {
                guard self.activeOperationID == operationID else { return }
                self.downloadTask = nil
                self.activeOperationID = nil
                if Task.isCancelled {
                    self.state = self.stateForCurrentFiles()
                } else if ParakeetModelStore.inspect(at: Storage.parakeetModelDirectory) == .partial {
                    self.state = .partial
                } else {
                    self.state = .failed(error.localizedDescription)
                }
            }
        }
    }

    func validate() async {
        guard activeOperationID == nil else { return }
        let operationID = UUID()
        activeOperationID = operationID
        await validate(operationID: operationID)
        if activeOperationID == operationID {
            activeOperationID = nil
        }
    }

    private func validate(operationID: UUID) async {
        guard ParakeetModelStore.inspect(at: Storage.parakeetModelDirectory) == .candidate else {
            guard activeOperationID == operationID else { return }
            state = stateForCurrentFiles()
            return
        }

        state = .validating
        do {
            _ = try await ParakeetFluidAudioOperations.shared.load(from: Storage.parakeetModelDirectory)
            try Task.checkCancellation()
            guard activeOperationID == operationID else { return }
            state = .ready
        } catch is CancellationError {
            guard activeOperationID == operationID else { return }
            state = stateForCurrentFiles()
        } catch {
            guard activeOperationID == operationID else { return }
            state = .failed(error.localizedDescription)
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    func deleteModel() {
        let cancelledTask = downloadTask
        let operationID = UUID()
        activeOperationID = operationID
        cancelledTask?.cancel()
        downloadTask = nil
        state = .deleting

        Task { [weak self] in
            _ = await cancelledTask?.result
            guard let self, self.activeOperationID == operationID else { return }

            do {
                let modelDirectory = Storage.parakeetModelDirectory
                try await ParakeetFluidAudioOperations.shared.deleteModel(at: modelDirectory)
                self.activeOperationID = nil
                self.state = .notInstalled
            } catch {
                self.activeOperationID = nil
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    private func stateForCurrentFiles() -> ParakeetModelState {
        switch ParakeetModelStore.inspect(at: Storage.parakeetModelDirectory) {
        case .notInstalled:
            return .notInstalled
        case .partial:
            return .partial
        case .candidate:
            return .installed
        }
    }
}
