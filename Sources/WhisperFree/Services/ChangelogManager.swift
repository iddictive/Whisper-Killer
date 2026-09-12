import Foundation
import Combine

struct ChangelogEntry: Identifiable, Hashable {
    let id: String
    let version: String
    let date: String?
    let markdownBody: String
}

@MainActor
final class ChangelogManager: ObservableObject {
    static let shared = ChangelogManager()

    private let remoteURL = URL(string: "https://raw.githubusercontent.com/iddictive/Whisper-Killer/main/CHANGELOG.md")!
    private let cacheURL: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("WhisperKiller", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("CHANGELOG.md")
    }()

    @Published var entries: [ChangelogEntry] = []
    @Published var rawMarkdown: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastFetchedDate: Date?

    init() {
        loadInitialContent()
    }

    func loadInitialContent() {
        let bundledURL = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md") ?? localRepoChangelogURL()
        let bundledString = bundledURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        let cachedString = (try? Data(contentsOf: cacheURL)).flatMap { String(data: $0, encoding: .utf8) }

        if let bundledString, !bundledString.isEmpty {
            applyContent(bundledString)
        } else if let cachedString, !cachedString.isEmpty {
            applyContent(cachedString)
        }

        fetchRemoteContent()
    }

    func refresh() {
        fetchRemoteContent(force: true)
    }

    private func localRepoChangelogURL() -> URL? {
        let candidate = URL(fileURLWithPath: "CHANGELOG.md")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    private func fetchRemoteContent(force: Bool = false) {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        var request = URLRequest(url: remoteURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 10
        request.setValue("WhisperKiller", forHTTPHeaderField: "User-Agent")

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                   let markdown = String(data: data, encoding: .utf8), !markdown.isEmpty {
                    try? data.write(to: self.cacheURL, options: .atomic)
                    self.applyContent(markdown)
                    self.lastFetchedDate = Date()
                } else {
                    if self.entries.isEmpty {
                        self.errorMessage = L.tr("Could not load latest changelog.", "Не удалось загрузить историю версий.")
                    }
                }
            } catch {
                if self.entries.isEmpty {
                    self.errorMessage = error.localizedDescription
                }
            }
            self.isLoading = false
        }
    }

    private func applyContent(_ markdown: String) {
        self.rawMarkdown = markdown
        self.entries = Self.parseChangelog(markdown)
    }

    nonisolated static func parseChangelog(_ markdown: String) -> [ChangelogEntry] {
        var results: [ChangelogEntry] = []
        let sections = markdown.components(separatedBy: "\n## ")

        for (index, section) in sections.enumerated() {
            let trimmed = section.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if index == 0 && !section.hasPrefix("[") && !section.hasPrefix("v") && !section.hasPrefix("3") {
                continue
            }

            let lines = trimmed.components(separatedBy: "\n")
            guard let headerLine = lines.first else { continue }

            var version = headerLine
            var date: String? = nil

            let parts = headerLine.components(separatedBy: " - ")
            if parts.count >= 2 {
                version = parts[0]
                date = parts[1]
            }

            version = version.replacingOccurrences(of: "[", with: "")
                .replacingOccurrences(of: "]", with: "")
                .trimmingCharacters(in: .whitespaces)

            let bodyLines = lines.dropFirst()
            let bodyText = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

            results.append(ChangelogEntry(
                id: version,
                version: version,
                date: date,
                markdownBody: bodyText
            ))
        }

        return results
    }

    nonisolated static func releaseNotes(
        from markdown: String,
        version: String,
        limit: Int = 3
    ) -> [String] {
        let normalizedVersion = version
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "v", with: "", options: [.anchored, .caseInsensitive])

        let entries = parseChangelog(markdown)
        let matchingEntry = entries.first {
            $0.version.compare(normalizedVersion, options: .caseInsensitive) == .orderedSame
        } ?? entries.first {
            $0.version.compare("Unreleased", options: .caseInsensitive) == .orderedSame
        }

        guard let body = matchingEntry?.markdownBody else { return [] }
        return summaryLines(from: body, limit: limit)
    }

    nonisolated static func summaryLines(from markdown: String, limit: Int = 3) -> [String] {
        guard limit > 0 else { return [] }

        var category: String?
        var summaries: [String] = []

        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.hasPrefix("### ") {
                category = String(trimmed.dropFirst(4))
                    .replacingOccurrences(of: "**", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") else { continue }

            let rawItem = String(trimmed.dropFirst(2))
            let summary: String
            if let category, let title = leadingBoldTitle(in: rawItem) {
                summary = "\(category) — \(title)"
            } else {
                summary = rawItem
                    .replacingOccurrences(of: "**", with: "")
                    .replacingOccurrences(of: "`", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard !summary.isEmpty else { continue }
            summaries.append(compact(summary))
            if summaries.count == limit { break }
        }

        return summaries
    }

    nonisolated private static func leadingBoldTitle(in text: String) -> String? {
        guard text.hasPrefix("**"),
              let end = text.dropFirst(2).range(of: "**")?.lowerBound else { return nil }

        let title = text[text.index(text.startIndex, offsetBy: 2)..<end]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    nonisolated private static func compact(_ text: String, maximumLength: Int = 110) -> String {
        guard text.count > maximumLength else { return text }

        let cutoff = text.index(text.startIndex, offsetBy: maximumLength)
        let prefix = text[..<cutoff]
        let wordBoundary = prefix.lastIndex(where: { $0.isWhitespace }) ?? prefix.endIndex
        return String(prefix[..<wordBoundary]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
