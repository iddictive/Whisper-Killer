import Foundation
import CoreMedia

/// Experimental Russian ASR backend using ai-sage/GigaAM-v3 through a local Python runtime.
final class GigaAMTranscriber: TranscriptionEngine, @unchecked Sendable {
    private var currentProcess: Process?

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
        guard timeRange == nil else {
            throw TranscriptionError.transcriptionFailed("GigaAM experiment does not support partial file ranges yet. Use the full file or switch to Whisper.")
        }

        guard let python = Self.findPythonBinary() else {
            throw TranscriptionError.transcriptionFailed("Python 3 not found. Install Python 3, then install the GigaAM packages from Settings.")
        }

        let scriptURL = try Self.writeHelperScript()
        onProgress?(0.05, nil)

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            currentProcess = process
            process.executableURL = URL(fileURLWithPath: python)
            process.arguments = [
                scriptURL.path,
                "--audio", audioURL.path,
                "--revision", "e2e_rnnt"
            ]

            var environment = ProcessInfo.processInfo.environment
            environment["PYTHONUNBUFFERED"] = "1"
            environment["USE_TF"] = "0"
            environment["USE_TORCH"] = "1"
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
                    continuation.resume(throwing: TranscriptionError.transcriptionFailed("GigaAM transcription timed out after \(Int(timeoutSeconds)) seconds."))
                } else {
                    let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: TranscriptionError.transcriptionFailed(message.isEmpty ? "GigaAM process exited with code \(p.terminationStatus)." : message))
                }
            }

            do {
                try process.run()
                onProgress?(0.12, nil)
            } catch {
                timer.cancel()
                continuation.resume(throwing: TranscriptionError.transcriptionFailed(error.localizedDescription))
            }
        }
    }

    static func findPythonBinary() -> String? {
        if FileManager.default.isExecutableFile(atPath: virtualEnvironmentPythonPath) {
            return virtualEnvironmentPythonPath
        }

        return findBasePythonBinary()
    }

    static func findBasePythonBinary() -> String? {
        let possiblePaths = [
            "/usr/local/bin/python3.12",
            "/opt/homebrew/bin/python3.12",
            "/usr/local/bin/python3.11",
            "/opt/homebrew/bin/python3.11",
            "/usr/local/bin/python3.10",
            "/opt/homebrew/bin/python3.10",
            "/usr/local/bin/python3.13",
            "/opt/homebrew/bin/python3.13",
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

    static let setupCommand = "mkdir -p ~/Library/Application\\ Support/WhisperKiller/GigaAM && python3.12 -m venv ~/Library/Application\\ Support/WhisperKiller/GigaAM/venv && ~/Library/Application\\ Support/WhisperKiller/GigaAM/venv/bin/python -m pip install --trusted-host pypi.org --trusted-host files.pythonhosted.org torch torchaudio transformers 'huggingface-hub<1.0' pyannote-audio torchcodec hydra-core omegaconf sentencepiece"

    static var virtualEnvironmentPythonPath: String {
        virtualEnvironmentPython.path
    }

    private static var virtualEnvironmentPython: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("WhisperKiller/GigaAM/venv/bin/python", isDirectory: false)
    }

    private static func writeHelperScript() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisperkiller_gigaam_transcribe.py")
        try pythonHelper.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func parseTranscript(from stdout: String) throws -> String {
        let marker = "__WHISPERFREE_GIGAAM_RESULT__"
        guard let line = stdout.components(separatedBy: .newlines).last(where: { $0.hasPrefix(marker) }) else {
            throw TranscriptionError.invalidResponse
        }

        let payload = String(line.dropFirst(marker.count))
        let data = Data(payload.utf8)
        let result = try JSONDecoder().decode(GigaAMResult.self, from: data)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct GigaAMResult: Decodable {
        let text: String
    }

    private static let pythonHelper = #"""
import argparse
import json
import sys

SETUP = "mkdir -p ~/Library/Application\\ Support/WhisperKiller/GigaAM && python3.12 -m venv ~/Library/Application\\ Support/WhisperKiller/GigaAM/venv && ~/Library/Application\\ Support/WhisperKiller/GigaAM/venv/bin/python -m pip install --trusted-host pypi.org --trusted-host files.pythonhosted.org torch torchaudio transformers 'huggingface-hub<1.0' pyannote-audio torchcodec hydra-core omegaconf sentencepiece"

def fail(message, code=1):
    print(message, file=sys.stderr)
    sys.exit(code)

parser = argparse.ArgumentParser()
parser.add_argument("--audio", required=True)
parser.add_argument("--revision", default="e2e_rnnt")
args = parser.parse_args()

if sys.version_info >= (3, 14):
    fail(f"GigaAM dependencies are not ready for Python {sys.version_info.major}.{sys.version_info.minor}. Use Python 3.10-3.13. Run: {SETUP}", 70)

try:
    from transformers import AutoModel
except ModuleNotFoundError as exc:
    fail(f"Missing Python package '{exc.name}'. Run: {SETUP}", 70)

try:
    model = AutoModel.from_pretrained(
        "ai-sage/GigaAM-v3",
        revision=args.revision,
        trust_remote_code=True,
    )
    model = model.float()
    text = model.transcribe(args.audio)
except ModuleNotFoundError as exc:
    fail(f"Missing Python package '{exc.name}'. Run: {SETUP}", 70)
except Exception as exc:
    fail(str(exc), 1)

if isinstance(text, dict):
    text = text.get("text", "")
elif isinstance(text, (list, tuple)):
    text = " ".join(str(item.get("text", item) if isinstance(item, dict) else item) for item in text)
else:
    text = str(text)

print("__WHISPERFREE_GIGAAM_RESULT__" + json.dumps({"text": text}, ensure_ascii=False))
"""#
}
