import Foundation

enum AIChatSourceFilter: String, CaseIterable {
    case all, voice, imports

    var title: String {
        switch self {
        case .all: return L.tr("All", "Все")
        case .voice: return L.tr("Voice", "Голосовые")
        case .imports: return L.tr("Imports", "Импорты")
        }
    }
}

enum AIChatSources {
    static func title(for entry: TranscriptionHistoryEntry) -> String {
        if entry.isFromFileImport, let path = entry.audioFilePath {
            let name = URL(fileURLWithPath: path).lastPathComponent
            if !name.isEmpty { return name }
        }
        let preview = entry.preferredDisplayText.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if preview.isEmpty { return entry.modeName }
        return preview.count > 90 ? String(preview.prefix(90)) + "…" : preview
    }

    static func text(for entry: TranscriptionHistoryEntry) -> String {
        let processed = entry.processedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !processed.isEmpty { return processed }
        let raw = entry.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? (entry.summaryText ?? "") : raw
    }

    static func matches(_ entry: TranscriptionHistoryEntry, query: String, filter: AIChatSourceFilter) -> Bool {
        if filter == .voice && entry.isFromFileImport { return false }
        if filter == .imports && !entry.isFromFileImport { return false }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return [title(for: entry), entry.modeName, entry.rawText, entry.processedText, entry.summaryText ?? ""]
            .contains { $0.localizedStandardContains(query) }
    }
}
