import XCTest
@testable import WhisperKiller

final class TranscriptSanitizerTests: XCTestCase {
    func testRemovesRepeatedProductionCreditsFromTranscriptPrefix() {
        let transcript = "Редактор субтитров А. Синецкая Корректор А. Егорова Корректор А. Кулакова Продюсер А. Кулакова да-да-да, не вернуть ли его?"

        XCTAssertEqual(
            TranscriptSanitizer.cleanWhisperText(transcript),
            "да-да-да, не вернуть ли его?"
        )
    }

    func testKeepsSpokenReferenceToSubtitleEditor() {
        let transcript = "Редактор субтитров сказал, что этот фрагмент нужно оставить."

        XCTAssertEqual(
            TranscriptSanitizer.cleanWhisperText(transcript),
            transcript
        )
    }
}
