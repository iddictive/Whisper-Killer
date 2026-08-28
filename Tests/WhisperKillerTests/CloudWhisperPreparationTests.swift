import XCTest
import AVFoundation
@testable import WhisperKiller

final class CloudWhisperPreparationTests: XCTestCase {
    func testSixtyFiveMinuteSpeechUsesBitRateThatFitsOneUpload() {
        let duration: TimeInterval = 3_950.165

        XCTAssertEqual(CloudWhisper.speechBitRate(for: duration), 48_000)
        XCTAssertEqual(CloudWhisper.requiredChunkCount(fileSize: 24_500_000), 1)
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
        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud_stereo_source_\(UUID().uuidString).wav")
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        )!
        let frameCount = AVAudioFrameCount(48_000 * 5)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        for channel in 0..<Int(format.channelCount) {
            guard let samples = buffer.floatChannelData?[channel] else { continue }
            for frame in 0..<Int(frameCount) {
                samples[frame] = sin(Float(frame) * 2 * .pi * 440 / 48_000) * 0.1
            }
        }
        do {
            let sourceFile = try AVAudioFile(forWriting: inputURL, settings: format.settings)
            try sourceFile.write(from: buffer)
        }
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
}
