import Foundation
import AVFoundation
import CoreMedia
import Darwin
import CryptoKit

/// Local Qwen3-ASR inference through an app-managed MLX runtime.
final class QwenASRTranscriber: TranscriptionEngine, @unchecked Sendable {
    static let runtimePackageVersion = "0.3.5"

    private let model: QwenASRModel
    private var currentProcess: Process?

    init(model: QwenASRModel) {
        self.model = model
    }

    func pause() {
        if let pid = currentProcess?.processIdentifier {
            kill(pid, SIGSTOP)
        }
    }

    func resume() {
        if let pid = currentProcess?.processIdentifier {
            kill(pid, SIGCONT)
        }
    }

    func cancel() {
        currentProcess?.terminate()
    }

    func transcribe(audioURL: URL, language: String?, timeRange: CMTimeRange?, onProgress: ((Float, TimeInterval?) -> Void)?) async throws -> String {
        guard Self.isAppleSilicon else {
            throw TranscriptionError.transcriptionFailed("Qwen3-ASR MLX requires Apple Silicon.")
        }

        try await Self.validateInputAudio(audioURL, timeRange: timeRange)
        onProgress?(0.03, nil)
        let python = try await Self.ensureRuntimeInstalled()
        onProgress?(0.10, nil)

        let wavURL: URL
        let shouldCleanupWav: Bool
        if isAlready16kHzWav(audioURL) && timeRange == nil {
            wavURL = audioURL
            shouldCleanupWav = false
        } else {
            wavURL = try await convertTo16kHzWav(audioURL, timeRange: timeRange) { progress in
                onProgress?(0.10 + progress * 0.10, nil)
            }
            shouldCleanupWav = true
        }
        defer {
            if shouldCleanupWav {
                try? FileManager.default.removeItem(at: wavURL)
            }
        }
        try Self.validatePreparedAudioFile(wavURL)

        let scriptURL = try Self.writeHelperScript()
        let languageName = Self.qwenLanguageName(for: language)

        var args = [
            scriptURL.path,
            "--audio", wavURL.path,
            "--model", model.modelID
        ]
        if let languageName {
            args += ["--language", languageName]
        }

        let stdout = try await Self.runHelperProcess(
            python: python,
            arguments: args,
            timeoutDescription: "Qwen3-ASR transcription",
            onProcessStart: { [weak self] process in self?.currentProcess = process },
            onProcessEnd: { [weak self] in self?.currentProcess = nil },
            onProgress: onProgress
        )
        let text = try Self.parseTranscript(from: stdout)
        onProgress?(1.0, nil)
        return text
    }

    static func downloadModel(_ model: QwenASRModel, onProgress: ((Float, TimeInterval?) -> Void)?) async throws {
        guard isAppleSilicon else {
            throw TranscriptionError.transcriptionFailed("Qwen3-ASR MLX requires Apple Silicon.")
        }

        onProgress?(0.03, nil)
        let python = try await ensureRuntimeInstalled()
        onProgress?(0.10, nil)

        let scriptURL = try writeHelperScript()
        _ = try await runHelperProcess(
            python: python,
            arguments: [scriptURL.path, "--model", model.modelID, "--download-only"],
            timeoutDescription: "Qwen3-ASR model download",
            onProcessStart: nil,
            onProcessEnd: nil,
            onProgress: onProgress
        )
        onProgress?(1.0, nil)
    }

