import Foundation

extension Notification.Name {
    static let liveTranslatorDidStart = Notification.Name("LiveTranslatorDidStart")
    static let liveTranslatorDidStop = Notification.Name("LiveTranslatorDidStop")
    static let liveTranslatorDidFailToStart = Notification.Name("LiveTranslatorDidFailToStart")
}

extension AppSettings {
    static func normalizedLiveTranslatorSourceLanguageCode(_ storedValue: String) -> String {
        normalizedLiveTranslatorLanguageCode(storedValue, defaultCode: "auto")
    }

    static func normalizedLiveTranslatorTargetLanguageCode(_ storedValue: String) -> String {
        normalizedLiveTranslatorLanguageCode(storedValue, defaultCode: "ru")
    }

    static func normalizedLiveTranslatorTargetLanguage(_ storedValue: String) -> String {
        let trimmedValue = storedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return "Russian" }

        if let language = supportedLanguages.first(where: {
            $0.code.caseInsensitiveCompare(trimmedValue) == .orderedSame ||
            $0.name.caseInsensitiveCompare(trimmedValue) == .orderedSame
        }) {
            return language.name
        }

        return trimmedValue
    }

    static func liveTranslatorSourceMatchesTarget(sourceLanguageCode: String, targetLanguage: String) -> Bool {
        let sourceCode = normalizedLiveTranslatorSourceLanguageCode(sourceLanguageCode)
        guard sourceCode != "auto" else { return false }

        return sourceCode.caseInsensitiveCompare(normalizedLiveTranslatorTargetLanguageCode(targetLanguage)) == .orderedSame
    }

    private static func normalizedLiveTranslatorLanguageCode(_ storedValue: String, defaultCode: String) -> String {
        let trimmedValue = storedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return defaultCode }

        if let language = supportedLanguages.first(where: {
            $0.code.caseInsensitiveCompare(trimmedValue) == .orderedSame ||
            $0.name.caseInsensitiveCompare(trimmedValue) == .orderedSame
        }) {
            return language.code
        }

        return trimmedValue.lowercased()
    }
}
