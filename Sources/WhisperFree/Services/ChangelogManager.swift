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
        // 1. Try local cache
        if let data = try? Data(contentsOf: cacheURL),
           let cachedString = String(data: data, encoding: .utf8),
           !cachedString.isEmpty {
            applyContent(cachedString)
        } else if let bundledURL = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md") ?? localRepoChangelogURL(),
                  let bundledString = try? String(contentsOf: bundledURL, encoding: .utf8),
                  !bundledString.isEmpty {
            // 2. Try bundled or repo root file
            applyContent(bundledString)
        }

        // 3. Fetch latest from remote in background
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
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
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

    static func parseChangelog(_ markdown: String) -> [ChangelogEntry] {
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
}
