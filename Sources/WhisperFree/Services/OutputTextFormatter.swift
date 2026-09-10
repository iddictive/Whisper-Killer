import Foundation

enum OutputTextFormatter {
    static func apply(to text: String, settings: AppSettings) -> String {
        guard !text.isEmpty else { return text }

        var result = text

        // 1. Apply casing (sentence case runs before punctuation removal to correctly detect sentence boundaries)
        result = applyCasing(result, casing: settings.textCasing)

        // 2. Apply punctuation rules
        result = applyPunctuation(result, settings: settings)

        // 3. Re-enforce lowercase or uppercase after punctuation stripping in case any artifacts remain
        if settings.textCasing == .lowercase {
            result = result.lowercased()
        } else if settings.textCasing == .uppercase {
            result = result.uppercased()
        }

        return result
    }

    static func applyCasing(_ text: String, casing: TextCasing) -> String {
        switch casing {
        case .original:
            return text
        case .lowercase:
            return text.lowercased()
        case .uppercase:
            return text.uppercased()
        case .sentenceCase:
            return toSentenceCase(text)
        case .titleCase:
            return text.capitalized
        }
    }

    static func applyPunctuation(_ text: String, settings: AppSettings) -> String {
        if !settings.enablePunctuation {
            return stripAllPunctuation(text)
        }

        var result = text
        var didRemove = false

        if settings.removePeriods {
            result = removePunctuationMarks(result, characters: Set(".…"))
            result = result.replacingOccurrences(of: #"\.{2,}"#, with: " ", options: .regularExpression)
            didRemove = true
        }

        if settings.removeCommas {
            result = removePunctuationMarks(result, characters: Set(","))
            didRemove = true
        }

        if settings.removeQuestionExclamation {
            result = removePunctuationMarks(result, characters: Set("?!؟¿¡"))
            didRemove = true
        }

        if settings.removeHyphensDashes {
            result = removePunctuationMarks(result, characters: Set("-—–_"))
            didRemove = true
        }

        if settings.removeQuotesBrackets {
            result = removePunctuationMarks(result, characters: Set("\"'«»“”‘’()[]{}<>`"))
            didRemove = true
        }

        if settings.removeColonsSemicolons {
            result = removePunctuationMarks(result, characters: Set(":;"))
            didRemove = true
        }

        if didRemove {
            result = normalizePunctuationWhitespace(result)
        }

        return result
    }

    static func stripAllPunctuation(_ text: String, preserveDecimals: Bool = true) -> String {
        guard !text.isEmpty else { return text }
        var result = text
        result = result.replacingOccurrences(of: "…", with: " ")
        result = result.replacingOccurrences(of: #"\.{2,}"#, with: " ", options: .regularExpression)

        var chars: [Character] = []
        let arr = Array(result)
        for i in 0..<arr.count {
            let c = arr[i]
            if preserveDecimals, (c == "." || c == ","), i > 0, i < arr.count - 1, arr[i - 1].isNumber, arr[i + 1].isNumber {
                chars.append(c)
            } else if c.isPunctuation {
                chars.append(" ")
            } else {
                chars.append(c)
            }
        }
        return normalizePunctuationWhitespace(String(chars))
    }

    static func removePunctuationMarks(_ text: String, characters: Set<Character>, preserveDecimals: Bool = true) -> String {
        guard !text.isEmpty else { return text }
        var chars: [Character] = []
        let arr = Array(text)
        for i in 0..<arr.count {
            let c = arr[i]
            if preserveDecimals, (c == "." || c == ","), i > 0, i < arr.count - 1, arr[i - 1].isNumber, arr[i + 1].isNumber {
                chars.append(c)
            } else if characters.contains(c) {
                chars.append(" ")
            } else {
                chars.append(c)
            }
        }
        return normalizePunctuationWhitespace(String(chars))
    }

    static func toSentenceCase(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = ""
        var capitalizeNext = true
        let lower = text.lowercased()

        for ch in lower {
            if capitalizeNext && ch.isLetter {
                result.append(ch.uppercased())
                capitalizeNext = false
            } else {
                result.append(ch)
                if ch == "." || ch == "!" || ch == "?" || ch == "\n" {
                    capitalizeNext = true
                }
            }
        }
        return result
    }

    static func normalizePunctuationWhitespace(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n").map { line in
            line
                .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"[ \t]+([,.;:!?])"#, with: "$1", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
