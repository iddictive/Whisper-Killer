import Foundation
import FluidAudio
import XCTest
@testable import WhisperKiller

final class ParakeetRuntimeTests: XCTestCase {
    private var cacheDirectory: URL!
    private var modelDirectory: URL!

    override func setUpWithError() throws {
        cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ParakeetRuntimeTests-\(UUID().uuidString)", isDirectory: true)
        modelDirectory = cacheDirectory.appendingPathComponent("parakeet-tdt-0.6b-v3", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let cacheDirectory, FileManager.default.fileExists(atPath: cacheDirectory.path) {
            try FileManager.default.removeItem(at: cacheDirectory)
        }
    }

    func testParakeetEngineRoundTripsThroughSettings() throws {
        XCTAssertEqual(AppSettings().parakeetModel, .ultra)
        for model in ParakeetModel.allCases {
            var settings = AppSettings()
            settings.engineType = .parakeet
            settings.parakeetModel = model

            let data = try JSONEncoder().encode(settings)
            let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

            XCTAssertEqual(decoded.engineType, .parakeet)
            XCTAssertEqual(decoded.parakeetModel, model)
            XCTAssertTrue(TranscriptionEngineFactory.create(for: .parakeet, settings: decoded) is ParakeetTranscriber)

            var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            legacy.removeValue(forKey: "parakeetModel")
            let legacyData = try JSONSerialization.data(withJSONObject: legacy)
            XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: legacyData).parakeetModel, .v3)
        }
    }

    func testMissingModelDirectoryIsNotInstalled() throws {
        XCTAssertEqual(ParakeetModelStore.inspect(at: modelDirectory), .notInstalled)
        try createCandidateModelDirectory()
        let ultraDirectory = cacheDirectory.appendingPathComponent(ParakeetModel.ultra.directoryName, isDirectory: true)
        XCTAssertEqual(ParakeetModelStore.inspect(at: ultraDirectory), .notInstalled)
        XCTAssertEqual(ParakeetModelStore.inspect(at: modelDirectory), .candidate)
    }

    func testPartialDownloadIsNotCandidate() throws {
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: modelDirectory.appendingPathComponent("Encoder.mlmodelc.partial"))

        XCTAssertEqual(ParakeetModelStore.inspect(at: modelDirectory), .partial)
    }

    func testMissingRequiredArtifactIsPartial() throws {
        try createCandidateModelDirectory()
        try FileManager.default.removeItem(at: modelDirectory.appendingPathComponent("parakeet_vocab.json"))

        XCTAssertEqual(ParakeetModelStore.inspect(at: modelDirectory), .partial)
    }

    func testCompleteRequiredPathsAreOnlyACandidateUntilFluidAudioLoadsThem() throws {
        for model in ParakeetModel.allCases {
            let directory = cacheDirectory.appendingPathComponent(model.directoryName, isDirectory: true)
            try createCandidateModelDirectory(at: directory)
            XCTAssertEqual(ParakeetModelStore.inspect(at: directory), .candidate)
        }
    }

    func testCompiledBundleWithoutCoreMLPayloadIsPartial() throws {
        try createCandidateModelDirectory()
        let payload = modelDirectory
            .appendingPathComponent("Encoder.mlmodelc")
            .appendingPathComponent("coremldata.bin")
        try FileManager.default.removeItem(at: payload)

        XCTAssertEqual(ParakeetModelStore.inspect(at: modelDirectory), .partial)
    }

    func testLanguageHintAcceptsRussianAndAutoDetect() throws {
        XCTAssertEqual(try ParakeetTranscriber.languageHint(for: "ru")?.rawValue, "ru")
        XCTAssertNil(try ParakeetTranscriber.languageHint(for: "auto"))
        XCTAssertNil(try ParakeetTranscriber.languageHint(for: nil))
    }

    func testLanguageHintRejectsUnsupportedLanguages() {
        XCTAssertThrowsError(try ParakeetTranscriber.languageHint(for: "ja"))
    }

    func testOfflineLoadFailurePreservesCandidateCache() async throws {
        ModelHub.offlineMode = true

        for model in ParakeetModel.allCases {
            let directory = cacheDirectory.appendingPathComponent(model.directoryName, isDirectory: true)
            try createCandidateModelDirectory(at: directory)
            do {
                _ = try await ParakeetFluidAudioOperations.shared.load(from: directory, model: model)
                XCTFail("Synthetic Core ML bundles must not load")
            } catch {
                XCTAssertTrue(ModelHub.offlineMode)
                XCTAssertEqual(ParakeetModelStore.inspect(at: directory), .candidate)
            }
        }
    }

    private func createCandidateModelDirectory(at directory: URL? = nil) throws {
        let directory = directory ?? modelDirectory!
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for relativePath in ParakeetModelStore.requiredRelativePaths {
            let url = directory.appendingPathComponent(relativePath)
            if relativePath.hasSuffix(".mlmodelc") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try Data("model".utf8).write(to: url.appendingPathComponent("coremldata.bin"))
            } else {
                try Data("{}".utf8).write(to: url)
            }
        }
    }
}
