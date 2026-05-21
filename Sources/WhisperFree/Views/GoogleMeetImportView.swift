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
            downloadProgress[meeting.id] = GoogleDriveDownloadProgress(downloadedBytes: 0, totalBytes: meeting.recording?.sizeBytes)
            errorMessage = nil
            do {
                let accountID = selectedAccountID
                let url = try await GoogleDriveMeetImporter.shared.downloadRecording(recording, accountID: accountID) { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadProgress[meeting.id] = progress
                    }
                }
                onImport([url])
                statusMessage = L.tr("Recording added to the queue.", "Запись добавлена в очередь.")
            } catch {
                errorMessage = error.localizedDescription
            }
            downloadProgress[meeting.id] = nil
            importingMeetingID = nil
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
}

struct GoogleMeetImportView: View {
    @StateObject private var viewModel = GoogleMeetImportViewModel()

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
            ToolbarItem(placement: .principal) {
                Text(L.tr("Meet Calendar", "Календарь Meet"))
                    .font(.system(size: 13, weight: .semibold))
            }

            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    if viewModel.isConnected {
                        Button {
                            viewModel.addAccount()
                        } label: {
                            Image(systemName: "person.crop.circle.badge.plus")
                        }
                        .buttonStyle(.borderless)
                        .disabled(viewModel.isLoading)
                        .help(L.tr("Add Google account", "Добавить Google аккаунт"))

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
                        .help(L.tr("Remove selected Google account", "Удалить выбранный Google аккаунт"))
                    }

                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help(L.tr("Close", "Закрыть"))
                }
            }
        }
        .onAppear {
            viewModel.refreshAccountState()
            if viewModel.isConnected && viewModel.meetings.isEmpty {
                viewModel.refresh()
            }
        }
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
                                downloadProgress: viewModel.downloadProgress[meeting.id],
                                onImport: {
                                    viewModel.importMeeting(meeting, onImport: onImport)
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
            .buttonStyle(.borderless)
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
            .buttonStyle(.borderless)
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
            .buttonStyle(.borderless)
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
        .buttonStyle(.plain)
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
    let downloadProgress: GoogleDriveDownloadProgress?
    let onImport: () -> Void

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
            .disabled(meeting.recording == nil || isImporting)
        }
        .padding(10)
        .background(SW.rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: SW.radiusMedium, style: .continuous))
    }
}
