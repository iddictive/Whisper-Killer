import XCTest
@testable import WhisperKiller

final class QwenASRRuntimeTests: XCTestCase {
    func testQwenModelMetadataDistinguishesFastAndQualityTiers() {
        XCTAssertEqual(QwenASRModel.fast.modelID, "Qwen/Qwen3-ASR-0.6B")
        XCTAssertEqual(QwenASRModel.quality.modelID, "Qwen/Qwen3-ASR-1.7B")
        XCTAssertTrue(QwenASRModel.fast.sizeDescription.contains("1.9 GB download"))
        XCTAssertTrue(QwenASRModel.quality.sizeDescription.contains("4.7 GB download"))
    }

    func testRuntimeProbeRejectsBrokenExecutable() async {
        do {
            try await QwenASRTranscriber.validateRuntime(at: "/usr/bin/false")
            XCTFail("A process that cannot import the pinned Qwen runtime must not be accepted")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testSavedFastModelChoiceSurvivesSettingsRoundTrip() throws {
        var settings = AppSettings()
        settings.qwenASRModel = .fast

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.qwenASRModel, .fast)
    }
}
