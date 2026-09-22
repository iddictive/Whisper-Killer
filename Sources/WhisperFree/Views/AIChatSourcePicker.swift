import SwiftUI

struct AIChatSourcePicker: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var filter = AIChatSourceFilter.all
    @State private var previewID: UUID?

    private var entries: [TranscriptionHistoryEntry] {
        appState.history.filter { AIChatSources.matches($0, query: query, filter: filter) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L.tr("Add transcripts", "Добавить расшифровки")).font(SW.titleFont)
                Spacer()
                Button(L.tr("Done", "Готово")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(SW.spacingL)

            HStack(spacing: SW.spacingM) {
                TextField(L.tr("Search transcripts…", "Поиск по расшифровкам…"), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(L.tr("Search transcripts", "Поиск по расшифровкам"))
                Picker(L.tr("Source", "Источник"), selection: $filter) {
                    ForEach(AIChatSourceFilter.allCases, id: \.self) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 235)
            }
            .padding(.horizontal, SW.spacingL)
            .padding(.bottom, SW.spacingM)

            Divider()
            ScrollView {
                LazyVStack(spacing: SW.spacingXS) {
                    ForEach(entries, id: \.entryId) { entry in
                        AIChatSourceRow(entry: entry, isExpanded: previewID == entry.entryId) {
                            previewID = previewID == entry.entryId ? nil : entry.entryId
                        }
                    }
                }
                .padding(SW.spacingM)
                if entries.isEmpty {
                    VStack(spacing: SW.spacingM) {
                        Text(appState.history.isEmpty
                             ? L.tr("No transcripts yet", "Расшифровок пока нет")
                             : L.tr("No matching transcripts", "Ничего не найдено"))
                            .foregroundStyle(SW.secondaryText)
                        if !appState.history.isEmpty {
                            Button(L.tr("Clear filters", "Сбросить фильтры")) {
                                query = ""
                                filter = .all
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                }
            }
            Divider()
            HStack {
                Text(L.tr("\(appState.selectedAIChatConversation?.attachments.count ?? 0) sources in chat",
                          "Источников в чате: \(appState.selectedAIChatConversation?.attachments.count ?? 0)"))
                    .font(SW.compactFont)
                    .foregroundStyle(SW.secondaryText)
                Spacer()
                Button(L.tr("Import audio or video…", "Импорт аудио или видео…")) {
                    dismiss()
                    AppDelegate.shared?.showFileTranscription()
                }
            }
            .padding(SW.spacingL)
        }
        .frame(width: 600, height: 430)
        .buttonStyle(AIChatSecondaryButtonStyle())
    }
}

private struct AIChatSourceRow: View {
    @EnvironmentObject var appState: AppState
    let entry: TranscriptionHistoryEntry
    let isExpanded: Bool
    let onPreview: () -> Void

    private var attachment: AIChatMessage? {
        appState.selectedAIChatConversation?.attachments.first {
            $0.attachmentSourceID == "history:\(entry.entryId.uuidString)"
        }
    }

    private var hasFileTitle: Bool {
        entry.isFromFileImport && entry.audioFilePath != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SW.spacingS) {
            HStack(spacing: SW.spacingM) {
                Toggle(isOn: Binding(get: { attachment != nil }, set: { selected in
                    if selected { appState.attachHistoryEntryToAIChat(entry) }
                    else if let attachment { appState.removeAIChatAttachment(attachment.id) }
                })) {
                    Text(AIChatSources.title(for: entry))
                }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(AIChatSources.text(for: entry).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(action: onPreview) {
                    VStack(alignment: .leading, spacing: SW.spacingXS) {
                        Text(hasFileTitle ? AIChatSources.title(for: entry) : AIChatSources.text(for: entry))
                            .font(SW.bodyFont)
                            .foregroundStyle(SW.primaryText)
                            .lineLimit(isExpanded && !hasFileTitle ? nil : 2)
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                        HStack(spacing: 5) {
                            Image(systemName: entry.isFromFileImport ? "doc" : "waveform")
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                        }
                        .font(SW.compactFont)
                        .foregroundStyle(SW.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(SW.compactFont)
                        .foregroundStyle(SW.secondaryText)
                }
                .buttonStyle(.swPlainInteractive)
                .help(L.tr("Preview transcript", "Просмотреть расшифровку"))
            }
            if isExpanded && hasFileTitle {
                Text(AIChatSources.text(for: entry))
                    .font(SW.bodyFont)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 26)
            }
        }
        .padding(SW.spacingM)
        .background(attachment == nil ? Color.clear : SW.rowHover)
        .clipShape(RoundedRectangle(cornerRadius: SW.radiusMedium))
    }
}
