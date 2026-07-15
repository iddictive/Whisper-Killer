import SwiftUI

@MainActor
final class GoogleMeetImportViewModel: ObservableObject {
    @Published var accounts: [GoogleOAuthAccount] = GoogleDriveMeetImporter.shared.accounts
    @Published var selectedAccountID: String? = GoogleDriveMeetImporter.shared.selectedAccountID
    @Published var meetings: [GoogleCalendarMeeting] = []
    @Published var selectedDate = Date()
    @Published var isConnected = GoogleDriveMeetImporter.shared.isConnected
    @Published var isLoading = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var importingMeetingID: String?
    @Published var downloadProgress: [String: GoogleDriveDownloadProgress] = [:]
    @Published var cachedRecordingIDs: Set<String> = []
    @Published var downloadSummary = GoogleMeetDownloadSummary.empty

    var selectedAccount: GoogleOAuthAccount? {
        guard let selectedAccountID else { return nil }
        return accounts.first { $0.id == selectedAccountID }
    }

    func connectAndRefresh() {
        Task {
            await runBusyTask { [self] in
                let account = try await GoogleDriveMeetImporter.shared.connect()
                self.refreshAccountState()
                self.selectedAccountID = account.id
                self.meetings = try await GoogleDriveMeetImporter.shared.listCalendarMeetings(on: self.selectedDate, accountID: account.id)
                try await self.refreshDownloadState()
                self.statusMessage = L.tr("Google Calendar connected.", "Google Calendar подключён.")
            }
        }
    }

    func addAccount() {
        connectAndRefresh()
    }

    func selectAccount(_ accountID: String) {
        GoogleDriveMeetImporter.shared.selectAccount(id: accountID)
        refreshAccountState()
        refresh()
    }

    func selectDate(_ date: Date) {
        selectedDate = date
        refresh()
    }

    func moveDay(_ value: Int) {
        selectedDate = Calendar.current.date(byAdding: .day, value: value, to: selectedDate) ?? selectedDate
        refresh()
    }

    func refresh() {
        guard isConnected else { return }

        Task {
            await runBusyTask { [self] in
                self.refreshAccountState()
                self.meetings = try await GoogleDriveMeetImporter.shared.listCalendarMeetings(on: self.selectedDate, accountID: self.selectedAccountID)
                try await self.refreshDownloadState()
                self.statusMessage = self.meetings.isEmpty
                    ? L.tr("No Meet meetings on this day.", "В этот день нет встреч Meet.")
                    : nil
            }
        }
    }

    func disconnect() {
        GoogleDriveMeetImporter.shared.disconnect(accountID: selectedAccountID)
        refreshAccountState()
        meetings = []
        statusMessage = isConnected
            ? L.tr("Google account removed.", "Google аккаунт удалён.")
            : L.tr("Google disconnected.", "Google отключён.")
        errorMessage = nil
    }

