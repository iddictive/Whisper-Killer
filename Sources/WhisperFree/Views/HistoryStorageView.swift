import SwiftUI

struct HistoryStorageView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var summary: HistoryStorageSummary?
    @State private var pendingCleanup: HistoryStorageCleanup?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(L.tr("Local Storage", "Локальное хранилище"))
                    .font(.headline)
                Spacer()
                if let summary {
                    Text(HistoryStorageSummary.size(summary.totalBytes))
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                } else { ProgressView().controlSize(.small) }
            }

            VStack(spacing: 16) {
                storageRow(
                    L.tr("Recorded audio", "Аудиозаписи"),
                    detail: L.tr("Transcripts are kept", "Тексты сохраняются"),
                    bytes: summary?.recordingsBytes,
                    cleanup: .recordings,
                    disabled: summary?.recordingCount == 0
                )
                Divider()
                storageRow(
                    L.tr("Meet downloads", "Скачанные записи Meet"),
                    detail: L.tr("Files in Google Drive are kept", "Файлы в Google Drive сохраняются"),
                    bytes: summary?.downloadsBytes,
                    cleanup: .downloads,
                    disabled: summary?.downloadCount == 0
                )
                Divider()
                storageRow(
                    L.tr("Transcripts & settings", "Тексты и настройки"),
                    bytes: summary?.textBytes
                )
                storageRow(
                    L.tr("Models & runtime", "Модели и окружение"),
                    detail: L.tr("Manage models in Settings", "Управление моделями — в настройках"),
                    bytes: summary?.modelsBytes
                )
                if let summary, summary.otherBytes > 0 {
                    storageRow(L.tr("Other app data", "Другие данные приложения"), bytes: summary.otherBytes)
                }
            }

            if !appState.canCleanHistoryStorage && !appState.isCleaningHistoryStorage {
                Text(L.tr("Finish recording and downloads, then clear the file queue before cleaning storage.", "Завершите запись и скачивание, затем освободите очередь файлов перед очисткой."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(SW.danger)
            }

            Divider()
            HStack {
                Button(L.tr("Delete All History…", "Удалить всю историю…"), role: .destructive) {
                    pendingCleanup = .history
                }
                .disabled(!appState.canCleanHistoryStorage || appState.history.isEmpty || summary == nil)
                Spacer()
                if appState.isCleaningHistoryStorage { ProgressView().controlSize(.small) }
                Button(L.tr("Done", "Готово")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(appState.isCleaningHistoryStorage)
            }
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 460, maxWidth: 520)
        .fixedSize(horizontal: false, vertical: true)
        .interactiveDismissDisabled(appState.isCleaningHistoryStorage)
        .task { await refresh() }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(get: { pendingCleanup != nil }, set: { if !$0 { pendingCleanup = nil } }),
            titleVisibility: .visible
        ) {
            if let pendingCleanup {
                Button(L.tr("Delete", "Удалить"), role: .destructive) { clean(pendingCleanup) }
            }
            Button(L.tr("Cancel", "Отмена"), role: .cancel) { pendingCleanup = nil }
        } message: {
            Text(confirmationMessage)
        }
    }

    private func storageRow(
        _ title: String,
        detail: String? = nil,
        bytes: Int64?,
        cleanup: HistoryStorageCleanup? = nil,
        disabled: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            Text(bytes.map(HistoryStorageSummary.size) ?? "—")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if let cleanup {
                Button(L.tr("Delete…", "Удалить…"), role: .destructive) { pendingCleanup = cleanup }
                    .disabled(disabled || !appState.canCleanHistoryStorage || summary == nil)
            }
        }
    }

    private var confirmationTitle: String {
        switch pendingCleanup {
        case .recordings: return L.tr("Delete recorded audio?", "Удалить аудиозаписи?")
        case .downloads: return L.tr("Delete Meet downloads?", "Удалить скачанные записи Meet?")
        case .history: return L.tr("Delete all history?", "Удалить всю историю?")
        case nil: return ""
        }
    }

    private var confirmationMessage: String {
        switch pendingCleanup {
        case .recordings:
            return L.tr(
                "Delete \(summary?.recordingCount ?? 0) audio files (\(HistoryStorageSummary.size(summary?.recordingsBytes ?? 0))) permanently. Transcripts stay available; playback and retranscription of these recordings will be unavailable.",
                "Аудиофайлы (\(summary?.recordingCount ?? 0), \(HistoryStorageSummary.size(summary?.recordingsBytes ?? 0))) будут удалены безвозвратно. Тексты сохранятся, но эти записи нельзя будет воспроизвести или транскрибировать повторно."
            )
        case .downloads:
            return L.tr(
                "Delete \(summary?.downloadCount ?? 0) local files (\(HistoryStorageSummary.size(summary?.downloadsBytes ?? 0))). Transcripts and Google Drive originals are kept. Download the recordings again to play or retranscribe them.",
                "Будут удалены локальные файлы (\(summary?.downloadCount ?? 0), \(HistoryStorageSummary.size(summary?.downloadsBytes ?? 0))). Тексты и оригиналы в Google Drive сохранятся. Для воспроизведения или повторной транскрибации скачайте записи заново."
            )
        case .history:
            return L.tr(
                "Delete all \(appState.history.count) transcripts and recorded audio permanently. Imported originals, Meet downloads, settings and models are kept.",
                "Все транскрипции (\(appState.history.count)) и аудиозаписи будут удалены безвозвратно. Оригиналы импортов, скачанные записи Meet, настройки и модели сохранятся."
            )
        case nil: return ""
        }
    }

    private func refresh() async {
        do {
            summary = try await HistoryStorage.shared.summary(textBytes: Storage.shared.textStorageBytes)
        } catch {
            summary = nil
            self.error = error.localizedDescription
        }
    }

    private func clean(_ cleanup: HistoryStorageCleanup) {
        pendingCleanup = nil
        error = nil
        Task { @MainActor in
            do { try await appState.cleanHistoryStorage(cleanup) }
            catch { self.error = error.localizedDescription }
            await refresh()
        }
    }
}