    private static func runHelperProcess(
        python: String,
        arguments: [String],
        timeoutDescription: String,
        onProcessStart: ((Process) -> Void)?,
        onProcessEnd: (() -> Void)?,
        onProgress: ((Float, TimeInterval?) -> Void)?
    ) async throws -> String {
        let startedAt = Date()

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: python)
            process.arguments = arguments
            process.environment = qwenProcessEnvironment()

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            let outputAccumulator = DataAccumulator()
            let errorAccumulator = DataAccumulator()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                outputAccumulator.append(chunk)
                guard let text = String(data: chunk, encoding: .utf8) else { return }
                for progress in parseProgress(from: text) {
                    let elapsed = Date().timeIntervalSince(startedAt)
                    let remaining: TimeInterval? = progress > 0.25 ? max(0, elapsed / Double(progress) - elapsed) : nil
                    onProgress?(progress, remaining)
                }
            }

            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                errorAccumulator.append(chunk)
            }

            let timeoutSeconds: Double = 1800
            let timedOut = ThreadSafeFlag(false)
            let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
            timer.schedule(deadline: .now() + timeoutSeconds)
            timer.setEventHandler {
                timedOut.set(true)
                if process.isRunning {
                    process.terminate()
                }
            }
            timer.resume()

            process.terminationHandler = { p in
                onProcessEnd?()
                timer.cancel()
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                let stdout = String(data: outputAccumulator.getData(), encoding: .utf8) ?? ""
                let stderr = String(data: errorAccumulator.getData(), encoding: .utf8) ?? ""

                if p.terminationStatus == 0 {
                    continuation.resume(returning: stdout)
                } else if timedOut.get() {
                    continuation.resume(throwing: TranscriptionError.transcriptionFailed("\(timeoutDescription) timed out after \(Int(timeoutSeconds)) seconds."))
                } else {
                    let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: TranscriptionError.transcriptionFailed(qwenFailureMessage(from: message, status: p.terminationStatus)))
                }
            }

            do {
                try process.run()
                onProcessStart?(process)
            } catch {
                timer.cancel()
                continuation.resume(throwing: TranscriptionError.transcriptionFailed(error.localizedDescription))
            }
        }
    }

    private static func qwenProcessEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        environment["HF_HOME"] = Storage.qwenASRCacheDirectory.path
        environment["HF_HUB_DISABLE_XET"] = "1"
        environment["HF_HUB_ENABLE_HF_TRANSFER"] = "0"
        environment["TOKENIZERS_PARALLELISM"] = "false"
        environment["NO_COLOR"] = "1"
        return environment
    }

    static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }

    static var runtimePythonPath: String {
        Storage.qwenASRRuntimeDirectory
            .appendingPathComponent("venv/bin/python", isDirectory: false)
            .path
    }

    private static var standalonePythonPath: String {
        Storage.qwenASRRuntimeDirectory
            .appendingPathComponent("Python/bin/python3", isDirectory: false)
            .path
    }

    static var isRuntimeInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: runtimePythonPath)
    }

    static func findBasePythonBinary() -> String? {
        if FileManager.default.isExecutableFile(atPath: standalonePythonPath) {
            return standalonePythonPath
        }

        let possiblePaths = [
            "/opt/homebrew/bin/python3.13",
            "/usr/local/bin/python3.13",
            "/opt/homebrew/bin/python3.12",
            "/usr/local/bin/python3.12",
            "/opt/homebrew/bin/python3.11",
            "/usr/local/bin/python3.11",
            "/opt/homebrew/bin/python3.10",
            "/usr/local/bin/python3.10",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]

        for path in possiblePaths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["python3"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    static func ensureRuntimeInstalled() async throws -> String {
        if isRuntimeInstalled {
            do {
                try await validateRuntime()
                return runtimePythonPath
            } catch {
                // Repair an incomplete or stale environment in place.
            }
        }

        try await installRuntime()
        return runtimePythonPath
    }

    static func installRuntime() async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = installRuntimeSync()
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
        try await validateRuntime()
    }

    static func validateRuntime(at pythonPath: String = runtimePythonPath) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let script = """
                from importlib.metadata import version
                import mlx_qwen3_asr
                installed = version("mlx-qwen3-asr")
                if installed != "\(runtimePackageVersion)":
                    raise RuntimeError(f"Expected mlx-qwen3-asr \(runtimePackageVersion), found {installed}")
                """
                let result = runProcess(
                    executable: pythonPath,
                    arguments: ["-c", script],
                    outputName: "qwen_asr_runtime_probe"
                )
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func installRuntimeSync() -> Result<Void, TranscriptionError> {
        let basePython: String
        switch ensureStandalonePythonSync() {
        case .success(let python):
            basePython = python
        case .failure(let error):
            return .failure(error)
        }

        let venvDirectory = Storage.qwenASRRuntimeDirectory.appendingPathComponent("venv", isDirectory: true).path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            "-lc",
            """
            set -e
            mkdir -p \(shellQuoted(Storage.qwenASRRuntimeDirectory.path))
            \(shellQuoted(basePython)) -m venv \(shellQuoted(venvDirectory))
            \(shellQuoted(runtimePythonPath)) -m pip install --upgrade pip
            \(shellQuoted(runtimePythonPath)) -m pip install --disable-pip-version-check mlx-qwen3-asr==\(runtimePackageVersion)
            """
        ]

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("qwen_asr_runtime_install_\(UUID().uuidString).log")
        _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        guard let outputHandle = try? FileHandle(forWritingTo: outputURL) else {
            return .failure(.transcriptionFailed("Could not create Qwen3-ASR install log."))
        }
        defer {
            try? outputHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
        }

        process.standardOutput = outputHandle
        process.standardError = outputHandle

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let output = (try? String(contentsOf: outputURL, encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return .failure(.transcriptionFailed(installFailureMessage(output: output, status: process.terminationStatus)))
            }

            return .success(())
        } catch {
            return .failure(.transcriptionFailed(error.localizedDescription))
        }
    }

    private static func ensureStandalonePythonSync() -> Result<String, TranscriptionError> {
        if FileManager.default.isExecutableFile(atPath: standalonePythonPath) {
            return .success(standalonePythonPath)
        }

        let downloadURL = URL(string: "https://github.com/astral-sh/python-build-standalone/releases/download/20260510/cpython-3.12.13%2B20260510-aarch64-apple-darwin-install_only_stripped.tar.gz")!
        let expectedSHA256 = "55bc1a5edbc8ac4da0081f4f5731ed2d1ed10c57cb37a820b2a0dbc7cad742e9"
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("qwen_asr_python_\(UUID().uuidString)", isDirectory: true)
        let archiveURL = workDirectory.appendingPathComponent("python.tar.gz")
        let extractDirectory = workDirectory.appendingPathComponent("extract", isDirectory: true)
        let targetDirectory = Storage.qwenASRRuntimeDirectory.appendingPathComponent("Python", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: extractDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: workDirectory) }

            let semaphore = DispatchSemaphore(value: 0)
            final class DownloadBox: @unchecked Sendable {
                var result: Result<URL, Error>?
            }
            let box = DownloadBox()
            let task = URLSession.shared.downloadTask(with: downloadURL) { location, _, error in
                if let error {
                    box.result = .failure(error)
                } else if let location {
                    box.result = .success(location)
                } else {
                    box.result = .failure(TranscriptionError.transcriptionFailed("Python runtime download did not return a file."))
                }
                semaphore.signal()
            }
            task.resume()
            semaphore.wait()

            guard let downloadResult = box.result else {
                return .failure(.transcriptionFailed("Python runtime download did not complete."))
            }

            let downloadedURL = try downloadResult.get()
            try FileManager.default.moveItem(at: downloadedURL, to: archiveURL)

            let archiveData = try Data(contentsOf: archiveURL)
            let actualSHA256 = SHA256.hash(data: archiveData).map { String(format: "%02x", $0) }.joined()
            guard actualSHA256 == expectedSHA256 else {
                return .failure(.transcriptionFailed("Python runtime integrity check failed. Retry the runtime install."))
            }

            let extractResult = runProcess(
                executable: "/usr/bin/tar",
                arguments: ["-xzf", archiveURL.path, "-C", extractDirectory.path],
                outputName: "qwen_asr_python_extract"
            )
            if case .failure(let error) = extractResult {
                return .failure(error)
            }

            let extractedPythonDirectory = extractDirectory.appendingPathComponent("python", isDirectory: true)
            if FileManager.default.fileExists(atPath: targetDirectory.path) {
                try FileManager.default.removeItem(at: targetDirectory)
            }
            try FileManager.default.moveItem(at: extractedPythonDirectory, to: targetDirectory)

            guard FileManager.default.isExecutableFile(atPath: standalonePythonPath) else {
                return .failure(.transcriptionFailed("Python runtime was installed but is not executable."))
            }

            return .success(standalonePythonPath)
        } catch {
            return .failure(.transcriptionFailed(error.localizedDescription))
        }
    }

    private static func runProcess(executable: String, arguments: [String], outputName: String) -> Result<Void, TranscriptionError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(outputName)_\(UUID().uuidString).log")
        _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        guard let outputHandle = try? FileHandle(forWritingTo: outputURL) else {
            return .failure(.transcriptionFailed("Could not create runtime log."))
        }
        defer {
            try? outputHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
        }

        process.standardOutput = outputHandle
        process.standardError = outputHandle

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let output = (try? String(contentsOf: outputURL, encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return .failure(.transcriptionFailed(installFailureMessage(output: output, status: process.terminationStatus)))
            }

            return .success(())
        } catch {
            return .failure(.transcriptionFailed(error.localizedDescription))
        }
    }

    private static func installFailureMessage(output: String?, status: Int32) -> String {
        guard let output, !output.isEmpty else {
            return "Qwen3-ASR runtime install exited with code \(status)."
        }

        let maxLength = 700
        return output.count <= maxLength ? output : String(output.suffix(maxLength))
    }

    private static func writeHelperScript() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisperkiller_qwen_asr_transcribe.py")
        try pythonHelper.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func parseTranscript(from stdout: String) throws -> String {
        let marker = "__WHISPERFREE_QWEN_RESULT__"
        guard let line = stdout.components(separatedBy: .newlines).last(where: { $0.hasPrefix(marker) }) else {
            throw TranscriptionError.invalidResponse
        }

        let payload = String(line.dropFirst(marker.count))
        let data = Data(payload.utf8)
        let result = try JSONDecoder().decode(QwenResult.self, from: data)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseProgress(from stdoutChunk: String) -> [Float] {
        let marker = "__WHISPERFREE_QWEN_PROGRESS__"
        return stdoutChunk.components(separatedBy: .newlines).compactMap { line in
            guard line.hasPrefix(marker) else { return nil }
            let payload = String(line.dropFirst(marker.count))
            guard let data = payload.data(using: .utf8),
                  let event = try? JSONDecoder().decode(QwenProgress.self, from: data)
            else { return nil }

            if let overallProgress = event.overallProgress {
                return min(max(overallProgress, 0), 1)
            }

            guard let progress = event.progress else { return nil }
            return min(max(0.25 + progress * 0.73, 0), 1)
        }
    }

    private static func qwenFailureMessage(from stderr: String, status: Int32) -> String {
        guard !stderr.isEmpty else {
            return "Qwen3-ASR exited with code \(status)."
        }

        if stderr.localizedCaseInsensitiveContains("Cannot compute mel spectrogram of empty audio") {
            return emptyAudioMessage
        }

        return stderr
    }

    private static func validateInputAudio(_ url: URL, timeRange: CMTimeRange?) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TranscriptionError.transcriptionFailed("Qwen3-ASR input audio file is missing.")
        }

        if url.pathExtension.lowercased() == "wav", let file = try? AVAudioFile(forReading: url) {
            guard file.length > 0 else {
                throw TranscriptionError.transcriptionFailed(emptyAudioMessage)
            }
            return
        }

        let asset = AVURLAsset(url: url)
        let duration = try await effectiveDuration(for: asset, timeRange: timeRange)
        guard duration.isFinite, duration > 0 else {
            throw TranscriptionError.transcriptionFailed(emptyAudioMessage)
        }

        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
            throw TranscriptionError.transcriptionFailed("Could not load audio track")
        }
    }

    private static func effectiveDuration(for asset: AVURLAsset, timeRange: CMTimeRange?) async throws -> Double {
        if let timeRange {
            return timeRange.duration.seconds
        }
        return try await asset.load(.duration).seconds
    }

    private static func qwenLanguageName(for code: String?) -> String? {
        guard let code, !code.isEmpty, code != "auto" else { return nil }
        let names: [String: String] = [
            "ar": "Arabic",
            "cs": "Czech",
            "da": "Danish",
            "de": "German",
            "en": "English",
            "es": "Spanish",
            "fa": "Persian",
            "fi": "Finnish",
            "fil": "Filipino",
            "fr": "French",
            "el": "Greek",
            "hi": "Hindi",
            "hu": "Hungarian",
            "id": "Indonesian",
            "it": "Italian",
            "ja": "Japanese",
            "ko": "Korean",
            "ms": "Malay",
            "nl": "Dutch",
            "pl": "Polish",
            "pt": "Portuguese",
            "ro": "Romanian",
            "ru": "Russian",
            "sv": "Swedish",
            "th": "Thai",
            "tr": "Turkish",
            "vi": "Vietnamese",
            "yue": "Cantonese",
            "zh": "Chinese"
        ]
        return names[code.lowercased()]
    }

    private func convertTo16kHzWav(_ inputURL: URL, timeRange: CMTimeRange?, onProgress: @escaping (Float) -> Void) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("qwen_asr_input_\(UUID().uuidString).wav")
        let asset = AVURLAsset(url: inputURL)
        let actualDuration: Double
        if let timeRange {
            actualDuration = timeRange.duration.seconds
        } else {
            actualDuration = try await asset.load(.duration).seconds
        }
        guard actualDuration.isFinite, actualDuration > 0 else {
            throw TranscriptionError.transcriptionFailed(Self.emptyAudioMessage)
        }
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw TranscriptionError.transcriptionFailed("Could not load audio track")
        }

        let reader = try AVAssetReader(asset: asset)
        if let timeRange {
            reader.timeRange = timeRange
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(trackOutput)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .wav)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        writerInput.expectsMediaDataInRealTime = false
        writer.add(writerInput)

        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        final class ConversionContext: @unchecked Sendable {
            let reader: AVAssetReader
            let writer: AVAssetWriter
            let writerInput: AVAssetWriterInput
            let trackOutput: AVAssetReaderTrackOutput
            let duration: Double
            var isResumed = false

            init(reader: AVAssetReader, writer: AVAssetWriter, writerInput: AVAssetWriterInput, trackOutput: AVAssetReaderTrackOutput, duration: Double) {
                self.reader = reader
                self.writer = writer
                self.writerInput = writerInput
                self.trackOutput = trackOutput
                self.duration = duration
            }
        }

        let context = ConversionContext(reader: reader, writer: writer, writerInput: writerInput, trackOutput: trackOutput, duration: actualDuration)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "qwenASRAudioConvertQueue")
            context.writerInput.requestMediaDataWhenReady(on: queue) {
                while context.writerInput.isReadyForMoreMediaData {
                    if let buffer = context.trackOutput.copyNextSampleBuffer() {
                        let time = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
                        let startTime = context.reader.timeRange.start.seconds
                        let relativeTime = time - (startTime > 0 ? startTime : 0)
                        let progress = Float(max(0, relativeTime) / context.duration)
                        onProgress(min(1.0, progress))
                        context.writerInput.append(buffer)
                    } else {
                        if !context.isResumed {
                            context.isResumed = true
                            context.writerInput.markAsFinished()
                            if let error = context.reader.error ?? context.writer.error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume()
                            }
                        }
                        break
                    }
                }
            }
        }

        await writer.finishWriting()
        onProgress(1.0)
        return outputURL
    }

    private static func validatePreparedAudioFile(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TranscriptionError.transcriptionFailed("Qwen3-ASR input audio file is missing.")
        }

        do {
            let file = try AVAudioFile(forReading: url)
            guard file.length > 0 else {
                throw TranscriptionError.transcriptionFailed(emptyAudioMessage)
            }
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.transcriptionFailed("Qwen3-ASR input audio could not be read: \(error.localizedDescription)")
        }
    }

    private func isAlready16kHzWav(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "wav" else { return false }
        guard let file = try? AVAudioFile(forReading: url) else { return false }
        let format = file.processingFormat
        return abs(format.sampleRate - 16000) < 100 && format.channelCount == 1 && file.length > 0
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static let emptyAudioMessage = "Qwen3-ASR input audio is empty. Try recording again or choose a file with an audio track."

    private struct QwenResult: Decodable {
        let text: String
    }

    private struct QwenProgress: Decodable {
        let progress: Float?
        let overallProgress: Float?

        enum CodingKeys: String, CodingKey {
            case progress
            case overallProgress = "overall_progress"
        }
    }

    private static let pythonHelper = #"""
import argparse
import json
import sys
import time

def emit_progress(event):
    try:
        payload = json.dumps(event, ensure_ascii=False)
    except TypeError:
        payload = json.dumps({"event": str(event)}, ensure_ascii=False)
    print("__WHISPERFREE_QWEN_PROGRESS__" + payload, flush=True)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--audio")
    parser.add_argument("--model", required=True)
    parser.add_argument("--language")
    parser.add_argument("--download-only", action="store_true")
    args = parser.parse_args()

    from huggingface_hub import snapshot_download
    from tqdm.auto import tqdm
    from mlx_qwen3_asr import transcribe

    class QwenDownloadProgress(tqdm):
        last_emit_at = 0.0

        def update(self, n=1):
            super().update(n)
            total = self.total or 0
            if total <= 0:
                return
            now = time.time()
            if now - self.last_emit_at < 0.5 and self.n < total:
                return
            self.last_emit_at = now
            progress = max(0.0, min(1.0, float(self.n) / float(total)))
            emit_progress({
                "stage": "download",
                "progress": progress,
                "overall_progress": 0.12 + progress * 0.12,
            })

    emit_progress({"stage": "download", "progress": 0.0, "overall_progress": 0.12})
    model_path = snapshot_download(
        repo_id=args.model,
        allow_patterns=["*.json", "*.safetensors", "*.txt", "*.model"],
        etag_timeout=20,
        max_workers=4,
        tqdm_class=QwenDownloadProgress,
    )
    emit_progress({"stage": "model_ready", "progress": 1.0, "overall_progress": 0.24})

    if args.download_only:
        print("__WHISPERFREE_QWEN_RESULT__" + json.dumps({"text": ""}, ensure_ascii=False), flush=True)
        return

    if not args.audio:
        parser.error("--audio is required unless --download-only is set")

    result = transcribe(
        args.audio,
        model=model_path,
        language=args.language,
        on_progress=emit_progress,
        verbose=True,
    )

    payload = {
        "text": getattr(result, "text", "") or "",
        "language": getattr(result, "language", None),
        "duration": getattr(result, "duration", None),
    }
    print("__WHISPERFREE_QWEN_RESULT__" + json.dumps(payload, ensure_ascii=False), flush=True)

if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        raise
"""#
}
