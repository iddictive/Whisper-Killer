import Foundation
import Testing
@testable import WhisperKiller

@Suite("Live Translator availability")
struct LiveTranslatorAvailabilityTests {
    @Test("new settings keep Live Translator disabled")
    func newSettingsDefaultToDisabled() {
        #expect(!AppSettings().liveTranslatorEnabled)
    }

    @Test("settings without the stored flag keep Live Translator disabled")
    func missingStoredFlagDefaultsToDisabled() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))

        #expect(!settings.liveTranslatorEnabled)
    }
}
