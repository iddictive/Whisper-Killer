import XCTest
import AVFoundation
@testable import WhisperKiller

final class CloudWhisperPreparationTests: XCTestCase {
    func testSixtyFiveMinuteSpeechUsesBitRateThatFitsOneUpload() {
        let duration: TimeInterval = 3_950.165

        XCTAssertEqual(CloudWhisper.speechBitRate(for: duration), 48_000)
        XCTAssertEqual(CloudWhisper.requiredChunkCount(fileSize: 24_500_000), 1)
        XCTAssertFalse(
            CloudWhisper.isPassthroughEligible(
                audioTrackCount: 1,
                duration: duration,
                estimatedDataRate: 128_000
            ),
            "A long 128 kbps source must skip remuxing and use the one-upload speech encoder"
        )
    }

    func testShortCompatibleTrackFitsPassthroughBudget() {
        XCTAssertTrue(
            CloudWhisper.isPassthroughEligible(
                audioTrackCount: 1,
                duration: 1_200,
                estimatedDataRate: 128_000
            )
        )
        XCTAssertFalse(
            CloudWhisper.isPassthroughEligible(
                audioTrackCount: 2,
                duration: 1_200,
                estimatedDataRate: 128_000
            ),
            "Multi-track media must keep the established first-track encoding path"
        )
    }

    func testPreparedPayloadUsesMinimumSizeBasedChunkCount() {
        XCTAssertEqual(CloudWhisper.requiredChunkCount(fileSize: 63_961_037), 3)
        XCTAssertEqual(CloudWhisper.requiredChunkCount(fileSize: 24_500_001), 2)
    }

    func testShortAudioKeepsHighestSpeechBitRate() {
        XCTAssertEqual(CloudWhisper.speechBitRate(for: 300), 64_000)
    }

    func testSmallAudioWithoutTrimmingPassesThroughUnchanged() async throws {
        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud_passthrough_\(UUID().uuidString).m4a")
        try Data([0x00, 0x01, 0x02]).write(to: inputURL)
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let engine = CloudWhisper(apiKey: "test", model: .gpt4oTranscribe)
        let prepared = try await engine.prepareAudioFile(inputURL, timeRange: nil, onProgress: nil)

        XCTAssertEqual(prepared.0, inputURL)
        XCTAssertFalse(prepared.1)
    }

    func testSpeechEncodingProducesReadableMonoM4A() async throws {
        let inputURL = try makeStereoWAV(duration: 5)
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let engine = CloudWhisper(apiKey: "test", model: .gpt4oTranscribe)
        let outputURL = try await engine.extractAudioAsM4A(inputURL, timeRange: nil, onProgress: nil)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let asset = AVURLAsset(url: outputURL)
        let duration = try await asset.load(.duration).seconds
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let track = try XCTUnwrap(tracks.first)
        let descriptions = try await track.load(.formatDescriptions)
        let description = try XCTUnwrap(descriptions.first)
        let streamDescription = try XCTUnwrap(CMAudioFormatDescriptionGetStreamBasicDescription(description))
        let fileSize = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int
        )

        XCTAssertEqual(duration, 5, accuracy: 0.05)
        XCTAssertEqual(streamDescription.pointee.mSampleRate, 24_000, accuracy: 1)
        XCTAssertEqual(streamDescription.pointee.mChannelsPerFrame, 1)
        XCTAssertLessThan(fileSize, 60_000)
    }

    func testCompatibleAACVideoIsRemuxedWithoutReencoding() async throws {
        let wavURL = try makeStereoWAV(duration: 2)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        let engine = CloudWhisper(apiKey: "test", model: .gpt4oTranscribe)
        let encodedURL = try await engine.extractAudioAsM4A(wavURL, timeRange: nil, onProgress: nil)
        defer { try? FileManager.default.removeItem(at: encodedURL) }

        let videoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud_aac_source_\(UUID().uuidString).mp4")
        try FileManager.default.copyItem(at: encodedURL, to: videoURL)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let prepared = try await engine.prepareAudioFile(videoURL, timeRange: nil, onProgress: nil)
        defer { if prepared.1 { try? FileManager.default.removeItem(at: prepared.0) } }

        XCTAssertTrue(prepared.1)
        XCTAssertNotEqual(prepared.0, videoURL)
        let preparedPayload = try await compressedAudioPayload(at: prepared.0)
        let sourcePayload = try await compressedAudioPayload(at: videoURL)
        XCTAssertEqual(
            preparedPayload,
            sourcePayload,
            "Eligible AAC must be remuxed instead of decoded and encoded again"
        )
    }

    private func makeStereoWAV(duration: TimeInterval) throws -> URL {
        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud_stereo_source_\(UUID().uuidString).wav")
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        )!
        let frameCount = AVAudioFrameCount(48_000 * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        for channel in 0..<Int(format.channelCount) {
            guard let samples = buffer.floatChannelData?[channel] else { continue }
            for frame in 0..<Int(frameCount) {
                samples[frame] = sin(Float(frame) * 2 * .pi * 440 / 48_000) * 0.1
            }
        }

        let sourceFile = try AVAudioFile(forWriting: inputURL, settings: format.settings)
        try sourceFile.write(from: buffer)
        return inputURL
    }

    private func compressedAudioPayload(at url: URL) async throws -> Data {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        XCTAssertTrue(reader.canAdd(output))
        reader.add(output)
        XCTAssertTrue(reader.startReading())

        var payload = Data()
        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            var bytes = Data(count: length)
            let status = bytes.withUnsafeMutableBytes { buffer in
                CMBlockBufferCopyDataBytes(
                    blockBuffer,
                    atOffset: 0,
                    dataLength: length,
                    destination: buffer.baseAddress!
                )
            }
            XCTAssertEqual(status, noErr)
            payload.append(bytes)
        }

        XCTAssertEqual(reader.status, .completed)
        return payload
    }
}
