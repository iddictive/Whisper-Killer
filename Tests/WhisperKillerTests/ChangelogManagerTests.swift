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
}
