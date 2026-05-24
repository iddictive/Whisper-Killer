import Foundation
import AVFoundation
import CoreMedia
import Darwin

/// Local Qwen3-ASR inference through an app-managed MLX runtime.
final class QwenASRTranscriber: TranscriptionEngine, @unchecked Sendable {
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

        let scriptURL = try Self.writeHelperScript()
        let languageName = Self.qwenLanguageName(for: language)
        let startedAt = Date()

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            self.currentProcess = process
            process.executableURL = URL(fileURLWithPath: python)
            var args = [
                scriptURL.path,
                "--audio", wavURL.path,
                "--model", model.modelID
            ]
            if let languageName {
                args += ["--language", languageName]
            }
            process.arguments = args

            var environment = ProcessInfo.processInfo.environment
            environment["PYTHONUNBUFFERED"] = "1"
            environment["HF_HOME"] = Storage.qwenASRCacheDirectory.path
            environment["TOKENIZERS_PARALLELISM"] = "false"
            environment["NO_COLOR"] = "1"
            process.environment = environment

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
                for progress in Self.parseProgress(from: text) {
                    let totalProgress = 0.20 + progress * 0.78
                    let elapsed = Date().timeIntervalSince(startedAt)
                    let remaining: TimeInterval? = totalProgress > 0.25 ? max(0, elapsed / Double(totalProgress) - elapsed) : nil
                    onProgress?(totalProgress, remaining)
                }
            }

            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                errorAccumulator.append(chunk)
            }

            let timeoutSeconds: Double = 3600
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

            process.terminationHandler = { [weak self] p in
                self?.currentProcess = nil
                timer.cancel()
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                let stdout = String(data: outputAccumulator.getData(), encoding: .utf8) ?? ""
                let stderr = String(data: errorAccumulator.getData(), encoding: .utf8) ?? ""

                if p.terminationStatus == 0 {
                    do {
                        let text = try Self.parseTranscript(from: stdout)
                        onProgress?(1.0, nil)
                        continuation.resume(returning: text)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                } else if timedOut.get() {
                    continuation.resume(throwing: TranscriptionError.transcriptionFailed("Qwen3-ASR transcription timed out after \(Int(timeoutSeconds)) seconds."))
                } else {
                    let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: TranscriptionError.transcriptionFailed(message.isEmpty ? "Qwen3-ASR exited with code \(p.terminationStatus)." : message))
                }
            }

            do {
                try process.run()
                onProgress?(0.20, nil)
            } catch {
                timer.cancel()
                continuation.resume(throwing: TranscriptionError.transcriptionFailed(error.localizedDescription))
            }
        }
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

    static var isRuntimeInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: runtimePythonPath)
    }

    static func findBasePythonBinary() -> String? {
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
            return runtimePythonPath
        }

        guard let basePython = findBasePythonBinary() else {
            throw TranscriptionError.transcriptionFailed("Qwen3-ASR runtime is not installed and Python 3.10+ was not found. Bundle a Python runtime with the app or install the Qwen runtime from Settings.")
        }

        try await installRuntime(basePythonPath: basePython)
        return runtimePythonPath
    }

    static func installRuntime(basePythonPath: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = installRuntimeSync(basePythonPath: basePythonPath)
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func installRuntimeSync(basePythonPath: String) -> Result<Void, TranscriptionError> {
        let venvDirectory = Storage.qwenASRRuntimeDirectory.appendingPathComponent("venv", isDirectory: true).path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            "-lc",
            """
            set -e
            mkdir -p \(shellQuoted(Storage.qwenASRRuntimeDirectory.path))
            \(shellQuoted(basePythonPath)) -m venv \(shellQuoted(venvDirectory))
            \(shellQuoted(runtimePythonPath)) -m pip install --upgrade pip
            \(shellQuoted(runtimePythonPath)) -m pip install --disable-pip-version-check mlx-qwen3-asr==0.3.5
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
                  let event = try? JSONDecoder().decode(QwenProgress.self, from: data),
                  let progress = event.progress
            else { return nil }
            return min(max(progress, 0), 1)
        }
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
            let writerInput: AVAssetWriterInput
            let trackOutput: AVAssetReaderTrackOutput
            let duration: Double
            var isResumed = false

            init(reader: AVAssetReader, writerInput: AVAssetWriterInput, trackOutput: AVAssetReaderTrackOutput, duration: Double) {
                self.reader = reader
                self.writerInput = writerInput
                self.trackOutput = trackOutput
                self.duration = duration
            }
        }

        let context = ConversionContext(reader: reader, writerInput: writerInput, trackOutput: trackOutput, duration: actualDuration)

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
                            if let error = context.reader.error {
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

    private func isAlready16kHzWav(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "wav" else { return false }
        guard let file = try? AVAudioFile(forReading: url) else { return false }
        let format = file.processingFormat
        return abs(format.sampleRate - 16000) < 100 && format.channelCount == 1
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private struct QwenResult: Decodable {
        let text: String
    }

    private struct QwenProgress: Decodable {
        let progress: Float?
    }

    private static let pythonHelper = #"""
import argparse
import json
import sys

def emit_progress(event):
    try:
        payload = json.dumps(event, ensure_ascii=False)
    except TypeError:
        payload = json.dumps({"event": str(event)}, ensure_ascii=False)
    print("__WHISPERFREE_QWEN_PROGRESS__" + payload, flush=True)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--audio", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--language")
    args = parser.parse_args()

    from mlx_qwen3_asr import transcribe

    result = transcribe(
        args.audio,
        model=args.model,
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
