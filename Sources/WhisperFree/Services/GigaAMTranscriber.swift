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
                if let text = String(data: chunk, encoding: .utf8) {
                    for progress in Self.parseProgress(from: text) {
                        onProgress?(0.12 + progress * 0.83, nil)
                    }
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

    private static func parseProgress(from stdoutChunk: String) -> [Float] {
        let marker = "__WHISPERFREE_GIGAAM_PROGRESS__"
        return stdoutChunk.components(separatedBy: .newlines).compactMap { line in
            guard line.hasPrefix(marker) else { return nil }
            let payload = String(line.dropFirst(marker.count))
            guard let value = Float(payload) else { return nil }
            return min(max(value, 0), 1)
        }
    }

    private struct GigaAMResult: Decodable {
        let text: String
    }

    private static let pythonHelper = #"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

SETUP = "mkdir -p ~/Library/Application\\ Support/WhisperKiller/GigaAM && python3.12 -m venv ~/Library/Application\\ Support/WhisperKiller/GigaAM/venv && ~/Library/Application\\ Support/WhisperKiller/GigaAM/venv/bin/python -m pip install --trusted-host pypi.org --trusted-host files.pythonhosted.org torch torchaudio transformers 'huggingface-hub<1.0' pyannote-audio torchcodec hydra-core omegaconf sentencepiece"
SHORT_LIMIT_SECONDS = 23.5
CHUNK_SECONDS = 22.0

def fail(message, code=1):
    print(message, file=sys.stderr)
    sys.exit(code)

def require_binary(name):
    path = shutil.which(name)
    if path:
        return path
    fail(f"{name} not found. Install ffmpeg to use GigaAM transcription.", 70)

def media_duration_seconds(audio_path):
    ffprobe = require_binary("ffprobe")
    completed = subprocess.run(
        [
            ffprobe,
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            audio_path,
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    try:
        return float(completed.stdout.strip())
    except ValueError as exc:
        raise RuntimeError("Could not determine audio duration") from exc

def emit_progress(value):
    print("__WHISPERFREE_GIGAAM_PROGRESS__" + f"{max(0.0, min(1.0, value)):.4f}", flush=True)

def normalize_text(value):
    if isinstance(value, dict):
        return str(value.get("text", value.get("transcription", "")))
    if isinstance(value, (list, tuple)):
        parts = []
        for item in value:
            if isinstance(item, dict):
                parts.append(str(item.get("text", item.get("transcription", ""))))
            else:
                parts.append(str(item))
        return " ".join(part for part in parts if part)
    return str(value)

def export_chunk(ffmpeg, audio_path, output_path, start, duration):
    subprocess.run(
        [
            ffmpeg,
            "-nostdin",
            "-hide_banner",
            "-loglevel", "error",
            "-ss", f"{start:.3f}",
            "-t", f"{duration:.3f}",
            "-i", audio_path,
            "-vn",
            "-ac", "1",
            "-ar", "16000",
            "-acodec", "pcm_s16le",
            output_path,
        ],
        check=True,
    )

def fixed_chunks(total_duration):
    start = 0.0
    while start < total_duration:
        remaining = total_duration - start
        if remaining <= SHORT_LIMIT_SECONDS:
            end = total_duration
        else:
            end = min(start + CHUNK_SECONDS, total_duration)
        yield start, end
        start = end

def transcribe_audio(model, audio_path):
    duration = media_duration_seconds(audio_path)
    if duration <= SHORT_LIMIT_SECONDS:
        emit_progress(0.0)
        text = normalize_text(model.transcribe(audio_path))
        emit_progress(1.0)
        return text

    ffmpeg = require_binary("ffmpeg")
    ranges = list(fixed_chunks(duration))
    texts = []
    with tempfile.TemporaryDirectory(prefix="whisperkiller_gigaam_chunks_") as tmpdir:
        for index, (start, end) in enumerate(ranges):
            chunk_path = os.path.join(tmpdir, f"chunk_{index:04d}.wav")
            export_chunk(ffmpeg, audio_path, chunk_path, start, end - start)
            text = normalize_text(model.transcribe(chunk_path)).strip()
            if text:
                texts.append(text)
            emit_progress((index + 1) / len(ranges))
    return "\n\n".join(texts)

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
    text = transcribe_audio(model, args.audio)
except ModuleNotFoundError as exc:
    fail(f"Missing Python package '{exc.name}'. Run: {SETUP}", 70)
except subprocess.CalledProcessError as exc:
    stderr = exc.stderr.decode("utf-8", errors="replace") if isinstance(exc.stderr, bytes) else (exc.stderr or "")
    fail(stderr.strip() or str(exc), 1)
except Exception as exc:
    fail(str(exc), 1)

print("__WHISPERFREE_GIGAAM_RESULT__" + json.dumps({"text": normalize_text(text)}, ensure_ascii=False))
"""#
}
