import XCTest
@testable import WhisperKiller

final class AIChatModelSelectionTests: XCTestCase {
    func testKeepsOnlyCurrentGeneralChatModelAliases() {
        let models = AIChatService.relevantOpenAIChatModels(from: [
            "gpt-4o",
            "gpt-5.5",
            "gpt-5.5-pro",
            "gpt-5.5-pro-2026-04-23",
            "gpt-5.6-terra",
            "gpt-5.6-sol",
            "gpt-5.6-luna",
            "gpt-5.6-codex",
            "gpt-5.6-search-api",
            "gpt-5.6-chat-latest",
            "gpt-5.6-2026-07-01",
            "omni-moderation-latest",
            "o3"
        ])

        XCTAssertEqual(models, [
            "gpt-5.6-luna",
            "gpt-5.6-sol",
            "gpt-5.6-terra"
        ])
    }

    func testFutureGeneralGenerationReplacesOlderGenerationWithoutAllowlistChange() {
        let models = AIChatService.relevantOpenAIChatModels(from: [
            "gpt-5.6",
            "gpt-5.6-pro",
            "gpt-5.7",
            "gpt-5.7-pro",
            "gpt-5.7-mini"
        ])

        XCTAssertEqual(models, [
            "gpt-5.7",
            "gpt-5.7-pro",
            "gpt-5.7-mini"
        ])
    }

    func testReturnsEmptyWhenCatalogContainsOnlySpecializedOrLegacyModels() {
        let models = AIChatService.relevantOpenAIChatModels(from: [
            "gpt-4o",
            "gpt-5.6-codex",
            "gpt-5.6-realtime",
            "gpt-5.6-2026-07-01",
            "o3"
        ])

        XCTAssertTrue(models.isEmpty)
    }
}
