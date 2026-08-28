import XCTest
@testable import WhisperKiller

final class OpenAIModelCatalogTests: XCTestCase {
    func testBootstrapCatalogContainsEveryKnownBaseTranscriptionModel() {
        XCTAssertEqual(
            OpenAIModelCatalog.bootstrapTranscriptionModels,
            [.gptTranscribe, .whisper1, .gpt4oMiniTranscribe, .gpt4oTranscribe]
        )
    }

    func testTranscriptionCatalogIncludesFutureStableModelsWithoutCodeChanges() {
        let models = OpenAIModelCatalog.relevantTranscriptionModels(from: [
            "gpt-transcribe",
            "whisper-1",
            "gpt-4o-mini-transcribe",
            "gpt-4o-transcribe",
            "gpt-4o-transcribe-diarize",
            "gpt-5.7-transcribe",
            "gpt-5.7-mini-transcribe",
            "gpt-5.7-transcribe-diarize"
        ])

        XCTAssertEqual(Set(models.map(\.apiName)), Set([
            "gpt-transcribe",
            "whisper-1",
            "gpt-4o-mini-transcribe",
            "gpt-4o-transcribe",
            "gpt-4o-transcribe-diarize",
            "gpt-5.7-transcribe",
            "gpt-5.7-mini-transcribe",
            "gpt-5.7-transcribe-diarize"
        ]))
        XCTAssertEqual(
            Set(models.filter(\.usesNativeDiarization).map(\.apiName)),
            Set(["gpt-4o-transcribe-diarize", "gpt-5.7-transcribe-diarize"])
        )
        XCTAssertFalse(
            OpenAIModelCatalog(modelIDs: models.map(\.apiName))
                .baseTranscriptionModels
                .contains(CloudTranscriptionModel(rawValue: "gpt-5.7-transcribe-diarize"))
        )
    }

    func testTranscriptionCatalogRejectsSnapshotsAndOtherModelFamilies() {
        let models = OpenAIModelCatalog.relevantTranscriptionModels(from: [
            "gpt-5.7",
            "gpt-image-2",
            "gpt-4o-mini-tts",
            "gpt-live-transcribe",
            "gpt-realtime-whisper",
            "gpt-5.7-transcribe-2026-07-24",
            "omni-moderation-latest"
        ])

        XCTAssertTrue(models.isEmpty)
    }

    func testGPTTranscribeIsTheNewSettingsDefaultWithKnownPricing() throws {
        let settings = AppSettings()

        XCTAssertEqual(settings.cloudTranscriptionModel, .gptTranscribe)
        XCTAssertEqual(CloudTranscriptionModel.gptTranscribe.pricePerMinute, 0.0045)

        var savedSettings = settings
        savedSettings.cloudTranscriptionModel = .whisper1
        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONEncoder().encode(savedSettings)
        )
        XCTAssertEqual(decoded.cloudTranscriptionModel, .whisper1)
    }

    func testUnknownFutureModelRoundTripsAndDoesNotInventPricing() throws {
        let model = CloudTranscriptionModel(rawValue: "gpt-6-mini-transcribe")
        let data = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(CloudTranscriptionModel.self, from: data)

        XCTAssertEqual(decoded, model)
        XCTAssertNil(model.pricePerMinute)
        XCTAssertNil(UsageLog.estimateAudioCost(durationSeconds: 60, model: model))
        XCTAssertTrue(
            CloudTranscriptionModel(rawValue: "gpt-6-transcribe-diarize")
                .usesNativeDiarization
        )
    }

    func testMissingCompatibleDiarizationModelDisablesNativeDiarization() {
        var settings = AppSettings()
        settings.apiKey = "test-key"
        settings.engineType = .cloud
        settings.enableSpeakerDiarization = true
        settings.cloudTranscriptionModel = CloudTranscriptionModel(rawValue: "gpt-6-mini-transcribe")
        settings.cloudDiarizationModel = nil

        XCTAssertFalse(settings.canUseSpeakerDiarization)
        XCTAssertFalse(settings.usesNativeCloudSpeakerDiarization)
        XCTAssertEqual(settings.effectiveCloudTranscriptionModel, settings.cloudTranscriptionModel)
    }
}
