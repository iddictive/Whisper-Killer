import Foundation

extension Notification.Name {
    static let liveTranslatorDidStart = Notification.Name("LiveTranslatorDidStart")
    static let liveTranslatorDidStop = Notification.Name("LiveTranslatorDidStop")
}

extension AppSettings {
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
}
