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
        var settings = AppSettings()
        settings.engineType = .parakeet

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.engineType, .parakeet)
        XCTAssertTrue(TranscriptionEngineFactory.create(for: .parakeet, settings: decoded) is ParakeetTranscriber)
    }

    func testMissingModelDirectoryIsNotInstalled() {
        XCTAssertEqual(ParakeetModelStore.inspect(at: modelDirectory), .notInstalled)
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
        try createCandidateModelDirectory()

        XCTAssertEqual(ParakeetModelStore.inspect(at: modelDirectory), .candidate)
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
        try createCandidateModelDirectory()
        ModelHub.offlineMode = true

        do {
            _ = try await ParakeetFluidAudioOperations.shared.load(from: modelDirectory)
            XCTFail("Synthetic Core ML bundles must not load")
        } catch {
            XCTAssertTrue(ModelHub.offlineMode)
            XCTAssertEqual(ParakeetModelStore.inspect(at: modelDirectory), .candidate)
        }
    }

    private func createCandidateModelDirectory() throws {
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        for relativePath in ParakeetModelStore.requiredRelativePaths {
            let url = modelDirectory.appendingPathComponent(relativePath)
            if relativePath.hasSuffix(".mlmodelc") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try Data("model".utf8).write(to: url.appendingPathComponent("coremldata.bin"))
            } else {
                try Data("{}".utf8).write(to: url)
            }
        }
    }
}
