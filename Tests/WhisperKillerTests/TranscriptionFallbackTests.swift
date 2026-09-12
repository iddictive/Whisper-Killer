import XCTest
@testable import WhisperKiller

final class TranscriptionFallbackTests: XCTestCase {
    func testLocalFallbackPrefersParakeetThenQwenThenWhisperCpp() {
        XCTAssertEqual(
            TranscriptionEngineType.preferredLocalFallback { [.parakeet, .qwenASR, .local].contains($0) },
            .parakeet
        )
        XCTAssertEqual(
            TranscriptionEngineType.preferredLocalFallback { [.qwenASR, .local].contains($0) },
            .qwenASR
        )
        XCTAssertEqual(
            TranscriptionEngineType.preferredLocalFallback { $0 == .local },
            .local
        )
    }

    func testLocalFallbackDoesNotReturnCloudOrUnavailableEngine() {
        XCTAssertNil(TranscriptionEngineType.preferredLocalFallback { $0 == .cloud })
        XCTAssertNil(TranscriptionEngineType.preferredLocalFallback { _ in false })
    }

    func testUnavailableCloudResolvesToReadyLocalEngine() {
        XCTAssertEqual(
            TranscriptionEngineType.resolvedForUse(
                current: .cloud,
                isOpenAIUsable: false,
                isLocalReady: { $0 == .qwenASR }
            ),
            .qwenASR
        )
    }

    func testResolutionPreservesExplicitLocalSelectionAndUnavailableCloud() {
        XCTAssertEqual(
            TranscriptionEngineType.resolvedForUse(
                current: .local,
                isOpenAIUsable: false,
                isLocalReady: { $0 == .parakeet }
            ),
            .local
        )
        XCTAssertEqual(
            TranscriptionEngineType.resolvedForUse(
                current: .cloud,
                isOpenAIUsable: false,
                isLocalReady: { _ in false }
            ),
            .cloud
        )
    }

    func testAIModesRemainSelectableWithoutOpenAIKey() {
        var settings = AppSettings()
        settings.apiKey = ""
        settings.enablePostProcessing = true

        XCTAssertTrue(settings.isModeEnabled(.dictation))
        XCTAssertTrue(settings.isModeEnabled(.email))

        settings.selectedModeName = TranscriptionMode.email.name
        settings.normalizeBeforeSaving()
        XCTAssertEqual(settings.selectedModeName, TranscriptionMode.email.name)
    }

    func testDisabledRefinementStillLocksAIModesButNotRaw() {
        var settings = AppSettings()
        settings.enablePostProcessing = false

        XCTAssertFalse(settings.isModeEnabled(.dictation))
        XCTAssertTrue(settings.isModeEnabled(.raw))
    }
}
