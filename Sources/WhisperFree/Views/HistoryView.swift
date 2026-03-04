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
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "clock")
                    .foregroundStyle(.cyan)
                Text("Transcription History")
                    .font(.headline)
                Spacer()
                Text("\(appState.history.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !appState.history.isEmpty {
                    Button(role: .destructive) {
                        appState.clearHistory()
                    } label: {
                        Text("Clear All")
                            .font(.caption)
                    }
                }
            }
            .padding()

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search transcriptions...", text: $searchText)
                    .textFieldStyle(.plain)
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
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            // History list
            if filteredHistory.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: searchText.isEmpty ? "waveform.slash" : "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text(searchText.isEmpty ? "No transcriptions yet" : "No results found")
                        .foregroundStyle(.secondary)
                    Text(searchText.isEmpty ? "Press ⌥+Space to start recording" : "Try a different search term")
                        .font(.caption)
                        .foregroundStyle(.secondary.opacity(0.7))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(filteredHistory.indices, id: \.self) { index in
                        historyRow(filteredHistory[index])
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    @ViewBuilder
    private func historyRow(_ entry: TranscriptionHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack {
                // Mode badge
                HStack(spacing: 4) {
                    Image(systemName: appState.settings.allModes.first { $0.name == entry.modeName }?.icon ?? "text.bubble")
                        .font(.caption2)
                    Text(entry.modeName)
                        .font(.caption2)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.cyan.opacity(0.15))
                .foregroundStyle(.cyan)
                .clipShape(Capsule())

                // Engine badge
                Text(entry.engineUsed)
                    .font(.system(size: 9))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())

                Spacer()

                // Duration
                Text(formatDuration(entry.duration))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)

                // Timestamp
                Text(entry.date, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Processed text preview
            Text(entry.processedText)
                .font(.system(size: 13))
                .lineLimit(expandedEntryId == entry.entryId ? nil : 2)
                .onTapGesture {
                    withAnimation {
                        expandedEntryId = expandedEntryId == entry.entryId ? nil : entry.entryId
                    }
                }

            // Expanded: show raw text
            if expandedEntryId == entry.entryId && entry.rawText != entry.processedText {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RAW TRANSCRIPTION")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(entry.rawText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Action buttons
            HStack {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.processedText, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.cyan)

                if entry.rawText != entry.processedText {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.rawText, forType: .string)
                    } label: {
                        Label("Copy Raw", systemImage: "doc.on.clipboard")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button(role: .destructive) {
                    withAnimation {
                        appState.deleteTranscriptionHistoryEntry(entry)
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red.opacity(0.7))
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        if seconds < 60 {
            return "\(seconds)s"
        }
        return "\(seconds / 60)m \(seconds % 60)s"
    }
}
