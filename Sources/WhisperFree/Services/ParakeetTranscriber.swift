import AVFoundation
import CoreMedia
import FluidAudio
import Foundation
import os

/// Native on-device Parakeet TDT v3 inference through FluidAudio and Core ML.
final class ParakeetTranscriber: TranscriptionEngine, @unchecked Sendable {
    static var isAppleSilicon: Bool { SystemInfo.isAppleSilicon }

    private let currentTask = OSAllocatedUnfairLock<Task<String, Error>?>(initialState: nil)

    func cancel() {
        currentTask.withLock { $0 }?.cancel()
    }

    func transcribe(
        audioURL: URL,
        language: String?,
        timeRange: CMTimeRange?,
        onProgress: ((Float, TimeInterval?) -> Void)?
    ) async throws -> String {
        guard Self.isAppleSilicon else {
            throw TranscriptionError.transcriptionFailed("Parakeet TDT v3 requires Apple Silicon.")
        }
        guard ParakeetModelStore.inspect(at: Storage.parakeetModelDirectory) == .candidate else {
            throw TranscriptionError.modelNotDownloaded
        }

        let progressSink = ParakeetProgressSink(callback: onProgress)
        let task = currentTask.withLock { currentTask -> Task<String, Error>? in
            guard currentTask == nil else { return nil }
            let task = Task {
                let preparedURL = try await Self.prepareAudio(
                    audioURL,
                    timeRange: timeRange,
                    progressSink: progressSink
                )
                defer {
                    if preparedURL != audioURL {
                        try? FileManager.default.removeItem(at: preparedURL)
                    }
                }
                return try await Self.runInference(
                    audioURL: preparedURL,
                    language: language,
                    progressSink: progressSink
                )
            }
            currentTask = task
            return task
        }
        guard let task else {
            throw TranscriptionError.transcriptionFailed("Parakeet transcription is already running.")
        }

        defer {
            currentTask.withLock { $0 = nil }
        }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func runInference(
        audioURL: URL,
        language: String?,
        progressSink: ParakeetProgressSink
    ) async throws -> String {
        let languageHint = try languageHint(for: language)
        progressSink.report(0.08)
        do {
            return try await ParakeetFluidAudioOperations.shared.withLoadedModels(
                from: Storage.parakeetModelDirectory,
                progressHandler: { progress in
                    progressSink.report(0.08 + Float(progress.fractionCompleted) * 0.14)
                }
            ) { models in
                try Task.checkCancellation()

                let manager = AsrManager(models: models)
                let progressTask = Task {
                    do {
                        let stream = await manager.transcriptionProgressStream
                        for try await progress in stream {
                            progressSink.report(0.22 + Float(progress) * 0.76)
                        }
                    } catch {
                        // The transcription result owns the surfaced error.
                    }
                }

                do {
                    var decoderState = try TdtDecoderState()
                    let result = try await manager.transcribe(
                        audioURL,
                        decoderState: &decoderState,
                        language: languageHint
                    )
                    progressTask.cancel()
                    _ = await progressTask.result
                    await manager.cleanup()
                    progressSink.report(1)
                    await MainActor.run {
                        ParakeetModelManager.shared.markReady()
                    }
                    return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                } catch {
                    progressTask.cancel()
                    _ = await progressTask.result
                    await manager.cleanup()
                    throw error
                }
            }
        } catch let error as ParakeetFluidAudioError {
            await MainActor.run {
                ParakeetModelManager.shared.markModelLoadFailed(error.localizedDescription)
            }
            throw error
        }
    }

    static func languageHint(for code: String?) throws -> Language? {
        guard let code, code != "auto" else { return nil }
        guard let language = Language(rawValue: code) else {
            throw TranscriptionError.transcriptionFailed(
                "Parakeet TDT v3 does not support the selected language. Use Auto-detect or choose a supported European language."
            )
        }
        return language
    }

    private static func prepareAudio(
        _ inputURL: URL,
        timeRange: CMTimeRange?,
        progressSink: ParakeetProgressSink
    ) async throws -> URL {
        guard let timeRange else { return inputURL }
        guard timeRange.duration.seconds.isFinite, timeRange.duration.seconds > 0 else {
            throw TranscriptionError.transcriptionFailed("The selected audio range is empty.")
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("parakeet_audio_\(UUID().uuidString).m4a")
        let asset = AVURLAsset(url: inputURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TranscriptionError.transcriptionFailed("Could not prepare the selected audio range.")
        }
        let sessionBox = ParakeetExportSessionBox(session)

        session.outputURL = outputURL
        session.outputFileType = .m4a
        session.timeRange = timeRange
        progressSink.report(0.02)

        await withTaskCancellationHandler {
            await session.export()
        } onCancel: {
            sessionBox.session.cancelExport()
        }

        if Task.isCancelled {
            try? FileManager.default.removeItem(at: outputURL)
            throw CancellationError()
        }
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: outputURL)
            throw TranscriptionError.transcriptionFailed(
                session.error?.localizedDescription ?? "Could not prepare the selected audio range."
            )
        }
        return outputURL
    }
}

private final class ParakeetExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

private final class ParakeetProgressSink: @unchecked Sendable {
    private let lock = NSLock()
    private let callback: ((Float, TimeInterval?) -> Void)?

    init(callback: ((Float, TimeInterval?) -> Void)?) {
        self.callback = callback
    }

    func report(_ progress: Float) {
        lock.lock()
        let callback = callback
        lock.unlock()
        callback?(min(max(progress, 0), 1), nil)
    }
}
