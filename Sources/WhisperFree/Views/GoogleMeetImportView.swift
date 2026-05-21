import SwiftUI

@MainActor
final class GoogleMeetImportViewModel: ObservableObject {
    @Published var meetings: [GoogleCalendarMeeting] = []
    @Published var selectedDate = Date()
    @Published var isConnected = GoogleDriveMeetImporter.shared.isConnected
    @Published var isLoading = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var importingMeetingID: String?

    func connectAndRefresh() {
        Task {
            await runBusyTask { [self] in
                try await GoogleDriveMeetImporter.shared.connect()
                self.isConnected = true
                self.meetings = try await GoogleDriveMeetImporter.shared.listCalendarMeetings(on: self.selectedDate)
                self.statusMessage = L.tr("Google Calendar connected.", "Google Calendar подключён.")
            }
        }
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
                self.meetings = try await GoogleDriveMeetImporter.shared.listCalendarMeetings(on: self.selectedDate)
                self.statusMessage = self.meetings.isEmpty
                    ? L.tr("No Meet meetings on this day.", "В этот день нет встреч Meet.")
                    : nil
            }
        }
    }

    func disconnect() {
        GoogleDriveMeetImporter.shared.disconnect()
        isConnected = false
        meetings = []
        statusMessage = L.tr("Google disconnected.", "Google отключён.")
        errorMessage = nil
    }

    func importMeeting(_ meeting: GoogleCalendarMeeting, onImport: @escaping ([URL]) -> Void) {
        guard let recording = meeting.recording else { return }

        Task {
            importingMeetingID = meeting.id
            errorMessage = nil
            do {
                let url = try await GoogleDriveMeetImporter.shared.downloadRecording(recording)
                onImport([url])
                statusMessage = L.tr("Recording added to the queue.", "Запись добавлена в очередь.")
            } catch {
                errorMessage = error.localizedDescription
            }
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
}

struct GoogleMeetImportView: View {
    @StateObject private var viewModel = GoogleMeetImportViewModel()

    let onImport: ([URL]) -> Void
    let onClose: () -> Void

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if viewModel.isConnected && viewModel.meetings.isEmpty {
                viewModel.refresh()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SW.accent)
            Text(L.tr("Meet Calendar", "Календарь Meet"))
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

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help(L.tr("Close", "Закрыть"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
        .background(SW.windowBackground.opacity(0.35))
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
                    if let recording = meeting.recording {
                        SWStatusBadge(title: L.tr("Recording ready", "Запись готова"), icon: "checkmark.circle.fill", color: SW.accent)
                        if !recording.displaySize.isEmpty {
                            Text(recording.displaySize)
                                .font(.system(size: 10))
                                .foregroundStyle(SW.secondaryText)
                        }
                    } else {
                        SWStatusBadge(title: L.tr("No recording", "Нет записи"), icon: "clock", color: SW.secondaryText)
                    }
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
                    Text(L.tr("Transcribe", "Транскрибировать"))
                }
                .font(.system(size: 11, weight: .semibold))
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
