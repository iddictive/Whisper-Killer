import Foundation

enum TranscriptSanitizer {
    static func cleanWhisperText(_ text: String) -> String {
        clean(text, collapseWordWindows: true)
    }

    static func cleanForSummarization(_ text: String) -> String {
        clean(text, collapseWordWindows: true)
    }

    private static func clean(_ text: String, collapseWordWindows: Bool) -> String {
        var result = text

        result = stripKnownArtifacts(from: result)
        result = result.replacingOccurrences(
            of: #"(?m)(?:^|\s)(?:\.{2,}|…)(?=\s|$)"#,
            with: " ",
            options: .regularExpression
        )
        result = normalizeWhitespace(in: result)
        result = collapseRepeatedSentences(in: result)

        if collapseWordWindows {
            result = collapseRepeatedWordWindows(in: result)
        }

        return normalizeWhitespace(in: result)
    }

    private static func stripKnownArtifacts(from text: String) -> String {
        let patterns = [
            #"^\s*(?:(?:[Рр]едактор(?:\s+субтитров)?|[Кк]орректор|[Пп]родюсер|[Пп]ереводчик|[Рр]ежисс[её]р|[Мм]онтаж[её]р)\s+(?:\p{Lu}\.\s*)?\p{Lu}[\p{L}'’\-]+\s*){2,}"#,
            #"(?i)\b(?:subtitles by|translated by|edited by)[^.!\n]*[.!]?"#,
            #"(?i)\b(?:thank you|thanks) for watching[.!]?"#,
            #"(?i)(?:субтитры (?:сделал|подготовил|предоставлены|добавил|отредактировал)[^.!\n]*[.!]?)"#,
            #"(?i)(?:спасибо за субтитры[^.!\n]*[.!]?)"#,
            #"(?i)(?:подписывайтесь? на канал[^.!\n]*[.!]?)"#,
            #"(?i)(?:продолжение следует[.!]?)"#
        ]

        var result = text
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        return result
    }

    private static func collapseRepeatedSentences(in text: String) -> String {
        let fragments = sentenceFragments(from: text)
        var kept: [String] = []
        var lastKey = ""

        for fragment in fragments {
            let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let key = semanticKey(for: trimmed)
            guard !key.isEmpty else { continue }

            if key == lastKey, key.split(separator: " ").count >= 3 {
                continue
            }

            kept.append(trimmed)
            lastKey = key
        }

        return kept.joined(separator: " ")
    }

    private static func collapseRepeatedWordWindows(in text: String) -> String {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard words.count >= 6 else { return text }

        var result: [String] = []
        var index = 0

        while index < words.count {
            let maxWindow = min(14, (words.count - index) / 2)
            var collapsed = false

            if maxWindow >= 3 {
                for windowSize in stride(from: maxWindow, through: 3, by: -1) {
                    let firstKey = semanticKey(for: words[index..<index + windowSize].joined(separator: " "))
                    guard !firstKey.isEmpty else { continue }

                    var repeatCount = 1
                    while index + ((repeatCount + 1) * windowSize) <= words.count {
                        let start = index + (repeatCount * windowSize)
                        let nextKey = semanticKey(for: words[start..<start + windowSize].joined(separator: " "))
                        guard nextKey == firstKey else { break }
                        repeatCount += 1
                    }

                    if repeatCount > 1 {
                        result.append(contentsOf: words[index..<index + windowSize])
                        index += repeatCount * windowSize
                        collapsed = true
                        break
                    }
                }
            }

            if !collapsed {
                result.append(words[index])
                index += 1
            }
        }

        return result.joined(separator: " ")
    }

    private static func sentenceFragments(from text: String) -> [String] {
        var fragments: [String] = []
        var current = ""
        let terminators = Set<Character>(".!?؟。！？\n")

        for character in text {
            current.append(character)
            if terminators.contains(character) {
                fragments.append(current)
                current = ""
            }
        }

        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fragments.append(current)
        }

        return fragments
    }

    private static func semanticKey(for text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func normalizeWhitespace(in text: String) -> String {
        text
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([,.;:!?])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
