import XCTest
@testable import WhisperKiller

final class AIChatRecentItemLabelTests: XCTestCase {
    func testRepeatedModesUseTranscriptPreviewToStayDistinguishable() {
        let first = TranscriptionHistoryEntry(
            rawText: "First transcript",
            processedText: "Discuss the launch schedule",
            modeName: "Raw",
            duration: 1,
            engineUsed: "local"
        )
        let second = TranscriptionHistoryEntry(
            rawText: "Second transcript",
            processedText: "Review the support backlog",
            modeName: "Raw",
            duration: 1,
            engineUsed: "local"
        )

        let firstLabel = AIChatRecentItemLabel.text(for: first)
        let secondLabel = AIChatRecentItemLabel.text(for: second)

        XCTAssertNotEqual(firstLabel, secondLabel)
        XCTAssertTrue(firstLabel.contains("Discuss the launch schedule"))
        XCTAssertTrue(secondLabel.contains("Review the support backlog"))
    }

    func testEmptyTranscriptFallsBackToModeAndTime() {
        let entry = TranscriptionHistoryEntry(
            rawText: "  ",
            processedText: "\n",
            modeName: "Raw",
            duration: 1,
            engineUsed: "local"
        )

        let label = AIChatRecentItemLabel.text(for: entry)

        XCTAssertTrue(label.hasPrefix("Raw · "))
        XCTAssertFalse(label.hasSuffix(" · "))
    }
}
