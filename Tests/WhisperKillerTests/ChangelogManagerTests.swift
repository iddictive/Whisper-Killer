import XCTest
@testable import WhisperKiller

@MainActor
final class ChangelogManagerTests: XCTestCase {
    func testChangelogParsingBuildsStructuredEntries() {
        let sampleMarkdown = """
        # Changelog

        ## [3.50] - 2026-09-10
        ### Added
        - Feature A

        ## [3.49] - 2026-09-04
        ### Fixed
        - Bug B
        """

        let entries = ChangelogManager.parseChangelog(sampleMarkdown)
        XCTAssertEqual(entries.count, 2)
        
        let first = entries.first
        XCTAssertEqual(first?.version, "3.50")
        XCTAssertEqual(first?.date, "2026-09-10")
        XCTAssertTrue(first?.markdownBody.contains("Feature A") == true)

        let second = entries.last
        XCTAssertEqual(second?.version, "3.49")
        XCTAssertEqual(second?.date, "2026-09-04")
        XCTAssertTrue(second?.markdownBody.contains("Bug B") == true)
    }

    func testChangelogFileExistsInRepository() {
        let fileURL = URL(fileURLWithPath: "CHANGELOG.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        let content = try? String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertNotNil(content)
        XCTAssertTrue(content?.contains("## [3.50]") == true)
        XCTAssertTrue(content?.contains("## [3.0.0]") == true)
    }

    func testReleaseNotesPreferMatchingVersionAndStayCompact() {
        let sampleMarkdown = """
        # Changelog

        ## [Unreleased]
        - **Future item**: Not part of this release.

        ## [3.52] - 2026-09-12
        ### Changed
        - **Updater feedback**: Manual checks now always report a result.
        - `Install` dialogs show release highlights.
        - Third item
        - Fourth item
        """

        let notes = ChangelogManager.releaseNotes(from: sampleMarkdown, version: "v3.52")

        XCTAssertEqual(notes.count, 3)
        XCTAssertEqual(notes[0], "Changed — Updater feedback")
        XCTAssertEqual(notes[1], "Install dialogs show release highlights.")
        XCTAssertFalse(notes.joined().contains("Future item"))
        XCTAssertFalse(notes.joined().contains("Fourth item"))
    }

    func testReleaseNotesFallBackToUnreleasedSectionForTaggedSnapshot() {
        let sampleMarkdown = """
        # Changelog

        ## [Unreleased]
        ### Fixed
        - Manual update checks show a final status.

        ## [3.51] - 2026-09-10
        - Older item
        """

        XCTAssertEqual(
            ChangelogManager.releaseNotes(from: sampleMarkdown, version: "3.52"),
            ["Manual update checks show a final status."]
        )
    }
}
