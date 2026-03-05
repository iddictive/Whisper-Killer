import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var expandedEntryId: UUID?

    var filteredHistory: [TranscriptionHistoryEntry] {
        if searchText.isEmpty {
            return appState.history
        }
        return appState.history.filter {
            $0.rawText.localizedCaseInsensitiveContains(searchText) ||
            $0.processedText.localizedCaseInsensitiveContains(searchText) ||
            $0.modeName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                mainContent
            }
        }
        .frame(minWidth: 420, minHeight: 480)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Spacer().frame(width: 80)
            }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            header
            statsHeader
            searchBar
            content
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "clock")
                .font(.system(size: 14))
                .foregroundStyle(.cyan)
            Text("Transcription History")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Text("\(appState.history.count) entries")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if !appState.history.isEmpty {
                Button(role: .destructive) {
                    appState.clearHistory()
                } label: {
                    Text("Clear All")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red.opacity(0.8))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private var statsHeader: some View {
        HStack(spacing: 16) {
            statItem(title: "AVG. WPM", value: "\(appState.averageWPM)", icon: "speedometer", color: .cyan)
            statItem(title: "TOTAL WORDS", value: "\(appState.totalWords)", icon: "text.wordspacing", color: .purple)
            statItem(title: "TIME SAVED", value: formatSavedTime(appState.estimatedTimeSaved), icon: "hourglass", color: .orange)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private func statItem(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(color)
            
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(color.opacity(0.15), lineWidth: 1)
        )
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("Search transcriptions...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var content: some View {
        VStack(spacing: 0) {
            if filteredHistory.isEmpty {
                emptyView
            } else {
                List {
                    ForEach(filteredHistory.indices, id: \.self) { index in
                        historyRow(filteredHistory[index])
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: searchText.isEmpty ? "waveform.slash" : "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.5))
            Text(searchText.isEmpty ? "No transcriptions yet" : "No results found")
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? "Press \(appState.settings.hotkeyConfig.displayString) to start recording" : "Try a different search term")
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.7))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func historyRow(_ entry: TranscriptionHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            rowHeader(entry)
            rowContent(entry)
            rowActions(entry)
        }
        .padding(16)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private func rowHeader(_ entry: TranscriptionHistoryEntry) -> some View {
        HStack(spacing: 8) {
            // Mode badge
            let mode = appState.settings.allModes.first { $0.name == entry.modeName }
            HStack(spacing: 4) {
                Image(systemName: mode?.icon ?? "text.bubble")
                    .font(.system(size: 9))
                Text(entry.modeName)
                    .font(.system(size: 10, weight: .bold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.12))
            .foregroundStyle(Color.accentColor)
            .clipShape(Capsule())

            // Engine badge
            Text(entry.engineUsed)
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.06))
                .foregroundStyle(.secondary)
                .clipShape(Capsule())
            
            // Usage info
            if let usage = entry.usage {
                Text("$\(String(format: "%.4f", usage.estimatedCost))")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
            }

            Spacer()

            Text(entry.date, style: .relative)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func rowContent(_ entry: TranscriptionHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.processedText)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(expandedEntryId == entry.entryId ? nil : 3)
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        expandedEntryId = expandedEntryId == entry.entryId ? nil : entry.entryId
                    }
                }

            if expandedEntryId == entry.entryId && entry.rawText != entry.processedText {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RAW TRANSCRIPTION")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(entry.rawText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func rowActions(_ entry: TranscriptionHistoryEntry) -> some View {
        HStack(spacing: 12) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.processedText, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc.fill")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.cyan)

            if entry.rawText != entry.processedText {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.rawText, forType: .string)
                } label: {
                    Label("Raw", systemImage: "doc.on.clipboard")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive) {
                withAnimation { appState.deleteTranscriptionHistoryEntry(entry) }
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red.opacity(0.8))
        }
    }

    private func formatSavedTime(_ time: TimeInterval) -> String {
        if time < 60 {
            return "\(Int(time))s"
        } else if time < 3600 {
            return "\(Int(time / 60))m"
        } else {
            return String(format: "%.1fh", time / 3600.0)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        if seconds < 60 {
            return "\(seconds)s"
        }
        return "\(seconds / 60)m \(seconds % 60)s"
    }
}
