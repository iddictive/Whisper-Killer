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

    private let installedVersion: String
    private let isDevelopmentBuild: Bool
    private let remoteURL: URL?
    private let cacheURL: URL?

    @Published var entries: [ChangelogEntry] = []
    @Published var rawMarkdown: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastFetchedDate: Date?

    init(
        installedVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
        isDevelopmentBuild: Bool = Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true
    ) {
        self.installedVersion = installedVersion
        self.isDevelopmentBuild = isDevelopmentBuild

        let releaseVersion = Self.normalizedReleaseVersion(installedVersion)
        self.remoteURL = releaseVersion.flatMap { Self.releaseChangelogURL(version: $0) }
        self.cacheURL = releaseVersion.map { Self.cacheURL(for: $0) }

        loadInitialContent()
    }

    private static func cacheURL(for version: String) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("WhisperKiller", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("CHANGELOG-\(version).md")
    }

    func loadInitialContent() {
        let bundledURL = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md")
            ?? (isDevelopmentBuild ? localRepoChangelogURL() : nil)
        let bundledString = bundledURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) }

        if isDevelopmentBuild, let bundledString, !bundledString.isEmpty {
            applyContent(bundledString)
            return
        }

        if let bundledString, !bundledString.isEmpty {
            applyReleaseContent(bundledString)
        }

        if entries.isEmpty,
           let cacheURL,
           let cachedData = try? Data(contentsOf: cacheURL),
           let cachedString = String(data: cachedData, encoding: .utf8) {
            applyReleaseContent(cachedString)
        }

        fetchRemoteContent()
    }

    func refresh() {
        fetchRemoteContent()
    }

    private func localRepoChangelogURL() -> URL? {
        let candidate = URL(fileURLWithPath: "CHANGELOG.md")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    private func fetchRemoteContent() {
        guard !isDevelopmentBuild, let remoteURL, !isLoading else { return }
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
                    if self.applyReleaseContent(markdown) {
                        if let cacheURL = self.cacheURL {
                            try? data.write(to: cacheURL, options: .atomic)
                        }
                        self.lastFetchedDate = Date()
                    } else if self.entries.isEmpty {
                        self.errorMessage = L.tr("Could not load this version's changelog.", "Не удалось загрузить историю этой версии.")
                    }
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

    @discardableResult
    private func applyReleaseContent(_ markdown: String) -> Bool {
        guard Self.isReleaseChangelog(markdown, for: installedVersion) else { return false }

        self.rawMarkdown = markdown
        self.entries = Self.releaseEntries(from: markdown, through: installedVersion)
        return true
    }

    nonisolated static func releaseChangelogURL(version: String) -> URL? {
        guard let normalizedVersion = normalizedReleaseVersion(version) else { return nil }
        let tag = "v\(normalizedVersion)"
        guard let encodedTag = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "https://raw.githubusercontent.com/iddictive/Whisper-Killer/\(encodedTag)/CHANGELOG.md")
    }

    nonisolated static func isReleaseChangelog(_ markdown: String, for installedVersion: String) -> Bool {
        guard let normalizedVersion = normalizedReleaseVersion(installedVersion) else { return false }
        return parseChangelog(markdown).contains { entry in
            normalizedReleaseVersion(entry.version) == normalizedVersion
        }
    }

    nonisolated static func releaseEntries(
        from markdown: String,
        through installedVersion: String
    ) -> [ChangelogEntry] {
        guard let installedComponents = versionComponents(installedVersion) else { return [] }

        return parseChangelog(markdown).filter { entry in
            guard let entryComponents = versionComponents(entry.version) else { return false }
            return compareVersionComponents(entryComponents, installedComponents) != .orderedDescending
        }
    }

    nonisolated private static func normalizedReleaseVersion(_ version: String) -> String? {
        let normalized = version
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "v", with: "", options: [.anchored, .caseInsensitive])

        guard let components = versionComponents(normalized) else { return nil }
        return components.map(String.init).joined(separator: ".")
    }

    nonisolated private static func versionComponents(_ version: String) -> [Int]? {
        guard version.range(of: #"^[0-9]+\.[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil else { return nil }
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty else { return nil }

        let numbers = components.compactMap { Int($0) }
        guard numbers.count == components.count else { return nil }
        return numbers
    }

    nonisolated private static func compareVersionComponents(_ lhs: [Int], _ rhs: [Int]) -> ComparisonResult {
        let count = max(lhs.count, rhs.count)
        for index in 0..<count {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
        }
        return .orderedSame
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
        let entries = parseChangelog(markdown)
        guard let normalizedVersion = normalizedReleaseVersion(version) else { return [] }
        let matchingEntry = entries.first {
            normalizedReleaseVersion($0.version) == normalizedVersion
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
