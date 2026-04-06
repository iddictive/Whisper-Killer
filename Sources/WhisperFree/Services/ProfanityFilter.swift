import Foundation

enum ProfanityFilter {
    enum DictionaryImportError: LocalizedError {
        case unreadableFile
        case unsupportedJSON
        case emptyDictionary

        var errorDescription: String? {
            switch self {
            case .unreadableFile:
                return L.tr("Could not read the dictionary file.", "Не удалось прочитать файл словаря.")
            case .unsupportedJSON:
                return L.tr("JSON must be an array of strings or an object with a 'words' or 'terms' array.", "JSON должен быть массивом строк или объектом с массивом 'words' или 'terms'.")
            case .emptyDictionary:
                return L.tr("No valid words were found in the file.", "В файле не найдено подходящих слов.")
            }
        }
    }

    static func apply(to text: String, settings: AppSettings) -> String {
        guard settings.enableProfanityFilter, !text.isEmpty else { return text }

        let range = NSRange(text.startIndex..., in: text)
        let filtered = profanityRegex(for: settings).stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        return cleanupSpacing(in: filtered)
    }

    static func importDictionary(from url: URL) throws -> CustomProfanityDictionary {
        let terms: [String]

        switch url.pathExtension.lowercased() {
        case "json":
            terms = try parseJSONDictionary(from: url)
        default:
            terms = try parseTextDictionary(from: url)
        }

        let normalizedTerms = normalizeCustomTerms(terms)
        guard !normalizedTerms.isEmpty else {
            throw DictionaryImportError.emptyDictionary
        }

        return CustomProfanityDictionary(fileName: url.lastPathComponent, terms: normalizedTerms)
    }

    private static let englishPatterns: [String] = [
        "motherfucker(?:s)?",
        "fuck(?:er|ers|ed|ing|in)?",
        "bullshit(?:ting)?",
        "shit(?:s|ty|ter|ters|ting)?",
        "bitch(?:es|y)?",
        "asshole(?:s)?",
        "bastard(?:s)?",
        "dick(?:head|heads|s)?",
        "cunt(?:s)?",
        "slut(?:s)?",
        "whore(?:s)?",
        "prick(?:s)?"
    ]

    private static let russianPatterns: [String] = [
        "бля(?:д(?:ь|и|ина|ины|иной|ину|ями|ях|ский|ская|ское|ские|ских|ским|скими|скую)?|т(?:ь|и)?|ха|хи|ху)?",
        "сук(?:а|и|у|е|ой|ою|ами|ах)",
        "ху(?:й|я|ю|ем|е|и|йн(?:я|и|ю|е|ей|ями|ях)|ево|евый|евая|евое|евые|евым|евых|ево)",
        "пизд(?:а|ы|е|у|ой|ец|еца|ецу|ецом|ецы|ецов|юк|юка|юку|юком)",
        "(?:е|ё)б(?:ать|ал(?:а|и|о)?|ан(?:ый|ая|ое|ые|ого|ому|ым|ыми|ую)?|нут(?:ь|ый|ая|ое|ые)?|нул(?:а|и|о)?|усь|ешь|ете|ись)",
        "мудак(?:и|а|у|ом|ами|ах)?",
        "мраз(?:ь|и|ью)",
        "говн(?:о|а|е|у|ом|ы|ами|ах)",
        "дерьм(?:о|а|е|у|ом|ы|ами|ах)",
        "шлюх(?:а|и|у|е|ой|ою|ами|ах)",
        "сволоч(?:ь|и|ью)"
    ]

    private static func profanityRegex(for settings: AppSettings) -> NSRegularExpression {
        let customPatterns = normalizeCustomTerms(settings.customProfanityDictionaries.flatMap(\.terms))
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))

        let combined = (englishPatterns + russianPatterns + customPatterns).joined(separator: "|")
        let pattern = "(?iu)(?<![\\p{L}\\p{N}])(?:\(combined))(?![\\p{L}\\p{N}])"
        return try! NSRegularExpression(pattern: pattern)
    }

    private static let cleanupRules: [(pattern: String, template: String)] = [
        ("[ \\t]{2,}", " "),
        ("\\s+([,.;:!?])", "$1"),
        ("([\\(\\[«“])\\s+", "$1"),
        ("\\s+([\\)\\]»”])", "$1"),
        ("\\n{3,}", "\n\n")
    ]

    private static func cleanupSpacing(in text: String) -> String {
        var result = text

        for rule in cleanupRules {
            let regex = try! NSRegularExpression(pattern: rule.pattern, options: [])
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: rule.template)
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseTextDictionary(from url: URL) throws -> [String] {
        guard let content = readString(from: url) else {
            throw DictionaryImportError.unreadableFile
        }

        return content
            .components(separatedBy: .newlines)
            .flatMap { line -> [String] in
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedLine.isEmpty,
                      !trimmedLine.hasPrefix("#"),
                      !trimmedLine.hasPrefix("//") else {
                    return []
                }

                return trimmedLine
                    .split(whereSeparator: { $0 == "," || $0 == ";" })
                    .map { String($0) }
            }
    }

    private static func parseJSONDictionary(from url: URL) throws -> [String] {
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data)

        if let words = json as? [String] {
            return words
        }

        if let dictionary = json as? [String: Any] {
            if let words = dictionary["words"] as? [String] {
                return words
            }
            if let terms = dictionary["terms"] as? [String] {
                return terms
            }
        }

        throw DictionaryImportError.unsupportedJSON
    }

    private static func readString(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        let encodings: [String.Encoding] = [.utf8, .utf16, .windowsCP1251]
        for encoding in encodings {
            if let string = String(data: data, encoding: encoding) {
                return string
            }
        }

        return nil
    }

    private static func normalizeCustomTerms(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []

        for term in terms {
            let compact = term
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

            guard !compact.isEmpty else { continue }

            let dedupeKey = compact.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(dedupeKey).inserted else { continue }

            normalized.append(compact)
        }

        return normalized
    }
}
