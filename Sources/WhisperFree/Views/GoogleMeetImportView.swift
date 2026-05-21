import SwiftUI

@MainActor
final class GoogleMeetImportViewModel: ObservableObject {
    @Published var recordings: [GoogleDriveRecording] = []
    @Published var isConnected = GoogleDriveMeetImporter.shared.isConnected
    @Published var isLoading = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var importingRecordingID: String?

    func connectAndRefresh() {
        Task {
            await runBusyTask { [self] in
                try await GoogleDriveMeetImporter.shared.connect()
                self.isConnected = true
                self.recordings = try await GoogleDriveMeetImporter.shared.listRecentMeetRecordings()
                self.statusMessage = L.tr("Google Drive connected.", "Google Drive подключён.")
            }
        }
    }

    func refresh() {
        Task {
            await runBusyTask { [self] in
                self.recordings = try await GoogleDriveMeetImporter.shared.listRecentMeetRecordings()
                self.statusMessage = self.recordings.isEmpty
                    ? L.tr("No recent Meet recordings found.", "Свежие записи Meet не найдены.")
                    : nil
            }
        }
    }

    func disconnect() {
        GoogleDriveMeetImporter.shared.disconnect()
        isConnected = false
        recordings = []
        statusMessage = L.tr("Google Drive disconnected.", "Google Drive отключён.")
        errorMessage = nil
    }

    func importRecording(_ recording: GoogleDriveRecording, onImport: @escaping ([URL]) -> Void) {
        Task {
            importingRecordingID = recording.id
            errorMessage = nil
            do {
                let url = try await GoogleDriveMeetImporter.shared.downloadRecording(recording)
                onImport([url])
                statusMessage = L.tr("Recording added to the queue.", "Запись добавлена в очередь.")
            } catch {
                errorMessage = error.localizedDescription
            }
            importingRecordingID = nil
        }
    }

    private func runBusyTask(_ operation: @escaping () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct GoogleMeetImportView: View {
    @StateObject private var viewModel = GoogleMeetImportViewModel()

    let onImport: ([URL]) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if viewModel.isConnected {
                connectedContent
            } else {
                connectContent
            }

            if let error = viewModel.errorMessage {
                messageBar(text: error, color: SW.danger, icon: "exclamationmark.triangle.fill")
            } else if let status = viewModel.statusMessage {
                messageBar(text: status, color: SW.accent, icon: "checkmark.circle.fill")
            }
        }
        .frame(width: 520, height: 460)
        .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow).ignoresSafeArea())
        .onAppear {
            if viewModel.isConnected && viewModel.recordings.isEmpty {
                viewModel.refresh()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "video.badge.waveform")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SW.accent)
            Text(L.tr("Meet Recordings", "Записи Meet"))
                .font(.system(size: 14, weight: .semibold))
            Spacer()

            if viewModel.isConnected {
                Button {
                    viewModel.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isLoading)
                .help(L.tr("Refresh", "Обновить"))

                Button {
                    viewModel.disconnect()
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isLoading)
                .help(L.tr("Disconnect Google", "Отключить Google"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var connectContent: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "g.circle")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(SW.tertiaryText)

            Text(L.tr("Connect Google Drive", "Подключить Google Drive"))
                .font(.system(size: 15, weight: .semibold))

            Text(L.tr(
                "Sign in to find Meet recording files in your Drive and import them into file transcription.",
                "Войдите, чтобы найти записи Meet в Drive и импортировать их в транскрибацию файлов."
            ))
            .font(SW.compactFont)
            .foregroundStyle(SW.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 330)

            Button {
                viewModel.connectAndRefresh()
            } label: {
                HStack(spacing: 6) {
                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "link")
                    }
                    Text(L.tr("Connect", "Подключить"))
                }
                .frame(width: 132)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isLoading)

            Spacer()
        }
        .padding(24)
    }

    private var connectedContent: some View {
        Group {
            if viewModel.isLoading && viewModel.recordings.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    ProgressView()
                    Text(L.tr("Loading recordings...", "Загружаю записи..."))
                        .font(SW.compactFont)
                        .foregroundStyle(SW.secondaryText)
                    Spacer()
                }
            } else if viewModel.recordings.isEmpty {
                SWEmptyState(
                    icon: "video.slash",
                    title: L.tr("No recordings found", "Записи не найдены"),
                    detail: L.tr("Only Drive files whose names look like Meet recordings are shown.", "Показываются только файлы Drive, похожие по названию на записи Meet.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.recordings) { recording in
                            GoogleMeetRecordingRow(
                                recording: recording,
                                isImporting: viewModel.importingRecordingID == recording.id,
                                onImport: {
                                    viewModel.importRecording(recording, onImport: onImport)
                                }
                            )
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private func messageBar(text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
            Spacer()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(color.opacity(0.10))
    }
}

private struct GoogleMeetRecordingRow: View {
    let recording: GoogleDriveRecording
    let isImporting: Bool
    let onImport: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: recording.canImportForTranscription ? "video.fill" : "doc.text.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(recording.canImportForTranscription ? SW.accent : SW.secondaryText)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(recording.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SW.primaryText)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(recording.displayDate)
                    if !recording.displaySize.isEmpty {
                        Text(recording.displaySize)
                    }
                    Text(recording.mimeType)
                }
                .font(.system(size: 10))
                .foregroundStyle(SW.secondaryText)
                .lineLimit(1)
            }

            Spacer()

            Button {
                onImport()
            } label: {
                if isImporting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.down.circle")
                }
            }
            .buttonStyle(.borderless)
            .disabled(!recording.canImportForTranscription || isImporting)
            .help(recording.canImportForTranscription ? L.tr("Import", "Импортировать") : L.tr("Not an audio/video file", "Это не аудио/видео файл"))
        }
        .padding(10)
        .background(SW.rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: SW.radiusMedium, style: .continuous))
    }
}
