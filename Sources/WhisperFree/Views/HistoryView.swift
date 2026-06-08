import SwiftUI
import AVFoundation

struct HistoryView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var expandedEntryId: UUID?
    @State private var playingEntryId: UUID?
    @State private var audioPlayer: AVAudioPlayer?
    
    @State private var renamingEntry: TranscriptionHistoryEntry?
    @State private var newTranscriptionText = ""
    @State private var retranscribingEntryIds = Set<UUID>()
    @State private var markdownSaveURLs: [UUID: URL] = [:]
    @State private var markdownSaveErrors: [UUID: String] = [:]

    var filteredHistory: [TranscriptionHistoryEntry] {
        if searchText.isEmpty {
            return appState.history
        }
        return appState.history.filter {
            $0.rawText.localizedCaseInsensitiveContains(searchText) ||
            $0.processedText.localizedCaseInsensitiveContains(searchText) ||
            ($0.summaryText?.localizedCaseInsensitiveContains(searchText) ?? false) ||
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
        .safeAreaInset(edge: .top, spacing: 0) {
            WindowHeaderUnderlay()
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(L.tr("Transcription History", "История транскрибации"))
                    .font(.system(size: 13, weight: .semibold))
            }
            
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    let total = appState.activeHistoryCount
                    let files = appState.fileImportCount
                    
                    Text(L.historyCount(entries: total, files: files))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    if !appState.history.isEmpty {
                        Button(role: .destructive) {
                            appState.clearHistory()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.red.opacity(0.8))
                        .help(L.tr("Clear All History", "Очистить всю историю"))
                    }
                }
            }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            statsHeader
            searchBar
            content
        }
        .padding(.top, 16) // Padding since header is removed
    }


    private var statsHeader: some View {
        HStack(spacing: 8) {
            statItem(title: L.tr("WPM", "WPM"), value: "\(appState.averageWPM)", icon: "speedometer", color: SW.accent)
            statItem(title: L.tr("Words", "Слова"), value: "\(appState.totalWords)", icon: "text.wordspacing", color: SW.secondaryText)
            statItem(title: L.tr("Saved", "Сэкономлено"), value: formatSavedTime(appState.estimatedTimeSaved), icon: "hourglass", color: SW.warning)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func statItem(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 7) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(SW.labelFont)
            }
            .foregroundStyle(color)
            
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(SW.rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: SW.radiusMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SW.radiusMedium, style: .continuous)
                .strokeBorder(SW.border, lineWidth: 1)
        )
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField(L.tr("Search transcriptions...", "Поиск по транскрипциям..."), text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.swPlainInteractive)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(SW.rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: SW.radiusMedium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SW.radiusMedium, style: .continuous).strokeBorder(SW.border, lineWidth: 1))
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
                            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
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
            Text(searchText.isEmpty ? L.tr("No transcriptions yet", "Транскрипций пока нет") : L.tr("No results found", "Ничего не найдено"))
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? L.tr("Press \(appState.settings.hotkeyConfig.displayString) to start recording", "Нажмите \(appState.settings.hotkeyConfig.displayString), чтобы начать запись") : L.tr("Try a different search term", "Попробуйте другой поисковый запрос"))
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
        .padding(12)
        .background(SW.rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: SW.radiusMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SW.radiusMedium, style: .continuous)
                .strokeBorder(SW.border, lineWidth: 1)
        )
        .alert(L.tr("Rename Transcription", "Переименовать транскрипцию"), isPresented: .init(get: { renamingEntry?.entryId == entry.entryId }, set: { if !$0 { renamingEntry = nil } })) {
            TextField(L.tr("Transcription text", "Текст транскрипции"), text: $newTranscriptionText)
            Button(L.tr("Cancel", "Отмена"), role: .cancel) { renamingEntry = nil }
            Button(L.tr("Save", "Сохранить")) {
                if let entry = renamingEntry {
                    appState.updateTranscriptionText(entry: entry, newText: newTranscriptionText)
                }
                renamingEntry = nil
            }
        } message: {
            Text(L.tr("Edit the transcription text for this entry.", "Измените текст транскрипции для этой записи."))
        }
    }

    private func rowHeader(_ entry: TranscriptionHistoryEntry) -> some View {
        HStack(spacing: 8) {
            // Mode badge
            let mode = appState.settings.allModes.first { $0.name == entry.modeName }
            HStack(spacing: 4) {
                Image(systemName: mode?.icon ?? "text.bubble")
                    .font(.system(size: 9))
                Text(entry.modeName)
                    .font(SW.labelFont)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(SW.accent.opacity(0.12))
            .foregroundStyle(SW.accent)
            .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))

            // Engine badge
            Text(entry.engineUsed)
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(SW.rowBackground)
                .foregroundStyle(.secondary)
                .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
            
            // File badge if imported
            if entry.isFromFileImport {
                HStack(spacing: 4) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 8))
                    Text(L.tr("FILE", "ФАЙЛ"))
                        .font(.system(size: 9, weight: .black))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(SW.warning.opacity(0.13))
                .foregroundStyle(SW.warning)
                .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
            }

            // Usage info
            if let usage = entry.usage {
                Text("$\(String(format: "%.4f", usage.estimatedCost))")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(SW.warning.opacity(0.13))
                    .foregroundStyle(SW.warning)
                .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
            }

            if entry.summaryText?.isEmpty == false {
                Text(L.tr("SUMMARY", "СВОДКА"))
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(SW.accent.opacity(0.12))
                    .foregroundStyle(SW.accent)
                    .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
            }

            if entry.processingError?.isEmpty == false {
                Text(isCancelledRecording(entry) ? L.tr("UNPROCESSED", "БЕЗ ОБРАБОТКИ") : L.tr("ERROR", "ОШИБКА"))
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((isCancelledRecording(entry) ? SW.warning : SW.danger).opacity(0.12))
                    .foregroundStyle(isCancelledRecording(entry) ? SW.warning : SW.danger)
                    .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
            }

            Spacer()

            Text(entry.date, style: .relative)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func rowContent(_ entry: TranscriptionHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(preferredDisplayText(for: entry))
                .font(.system(size: 13, weight: .medium))
                .lineLimit(expandedEntryId == entry.entryId ? nil : 3)
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        expandedEntryId = expandedEntryId == entry.entryId ? nil : entry.entryId
                    }
                }
                .swInteractiveHover()

            if expandedEntryId == entry.entryId {
                if let summary = entry.summaryText, !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.tr("TRANSCRIPT", "ТРАНСКРИПТ"))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(entry.processedText)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SW.rowBackground)
                    .clipShape(RoundedRectangle(cornerRadius: SW.radiusMedium, style: .continuous))
                }

                if entry.rawText != entry.processedText {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.tr("RAW TRANSCRIPTION", "СЫРАЯ ТРАНСКРИПЦИЯ"))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(entry.rawText)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SW.rowBackground)
                    .clipShape(RoundedRectangle(cornerRadius: SW.radiusMedium, style: .continuous))
                }

                if let processingError = entry.processingError, !processingError.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.tr("PROCESSING ERROR", "ОШИБКА ОБРАБОТКИ"))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(processingError)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SW.danger.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: SW.radiusMedium, style: .continuous))
                }
            }
        }
    }

    private func rowActions(_ entry: TranscriptionHistoryEntry) -> some View {
        HStack(spacing: 12) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(preferredDisplayText(for: entry), forType: .string)
            } label: {
                Label(L.tr("Copy", "Копировать"), systemImage: "doc.on.doc.fill")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.swPlainInteractive)
            .foregroundStyle(SW.accent)
            
            Button {
                newTranscriptionText = entry.summaryText ?? entry.processedText
                renamingEntry = entry
            } label: {
                Label(L.tr("Rename", "Переименовать"), systemImage: "pencil")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.swPlainInteractive)
            .foregroundStyle(SW.secondaryText)

            if entry.summaryText?.isEmpty == false {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.processedText, forType: .string)
                } label: {
                    Label(L.tr("Transcript", "Транскрипт"), systemImage: "text.alignleft")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.swPlainInteractive)
                .foregroundStyle(.secondary)
            }

            if canSaveMarkdown(for: entry) {
                Button {
                    saveMarkdown(for: entry)
                } label: {
                    Label(L.tr("Save as MD", "Save as MD"), systemImage: "square.and.arrow.down")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.swPlainInteractive)
                .foregroundStyle(Color.accentColor)

                markdownSaveStatus(entry)
            }

            if let path = entry.audioFilePath, FileManager.default.fileExists(atPath: path) {
                Button {
                    let entryId = entry.entryId
                    retranscribingEntryIds.insert(entryId)
                    Task { @MainActor in
                        await appState.retranscribeHistoryEntry(entry)
                        retranscribingEntryIds.remove(entryId)
                    }
                } label: {
                    Label(retranscribingEntryIds.contains(entry.entryId) ? L.tr("Retranscribing...", "Ретранскрипт...") : L.tr("Retranscribe", "Ретранскрипт"),
                          systemImage: retranscribingEntryIds.contains(entry.entryId) ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.swPlainInteractive)
                .foregroundStyle(Color.accentColor)
                .disabled(retranscribingEntryIds.contains(entry.entryId) || appState.state != .idle || appState.isProcessingActive)

                Button {
                    togglePlay(entry: entry)
                } label: {
                    Label(playingEntryId == entry.entryId ? L.tr("Pause", "Пауза") : L.tr("Play", "Воспроизвести"), 
                          systemImage: playingEntryId == entry.entryId ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.swPlainInteractive)
                .foregroundStyle(SW.warning)

                Button {
                    let url = URL(fileURLWithPath: path)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("Finder", systemImage: "folder.fill")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.swPlainInteractive)
                .foregroundStyle(.secondary)
            }

            if entry.rawText != entry.processedText {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.rawText, forType: .string)
                } label: {
                    Label(L.tr("Raw", "Сырой"), systemImage: "doc.on.clipboard")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.swPlainInteractive)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive) {
                withAnimation { appState.deleteTranscriptionHistoryEntry(entry) }
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 11))
            }
            .buttonStyle(.swPlainInteractive)
            .foregroundStyle(.red.opacity(0.8))
        }
    }

    @ViewBuilder
    private func markdownSaveStatus(_ entry: TranscriptionHistoryEntry) -> some View {
        if let error = markdownSaveErrors[entry.entryId] {
            Text(error)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(SW.danger)
                .lineLimit(1)
        } else if let url = markdownSaveURLs[entry.entryId] {
            Text(L.tr("Saved \(url.lastPathComponent)", "Сохранено \(url.lastPathComponent)"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(SW.success)
                .lineLimit(1)
        }
    }

    private func preferredDisplayText(for entry: TranscriptionHistoryEntry) -> String {
        if let summary = entry.summaryText, !summary.isEmpty {
            return summary
        }

        if !entry.processedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return entry.processedText
        }

        if !entry.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return entry.rawText
        }

        return entry.processingError ?? ""
    }

    private func markdownText(for entry: TranscriptionHistoryEntry) -> String {
        if !entry.processedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return entry.processedText
        }

        return entry.rawText
    }

    private func canSaveMarkdown(for entry: TranscriptionHistoryEntry) -> Bool {
        guard entry.isFromFileImport,
              let path = entry.audioFilePath,
              FileManager.default.fileExists(atPath: path)
        else { return false }

        return !markdownText(for: entry).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveMarkdown(for entry: TranscriptionHistoryEntry) {
        guard let path = entry.audioFilePath else { return }
        let text = markdownText(for: entry).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            markdownSaveURLs[entry.entryId] = nil
            markdownSaveErrors[entry.entryId] = L.tr("Nothing to save.", "Нечего сохранить.")
            return
        }

        do {
            let url = try MarkdownTranscriptExporter.save(text: text, nextToSourceFile: URL(fileURLWithPath: path))
            markdownSaveURLs[entry.entryId] = url
            markdownSaveErrors[entry.entryId] = nil
        } catch {
            markdownSaveURLs[entry.entryId] = nil
            markdownSaveErrors[entry.entryId] = L.tr("Save failed.", "Не удалось сохранить.")
        }
    }

    private func isCancelledRecording(_ entry: TranscriptionHistoryEntry) -> Bool {
        entry.engineUsed.localizedCaseInsensitiveContains("cancelled")
    }

    private func formatSavedTime(_ time: TimeInterval) -> String {
        if time < 60 {
            return L.tr("\(Int(time))s", "\(Int(time))с")
        } else if time < 3600 {
            return L.tr("\(Int(time / 60))m", "\(Int(time / 60))м")
        } else {
            return L.tr(String(format: "%.1fh", time / 3600.0), String(format: "%.1fч", time / 3600.0))
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        if seconds < 60 {
            return "\(seconds)s"
        }
        return "\(seconds / 60)m \(seconds % 60)s"
    }

    private func togglePlay(entry: TranscriptionHistoryEntry) {
        guard let path = entry.audioFilePath else { return }
        let url = URL(fileURLWithPath: path)

        if playingEntryId == entry.entryId {
            audioPlayer?.pause()
            playingEntryId = nil
        } else {
            do {
                audioPlayer?.stop()
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.play()
                playingEntryId = entry.entryId
            } catch {
                print("❌ Audio play error: \(error)")
            }
        }
    }
}