    func importMeeting(_ meeting: GoogleCalendarMeeting, onImport: @escaping ([URL]) -> Void) {
        guard let recording = meeting.recording else { return }

        Task {
            importingMeetingID = meeting.id
            if !cachedRecordingIDs.contains(recording.id) {
                downloadProgress[meeting.id] = GoogleDriveDownloadProgress(downloadedBytes: 0, totalBytes: recording.sizeBytes)
            }
            errorMessage = nil
            do {
                let accountID = selectedAccountID
                let url = try await GoogleDriveMeetImporter.shared.downloadRecording(
                    recording,
                    accountID: accountID,
                    meetingID: meeting.id
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadProgress[meeting.id] = progress
                    }
                }
                onImport([url])
                try await refreshDownloadState()
                statusMessage = L.tr("Recording added to the queue.", "Запись добавлена в очередь.")
            } catch {
                errorMessage = error.localizedDescription
            }
            downloadProgress[meeting.id] = nil
            importingMeetingID = nil
        }
    }

    func deleteDownload(for meeting: GoogleCalendarMeeting) {
        guard let recording = meeting.recording else { return }
        Task {
            errorMessage = nil
            do {
                _ = try await GoogleDriveMeetImporter.shared.deleteCachedRecording(recording)
                try await refreshDownloadState()
                statusMessage = L.tr("Local recording deleted.", "Локальная запись удалена.")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func clearDownloads() {
        Task {
            errorMessage = nil
            do {
                let deleted = try await GoogleDriveMeetImporter.shared.clearCachedRecordings()
                try await refreshDownloadState()
                statusMessage = L.tr(
                    "Deleted \(deleted.fileCount) local recordings (\(deleted.displaySize)).",
                    "Удалено локальных записей: \(deleted.fileCount) (\(deleted.displaySize))."
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func refreshDownloads() {
        Task {
            do {
                try await refreshDownloadState()
            } catch {
                errorMessage = error.localizedDescription
            }
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

    func refreshAccountState() {
        accounts = GoogleDriveMeetImporter.shared.accounts
        selectedAccountID = GoogleDriveMeetImporter.shared.selectedAccountID
        isConnected = GoogleDriveMeetImporter.shared.isConnected
    }

    private func refreshDownloadState() async throws {
        var cachedIDs: Set<String> = []
        for meeting in meetings {
            guard let recording = meeting.recording else { continue }
            if try await GoogleDriveMeetImporter.shared.cachedRecordingURL(recording, meetingID: meeting.id) != nil {
                cachedIDs.insert(recording.id)
            }
        }
        cachedRecordingIDs = cachedIDs
        downloadSummary = try await GoogleDriveMeetImporter.shared.cachedRecordingsSummary()
    }
}

struct GoogleMeetImportView: View {
    @StateObject private var viewModel = GoogleMeetImportViewModel()
    @State private var isConfirmingClearDownloads = false

    let onImport: ([URL]) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    onClose()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(L.tr("File Transcription", "К транскрибации"))
                    }
                    .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.swPlainInteractive)
                .help(L.tr("Back to file transcription", "Вернуться к транскрибации файла"))
            }

            ToolbarItem(placement: .principal) {
                Text(L.tr("Meet Calendar", "Календарь Meet"))
                    .font(.system(size: 13, weight: .semibold))
            }

            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    Button {
                        isConfirmingClearDownloads = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.swPlainInteractive)
                    .disabled(viewModel.downloadSummary.fileCount == 0)
                    .help(clearDownloadsHelp)

                    if viewModel.isConnected {
                        Button {
                            viewModel.addAccount()
                        } label: {
                            Image(systemName: "person.crop.circle.badge.plus")
                        }
                        .buttonStyle(.swPlainInteractive)
                        .disabled(viewModel.isLoading)
                        .help(L.tr("Add Google account", "Добавить Google аккаунт"))

                        Button {
                            viewModel.refresh()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.swPlainInteractive)
                        .disabled(viewModel.isLoading)
                        .help(L.tr("Refresh", "Обновить"))

                        Button {
                            viewModel.disconnect()
                        } label: {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                        }
                        .buttonStyle(.swPlainInteractive)
                        .disabled(viewModel.isLoading)
                        .help(L.tr("Remove selected Google account", "Удалить выбранный Google аккаунт"))
                    }

                }
            }
        }
        .onAppear {
            viewModel.refreshAccountState()
            viewModel.refreshDownloads()
            if viewModel.isConnected && viewModel.meetings.isEmpty {
                viewModel.refresh()
            }
        }
        .confirmationDialog(
            L.tr("Delete all downloaded Meet recordings?", "Удалить все скачанные записи Meet?"),
            isPresented: $isConfirmingClearDownloads
        ) {
            Button(L.tr("Delete downloads", "Удалить скачанное"), role: .destructive) {
                viewModel.clearDownloads()
            }
            Button(L.tr("Cancel", "Отмена"), role: .cancel) {}
        } message: {
            Text(L.tr(
                "This removes \(viewModel.downloadSummary.fileCount) local files (\(viewModel.downloadSummary.displaySize)). Google Drive files stay unchanged.",
                "Будет удалено локальных файлов: \(viewModel.downloadSummary.fileCount) (\(viewModel.downloadSummary.displaySize)). Файлы в Google Drive останутся без изменений."
            ))
        }
    }

    private var clearDownloadsHelp: String {
        guard viewModel.downloadSummary.fileCount > 0 else {
            return L.tr("No downloaded Meet recordings", "Нет скачанных записей Meet")
        }
        return L.tr(
            "Delete \(viewModel.downloadSummary.fileCount) downloads (\(viewModel.downloadSummary.displaySize))",
            "Удалить скачанное: \(viewModel.downloadSummary.fileCount) (\(viewModel.downloadSummary.displaySize))"
        )
    }

    private var connectContent: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(SW.tertiaryText)

            Text(L.tr("Connect Google Calendar", "Подключить Google Calendar"))
                .font(.system(size: 15, weight: .semibold))

            Text(L.tr(
                "Choose a past Meet event, then transcribe its recording when Google has generated one.",
                "Выберите прошедшую Meet-встречу и транскрибируйте запись, когда Google её уже сгенерировал."
            ))
            .font(SW.compactFont)
            .foregroundStyle(SW.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)

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
        VStack(spacing: 0) {
            calendarStrip
            Divider()

            if viewModel.isLoading && viewModel.meetings.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    ProgressView()
                    Text(L.tr("Loading meetings and recordings...", "Загружаю встречи и записи..."))
                        .font(SW.compactFont)
                        .foregroundStyle(SW.secondaryText)
                    Spacer()
                }
            } else if viewModel.meetings.isEmpty {
                SWEmptyState(
                    icon: "calendar.badge.exclamationmark",
                    title: L.tr("No Meet meetings", "Нет Meet-встреч"),
                    detail: L.tr("Pick another day in the calendar strip.", "Выберите другой день в календаре.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.meetings) { meeting in
                            GoogleCalendarMeetingRow(
                                meeting: meeting,
                                isImporting: viewModel.importingMeetingID == meeting.id,
                                isBusy: viewModel.importingMeetingID != nil,
                                isDownloaded: meeting.recording.map { viewModel.cachedRecordingIDs.contains($0.id) } ?? false,
                                downloadProgress: viewModel.downloadProgress[meeting.id],
                                onImport: {
                                    viewModel.importMeeting(meeting, onImport: onImport)
                                },
                                onDelete: {
                                    viewModel.deleteDownload(for: meeting)
                                }
                            )
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private var calendarStrip: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.moveDay(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.swPlainInteractive)
            .disabled(viewModel.isLoading)

            ForEach(visibleDays, id: \.self) { date in
                CalendarDayButton(
                    date: date,
                    isSelected: Calendar.current.isDate(date, inSameDayAs: viewModel.selectedDate),
                    action: {
                        viewModel.selectDate(date)
                    }
                )
                .disabled(viewModel.isLoading)
            }

            Button {
                viewModel.moveDay(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.swPlainInteractive)
            .disabled(viewModel.isLoading)

            Divider()
                .frame(height: 22)

            if viewModel.accounts.count > 1 {
                accountMenu

                Divider()
                    .frame(height: 22)
            }

            Button {
                viewModel.selectDate(Date())
            } label: {
                Text(L.tr("Today", "Сегодня"))
                    .font(SW.compactFont)
            }
            .buttonStyle(.swPlainInteractive)
            .disabled(viewModel.isLoading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(SW.windowBackground.opacity(0.35))
    }

    private var accountMenu: some View {
        Menu {
            ForEach(viewModel.accounts) { account in
                Button {
                    viewModel.selectAccount(account.id)
                } label: {
                    Label(account.displayName, systemImage: account.id == viewModel.selectedAccountID ? "checkmark.circle.fill" : "person.crop.circle")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "person.crop.circle")
                Text(viewModel.selectedAccount?.displayName ?? L.tr("Google", "Google"))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .font(SW.compactFont)
            .frame(maxWidth: 150)
            .swInteractiveHover(isActive: !viewModel.isLoading)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(viewModel.isLoading)
    }

    private var visibleDays: [Date] {
        let calendar = Calendar.current
        let selectedStart = calendar.startOfDay(for: viewModel.selectedDate)
        return (-3...3).compactMap { calendar.date(byAdding: .day, value: $0, to: selectedStart) }
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

private struct CalendarDayButton: View {
    let date: Date
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(Self.weekdayFormatter.string(from: date))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.82) : SW.secondaryText)
                Text(Self.dayFormatter.string(from: date))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? Color.white : SW.primaryText)
            }
            .frame(width: 46, height: 42)
            .background(isSelected ? SW.accent : SW.rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: SW.radiusMedium, style: .continuous))
        }
        .buttonStyle(.swPlainInteractive)
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()
}

private struct GoogleCalendarMeetingRow: View {
    let meeting: GoogleCalendarMeeting
    let isImporting: Bool
    let isBusy: Bool
    let isDownloaded: Bool
    let downloadProgress: GoogleDriveDownloadProgress?
    let onImport: () -> Void
    let onDelete: () -> Void
    @State private var isConfirmingDelete = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 3) {
                Text(meeting.timeRangeLabel)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SW.primaryText)
                Text(meeting.meetingCode ?? "Meet")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(SW.secondaryText)
                    .lineLimit(1)
            }
            .frame(width: 92, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                Text(meeting.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SW.primaryText)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let downloadProgress {
                        SWStatusBadge(
                            title: L.tr("Downloading \(downloadProgress.percentLabel)", "Скачивание \(downloadProgress.percentLabel)"),
                            icon: "arrow.down.circle.fill",
                            color: SW.accent
                        )
                        Text(downloadProgress.byteLabel)
                            .font(.system(size: 10))
                            .foregroundStyle(SW.secondaryText)
                    } else if isDownloaded {
                        SWStatusBadge(title: L.tr("Downloaded", "Скачано"), icon: "checkmark.circle.fill", color: SW.accent)
                        if let recording = meeting.recording, !recording.displaySize.isEmpty {
                            Text(recording.displaySize)
                                .font(.system(size: 10))
                                .foregroundStyle(SW.secondaryText)
                        }
                    } else if let recording = meeting.recording {
                        SWStatusBadge(title: L.tr("Recording ready", "Запись готова"), icon: "checkmark.circle.fill", color: SW.accent)
                        if !recording.displaySize.isEmpty {
                            Text(recording.displaySize)
                                .font(.system(size: 10))
                                .foregroundStyle(SW.secondaryText)
                        }
                    } else if case .inaccessible(let message) = meeting.recordingStatus {
                        SWStatusBadge(title: L.tr("Cannot check recording", "Нет доступа к записи"), icon: "lock.fill", color: SW.danger)
                        Text(message)
                            .font(.system(size: 10))
                            .foregroundStyle(SW.secondaryText)
                            .lineLimit(1)
                    } else {
                        SWStatusBadge(title: L.tr("No recording", "Нет записи"), icon: "clock", color: SW.secondaryText)
                    }
                }
                if let downloadProgress, let fraction = downloadProgress.fractionCompleted {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                }
            }

            Spacer()

            if isDownloaded {
                Button {
                    isConfirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.swPlainInteractive)
                .disabled(isBusy)
                .help(L.tr("Delete local copy", "Удалить локальную копию"))
            }

            Button {
                onImport()
            } label: {
                HStack(spacing: 5) {
                    if isImporting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "text.bubble")
                    }
                    Text(isImporting ? L.tr("Downloading", "Скачивание") : L.tr("Transcribe", "Транскрибировать"))
                }
                .font(.system(size: 11, weight: .semibold))
                .frame(minWidth: 108)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(meeting.recording == nil || isBusy)
        }
        .padding(10)
        .background(SW.rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: SW.radiusMedium, style: .continuous))
        .confirmationDialog(
            L.tr("Delete this downloaded recording?", "Удалить эту скачанную запись?"),
            isPresented: $isConfirmingDelete
        ) {
            Button(L.tr("Delete local copy", "Удалить локальную копию"), role: .destructive, action: onDelete)
            Button(L.tr("Cancel", "Отмена"), role: .cancel) {}
        } message: {
            Text(L.tr(
                "The Google Drive recording stays unchanged.",
                "Запись в Google Drive останется без изменений."
            ))
        }
    }
}
