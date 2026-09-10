import SwiftUI

struct ChangelogSection: Identifiable {
    let id = UUID()
    let category: ChangelogCategory
    let items: [String]
}

enum ChangelogCategory {
    case added
    case changed
    case fixed
    case performance
    case security
    case other(String)

    init(name: String) {
        let lower = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.contains("add") || lower.contains("новое") || lower.contains("добавлен") {
            self = .added
        } else if lower.contains("change") || lower.contains("измен") || lower.contains("обновлен") {
            self = .changed
        } else if lower.contains("fix") || lower.contains("исправлен") || lower.contains("баг") {
            self = .fixed
        } else if lower.contains("perf") || lower.contains("производит") || lower.contains("скорост") {
            self = .performance
        } else if lower.contains("sec") || lower.contains("безопасн") {
            self = .security
        } else {
            self = .other(name)
        }
    }

    var title: String {
        switch self {
        case .added: return L.tr("Added", "Новое")
        case .changed: return L.tr("Changed", "Изменения")
        case .fixed: return L.tr("Fixed", "Исправления")
        case .performance: return L.tr("Performance", "Производительность")
        case .security: return L.tr("Security", "Безопасность")
        case .other(let name): return name
        }
    }

    var icon: String {
        switch self {
        case .added: return "sparkles"
        case .changed: return "arrow.triangle.2.circlepath"
        case .fixed: return "wrench.and.screwdriver.fill"
        case .performance: return "bolt.fill"
        case .security: return "lock.shield.fill"
        case .other: return "tag.fill"
        }
    }

    var color: Color {
        switch self {
        case .added: return .green
        case .changed: return .blue
        case .fixed: return .orange
        case .performance: return .purple
        case .security: return .red
        case .other: return .secondary
        }
    }
}

struct ChangelogView: View {
    @ObservedObject private var manager = ChangelogManager.shared
    private let installedVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.51"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerBar

            if manager.isLoading && manager.entries.isEmpty {
                loadingView
            } else if let error = manager.errorMessage, manager.entries.isEmpty {
                errorView(error)
            } else {
                entriesList
            }
        }
    }

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(L.tr("Release History", "История изменений"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                if let lastDate = manager.lastFetchedDate {
                    Text(L.tr("Updated from GitHub", "Синхронизировано с GitHub") + " · " + formatDate(lastDate))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if manager.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 4)
            }

            Button {
                manager.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .help(L.tr("Check for latest notes", "Обновить список изменений"))

            Link(destination: URL(string: "https://github.com/iddictive/Whisper-Killer/blob/main/CHANGELOG.md")!) {
                HStack(spacing: 4) {
                    Text("GitHub")
                        .font(.caption)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var loadingView: some View {
        HStack {
            Spacer()
            VStack(spacing: 12) {
                ProgressView()
                Text(L.tr("Loading changelog from GitHub...", "Загрузка истории версий с GitHub..."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(40)
            Spacer()
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(L.tr("Failed to load changelog", "Не удалось загрузить changelog"))
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(L.tr("Retry", "Повторить")) {
                manager.refresh()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)
        }
        .padding()
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var entriesList: some View {
        VStack(spacing: 16) {
            ForEach(manager.entries) { entry in
                releaseCard(for: entry)
            }
        }
    }

    private func releaseCard(for entry: ChangelogEntry) -> some View {
        let isInstalled = entry.version == installedVersion || entry.version.hasPrefix(installedVersion)
        let sections = parseSections(entry.markdownBody)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Text("v" + entry.version)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(isInstalled ? Color.white : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            isInstalled
                                ? AnyShapeStyle(SW.accent)
                                : AnyShapeStyle(Color.primary.opacity(0.08))
                        )
                        .clipShape(Capsule())

                    if isInstalled {
                        Text(L.tr("Installed", "Установлена"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(SW.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(SW.accent.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                if let date = entry.date {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10))
                        Text(date)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Divider()
                .opacity(0.3)

            if sections.isEmpty {
                if !entry.markdownBody.isEmpty {
                    Text(formatInlineMarkdown(entry.markdownBody))
                        .font(.system(size: 12.5))
                        .lineSpacing(3)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 5) {
                                Image(systemName: section.category.icon)
                                    .font(.system(size: 10, weight: .semibold))
                                Text(section.category.title)
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(section.category.color)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(section.category.color.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(section.items, id: \.self) { item in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("•")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(section.category.color.opacity(0.75))
                                            .padding(.top, -1)

                                        Text(formatInlineMarkdown(item))
                                            .font(.system(size: 12.5))
                                            .lineSpacing(2)
                                            .foregroundStyle(.primary)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                            .padding(.leading, 4)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isInstalled ? SW.accent.opacity(0.35) : Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func parseSections(_ text: String) -> [ChangelogSection] {
        let lines = text.components(separatedBy: "\n")
        var sections: [ChangelogSection] = []
        var currentCategory: ChangelogCategory? = nil
        var currentItems: [String] = []

        func flush() {
            if let cat = currentCategory, !currentItems.isEmpty {
                sections.append(ChangelogSection(category: cat, items: currentItems))
            } else if !currentItems.isEmpty {
                sections.append(ChangelogSection(category: .other(""), items: currentItems))
            }
            currentItems = []
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("### ") {
                flush()
                let catName = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                currentCategory = ChangelogCategory(name: catName)
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let item = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !item.isEmpty {
                    currentItems.append(item)
                }
            } else if !trimmed.isEmpty && !trimmed.hasPrefix("---") {
                if !currentItems.isEmpty {
                    currentItems[currentItems.count - 1] += " " + trimmed
                } else {
                    currentItems.append(trimmed)
                }
            }
        }
        flush()
        return sections
    }

    private func formatInlineMarkdown(_ text: String) -> AttributedString {
        if let attr = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attr
        }
        return AttributedString(text)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
