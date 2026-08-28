import Foundation
@preconcurrency import AVFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class CloudWhisper: TranscriptionEngine {
    private let apiKey: String
    private let model: CloudTranscriptionModel
    private static let maxUploadBytes = 25_000_000 // OpenAI 25 MB limit
    private static let targetUploadBytes = 24_500_000
    private static let speechSampleRate = 24_000
    private static let speechBitRates = [64_000, 56_000, 48_000, 40_000, 32_000]
    private static let containerOverheadFactor = 1.02

    init(apiKey: String, model: CloudTranscriptionModel) {
        self.apiKey = apiKey
        self.model = model
    }

    // MARK: - Public API

    func transcribe(audioURL: URL, language: String?, timeRange: CMTimeRange? = nil, onProgress: ((Float, TimeInterval?) -> Void)?) async throws -> String {
        guard !apiKey.isEmpty else {
            throw TranscriptionError.noAPIKey
        }

        let startTime = Date()

        // Stage 1: Prepare the file (0–10%)
        onProgress?(0.02, nil)
        
        let (uploadURL, shouldCleanup) = try await prepareAudioFile(audioURL, timeRange: timeRange, onProgress: onProgress)
        defer { if shouldCleanup { try? FileManager.default.removeItem(at: uploadURL) } }

        // Check if we need to chunk because the prepared upload is still too large.
        let asset = AVURLAsset(url: uploadURL)
        let totalDuration = try await asset.load(.duration).seconds
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: uploadURL.path)[.size] as? Int) ?? 0

        if fileSize > Self.maxUploadBytes {
            print("whisper_debug: ☁️ File needs chunking: \(fileSize) bytes, \(String(format: "%.0f", totalDuration))s duration")
            let result = try await transcribeInChunks(fileURL: uploadURL, totalDuration: totalDuration, language: language, startTime: startTime, onProgress: onProgress)
            onProgress?(1.0, nil)
            return TranscriptSanitizer.cleanWhisperText(result)
        }

        // Single-file upload path
        let text = try await uploadAndTranscribe(fileURL: uploadURL, language: language, onProgress: onProgress, progressRange: (0.10, 0.90))

        let elapsed = Date().timeIntervalSince(startTime)
        print("whisper_debug: ☁️ Transcription complete in \(String(format: "%.1f", elapsed))s")
        onProgress?(1.0, nil)

        return TranscriptSanitizer.cleanWhisperText(text)
    }

    // MARK: - Chunked Transcription

    /// Splits a long audio file into chunks and transcribes each one sequentially.
    private func transcribeInChunks(fileURL: URL, totalDuration: TimeInterval, language: String?, startTime: Date, onProgress: ((Float, TimeInterval?) -> Void)?) async throws -> String {
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        let chunkCount = Self.requiredChunkCount(fileSize: fileSize)
        let chunkDuration = totalDuration / Double(chunkCount)
        print("whisper_debug: ☁️ Splitting into \(chunkCount) size-based chunks of ~\(Int(chunkDuration))s each")

        var allTexts: [String] = []

        for i in 0..<chunkCount {
            let chunkStart = TimeInterval(i) * chunkDuration
            let chunkEnd = i == chunkCount - 1 ? totalDuration : min(chunkStart + chunkDuration, totalDuration)
            let chunkProgress = Float(i) / Float(chunkCount)
            let nextChunkProgress = Float(i + 1) / Float(chunkCount)

            print("whisper_debug: ☁️ Chunk \(i + 1)/\(chunkCount): \(String(format: "%.0f", chunkStart))s – \(String(format: "%.0f", chunkEnd))s")

            // Map overall progress: 10% to 95% across all chunks
            let overallStart = 0.10 + chunkProgress * 0.85
            let overallEnd = 0.10 + nextChunkProgress * 0.85
            onProgress?(overallStart, nil)

            // Export this chunk
            let chunkURL = try await exportChunk(from: fileURL, start: chunkStart, end: chunkEnd)
            defer { try? FileManager.default.removeItem(at: chunkURL) }

            let chunkSize = (try? FileManager.default.attributesOfItem(atPath: chunkURL.path)[.size] as? Int) ?? 0
            print("whisper_debug: ☁️ Chunk \(i + 1) size: \(chunkSize) bytes")

            let text = try await uploadAndTranscribe(fileURL: chunkURL, language: language, onProgress: onProgress, progressRange: (overallStart, overallEnd))
            if !text.isEmpty {
                allTexts.append(text)
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)
        print("whisper_debug: ☁️ Chunked transcription complete in \(String(format: "%.1f", elapsed))s (\(chunkCount) chunks)")

        return allTexts.joined(separator: "\n\n")
    }

    /// Export a time-range chunk using the same speech-optimized encoding as the full upload.
    private func exportChunk(from fileURL: URL, start: TimeInterval, end: TimeInterval) async throws -> URL {
        let range = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 44100),
            end: CMTime(seconds: end, preferredTimescale: 44100)
        )
        return try await extractAudioAsM4A(fileURL, timeRange: range, onProgress: nil)
    }

    // MARK: - Single Upload

    /// Uploads a single audio file to OpenAI Whisper API and returns the text.
    private func uploadAndTranscribe(fileURL: URL, language: String?, onProgress: ((Float, TimeInterval?) -> Void)?, progressRange: (Float, Float)) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 600

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendMultipart(boundary: boundary, name: "model", value: model.apiName)
        
        if let lang = language, lang != "auto" {
            body.appendMultipart(boundary: boundary, name: "language", value: lang)
        }
        if model.usesNativeDiarization {
            body.appendMultipart(boundary: boundary, name: "response_format", value: "diarized_json")
            body.appendMultipart(boundary: boundary, name: "chunking_strategy", value: "auto")
        } else if model == .whisper1 {
            body.appendMultipart(boundary: boundary, name: "response_format", value: "text")
        } else {
            body.appendMultipart(boundary: boundary, name: "response_format", value: "json")
            body.appendMultipart(boundary: boundary, name: "chunking_strategy", value: "auto")
        }

        let audioData = try Data(contentsOf: fileURL)
        let ext = fileURL.pathExtension.lowercased()
        let (fileName, mimeType) = Self.fileInfo(for: ext)
        body.appendMultipart(boundary: boundary, name: "file", fileName: fileName, mimeType: mimeType, fileData: audioData)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        print("whisper_debug: ☁️ Uploading \(audioData.count) bytes (\(ext)) to OpenAI Whisper API...")
        onProgress?(progressRange.0 + (progressRange.1 - progressRange.0) * 0.3, nil)

        let (data, httpResponse) = try await TransientHTTPRetry.data(for: request, label: "OpenAI transcription")

        onProgress?(progressRange.1, nil)

        if httpResponse.statusCode == 401 {
            throw TranscriptionError.networkError("Invalid API key. Please check your OpenAI API key in Settings → Engine & API.")
        }

        if httpResponse.statusCode == 429 {
            let errorText = openAIErrorMessage(from: data) ?? "OpenAI quota exceeded. Check billing and project limits."
            throw TranscriptionError.networkError("HTTP 429: \(errorText)")
        }

        if httpResponse.statusCode != 200 {
            let errorText = openAIErrorMessage(from: data) ?? String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.networkError("HTTP \(httpResponse.statusCode): \(errorText)")
        }

        if model == .whisper1 {
            guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw TranscriptionError.invalidResponse
            }
            return text
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranscriptionError.invalidResponse
        }

        if model.usesNativeDiarization {
            let diarizedText = Self.diarizedText(from: json)
            if !diarizedText.isEmpty {
                return diarizedText
            }
        }

        guard let text = json["text"] as? String else {
            throw TranscriptionError.invalidResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func diarizedText(from json: [String: Any]) -> String {
        guard let segments = json["segments"] as? [[String: Any]] else {
            return ""
        }

        var lines: [String] = []
        var currentSpeaker: String?
        var currentText = ""

        func flush() {
            let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let speaker = currentSpeaker?.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = speaker?.isEmpty == false ? speaker! : "Speaker"
            lines.append("\(label): \(text)")
            currentText = ""
        }

        for segment in segments {
            guard let text = segment["text"] as? String else { continue }
            let speaker = (segment["speaker"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if speaker != currentSpeaker {
                flush()
                currentSpeaker = speaker
            }

            if !currentText.isEmpty {
                currentText += " "
            }
            currentText += text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        flush()
        return lines.joined(separator: "\n")
    }

    private func openAIErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }
        return message
    }

    // MARK: - File Preparation

    /// Prepares the audio file for upload, extracting audio from video or compressing if too large.
    /// Returns (URL to upload, shouldCleanup).
    func prepareAudioFile(_ inputURL: URL, timeRange: CMTimeRange?, onProgress: ((Float, TimeInterval?) -> Void)?) async throws -> (URL, Bool) {
        let ext = inputURL.pathExtension.lowercased()
        let videoExtensions = Set(["mp4", "mov", "m4v", "avi", "mkv", "webm"])
        let isVideo = videoExtensions.contains(ext)

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: inputURL.path)[.size] as? Int) ?? 0

        if !isVideo && fileSize < Self.maxUploadBytes && timeRange == nil {
            // Small audio file and no trimming — upload directly
            print("whisper_debug: ☁️ File is small audio (\(fileSize) bytes), uploading directly")
            return (inputURL, false)
        }

        // A compatible compressed audio track does not need another lossy encode.
        // Remuxing keeps its original packets and is substantially faster for short videos.
        if let passthroughURL = try await extractPassthroughM4AIfEligible(
            inputURL,
            timeRange: timeRange,
            onProgress: onProgress
        ) {
            let outputSize = (try? FileManager.default.attributesOfItem(atPath: passthroughURL.path)[.size] as? Int) ?? 0
            print("whisper_debug: ☁️ Remuxed original audio without re-encoding: \(outputSize) bytes")
            return (passthroughURL, true)
        }

        // Decode and encode only when the original track cannot be safely remuxed under the limit.
        print("whisper_debug: ☁️ Extracting/compressing audio from \(ext) file (\(fileSize) bytes)...")
        let outputURL = try await extractAudioAsM4A(inputURL, timeRange: timeRange, onProgress: onProgress)
        let outputSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0
        print("whisper_debug: ☁️ Extracted audio: \(outputSize) bytes")

        return (outputURL, true)
    }

    /// Copies a compatible compressed audio track into an M4A container when it is predicted
    /// to fit comfortably below the upload limit. Returns nil when re-encoding is required.
    private func extractPassthroughM4AIfEligible(
        _ inputURL: URL,
        timeRange: CMTimeRange?,
        onProgress: ((Float, TimeInterval?) -> Void)?
    ) async throws -> URL? {
        do {
            return try await attemptPassthroughM4A(
                inputURL,
                timeRange: timeRange,
                onProgress: onProgress
            )
        } catch {
            if Task.isCancelled || error is CancellationError {
                throw CancellationError()
            }
            return nil
        }
    }

    private func attemptPassthroughM4A(
        _ inputURL: URL,
        timeRange: CMTimeRange?,
        onProgress: ((Float, TimeInterval?) -> Void)?
    ) async throws -> URL? {
        let asset = AVURLAsset(url: inputURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            return nil
        }

        let duration = if let timeRange {
            timeRange.duration.seconds
        } else {
            try await asset.load(.duration).seconds
        }
        let estimatedDataRate = Double(try await audioTrack.load(.estimatedDataRate))
        guard duration.isFinite, duration > 0, estimatedDataRate > 0 else {
            return nil
        }

        guard Self.isPassthroughEligible(
            audioTrackCount: audioTracks.count,
            duration: duration,
            estimatedDataRate: estimatedDataRate
        ) else {
            return nil
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough),
              session.supportedFileTypes.contains(.m4a) else {
            return nil
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud_audio_passthrough_\(UUID().uuidString).m4a")
        session.outputURL = outputURL
        session.outputFileType = .m4a
        if let timeRange {
            session.timeRange = timeRange
        }

        final class PassthroughExportContext: @unchecked Sendable {
            let session: AVAssetExportSession

            init(session: AVAssetExportSession) {
                self.session = session
            }
        }
        let context = PassthroughExportContext(session: session)

        let progressTask = Task {
            while !Task.isCancelled {
                onProgress?(0.02 + context.session.progress * 0.08, nil)
                try await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        await withTaskCancellationHandler {
            await context.session.export()
        } onCancel: {
            context.session.cancelExport()
        }
        progressTask.cancel()

        if Task.isCancelled {
            try? FileManager.default.removeItem(at: outputURL)
            throw CancellationError()
        }

        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }

        let outputSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0
        guard outputSize > 0, outputSize <= Self.targetUploadBytes else {
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }

        onProgress?(0.10, nil)
        return outputURL
    }

    /// Extracts speech audio as mono AAC at the highest bitrate that fits the upload budget.
    func extractAudioAsM4A(_ inputURL: URL, timeRange: CMTimeRange?, onProgress: ((Float, TimeInterval?) -> Void)?) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud_audio_\(UUID().uuidString).m4a")

        let asset = AVURLAsset(url: inputURL)
        let duration = if let timeRange {
            timeRange.duration.seconds
        } else {
            try await asset.load(.duration).seconds
        }

        guard duration.isFinite, duration > 0 else {
            throw TranscriptionError.transcriptionFailed("Audio is empty")
        }

        // Verify that there is an audio track
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw TranscriptionError.transcriptionFailed("No audio track found in file")
        }

        let reader = try AVAssetReader(asset: asset)
        if let timeRange {
            reader.timeRange = timeRange
        }

        let readerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.speechSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerSettings)
        guard reader.canAdd(trackOutput) else {
            throw TranscriptionError.transcriptionFailed("Cannot read the audio track")
        }
        reader.add(trackOutput)

        let bitRate = Self.speechBitRate(for: duration)
        let writerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: Self.speechSampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: bitRate,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerSettings)
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else {
            throw TranscriptionError.transcriptionFailed("Cannot encode the audio track")
        }
        writer.add(writerInput)

        guard reader.startReading() else {
            throw TranscriptionError.transcriptionFailed(reader.error?.localizedDescription ?? "Audio reading failed")
        }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw TranscriptionError.transcriptionFailed(writer.error?.localizedDescription ?? "Audio encoding failed")
        }
        writer.startSession(atSourceTime: timeRange?.start ?? .zero)

        final class EncodingContext: @unchecked Sendable {
            let reader: AVAssetReader
            let writer: AVAssetWriter
            let writerInput: AVAssetWriterInput
            let trackOutput: AVAssetReaderTrackOutput
            let duration: TimeInterval
            let startTime: TimeInterval
            let onProgress: ((Float, TimeInterval?) -> Void)?
            var didResume = false

            init(
                reader: AVAssetReader,
                writer: AVAssetWriter,
                writerInput: AVAssetWriterInput,
                trackOutput: AVAssetReaderTrackOutput,
                duration: TimeInterval,
                startTime: TimeInterval,
                onProgress: ((Float, TimeInterval?) -> Void)?
            ) {
                self.reader = reader
                self.writer = writer
                self.writerInput = writerInput
                self.trackOutput = trackOutput
                self.duration = duration
                self.startTime = startTime
                self.onProgress = onProgress
            }
        }

        let context = EncodingContext(
            reader: reader,
            writer: writer,
            writerInput: writerInput,
            trackOutput: trackOutput,
            duration: duration,
            startTime: timeRange?.start.seconds ?? 0,
            onProgress: onProgress
        )

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let queue = DispatchQueue(label: "cloudSpeechAudioEncodeQueue", qos: .userInitiated)
                context.writerInput.requestMediaDataWhenReady(on: queue) {
                    while context.writerInput.isReadyForMoreMediaData {
                        if let buffer = context.trackOutput.copyNextSampleBuffer() {
                            let timestamp = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
                            let relativeTime = max(0, timestamp - context.startTime)
                            let progress = Float(min(1, relativeTime / context.duration))
                            context.onProgress?(0.02 + progress * 0.08, nil)

                            if !context.writerInput.append(buffer) {
                                guard !context.didResume else { return }
                                context.didResume = true
                                continuation.resume(throwing: context.writer.error ?? TranscriptionError.transcriptionFailed("Audio encoding failed"))
                                return
                            }
                        } else {
                            guard !context.didResume else { return }
                            context.didResume = true
                            context.writerInput.markAsFinished()
                            if let error = context.reader.error ?? context.writer.error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume()
                            }
                            return
                        }
                    }
                }
            }

            await writer.finishWriting()
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw TranscriptionError.transcriptionFailed("Audio extraction failed: \(error.localizedDescription)")
        }

        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: outputURL)
            throw TranscriptionError.transcriptionFailed(writer.error?.localizedDescription ?? "Audio encoding did not complete")
        }

        onProgress?(0.10, nil)
        let outputSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0
        print("whisper_debug: ☁️ Encoded speech audio at \(bitRate) bps mono/\(Self.speechSampleRate) Hz: \(outputSize) bytes")
        return outputURL
    }

    static func speechBitRate(for duration: TimeInterval) -> Int {
        guard duration.isFinite, duration > 0 else { return speechBitRates.last! }

        return speechBitRates.first { bitRate in
            let projectedBytes = duration * Double(bitRate) / 8 * containerOverheadFactor
            return projectedBytes <= Double(targetUploadBytes)
        } ?? speechBitRates.last!
    }

    static func requiredChunkCount(fileSize: Int) -> Int {
        guard fileSize > 0 else { return 1 }
        return max(1, Int(ceil(Double(fileSize) / Double(targetUploadBytes))))
    }

    static func isPassthroughEligible(
        audioTrackCount: Int,
        duration: TimeInterval,
        estimatedDataRate: Double
    ) -> Bool {
        guard audioTrackCount == 1,
              duration.isFinite,
              duration > 0,
              estimatedDataRate.isFinite,
              estimatedDataRate > 0 else {
            return false
        }
        let projectedBytes = duration * estimatedDataRate / 8 * containerOverheadFactor
        return projectedBytes <= Double(targetUploadBytes)
    }

    // MARK: - Helpers

    private static func fileInfo(for ext: String) -> (fileName: String, mimeType: String) {
        switch ext {
        case "mp3":  return ("audio.mp3", "audio/mpeg")
        case "mp4":  return ("audio.mp4", "audio/mp4")
        case "m4a":  return ("audio.m4a", "audio/mp4")
        case "wav":  return ("audio.wav", "audio/wav")
        case "webm": return ("audio.webm", "audio/webm")
        case "ogg":  return ("audio.ogg", "audio/ogg")
        case "flac": return ("audio.flac", "audio/flac")
        default:     return ("audio.\(ext)", "application/octet-stream")
        }
    }

    /// Returns the duration of an audio/video file in seconds.
    static func fileDuration(url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        return try? await asset.load(.duration).seconds
    }
}

// MARK: - Multipart Form Data Helpers

extension Data {
    mutating func appendMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipart(boundary: String, name: String, fileName: String, mimeType: String, fileData: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(fileData)
        append("\r\n".data(using: .utf8)!)
    }
}
