import SwiftUI
import UniformTypeIdentifiers

// MARK: - Main View

struct FileTranscriptionView: View {
    @EnvironmentObject var appState: AppState
    @State private var isDragging = false
    @State private var showFilePicker = false
    @State private var error: String?

    @State private var queueItems: [QueueItem] = []
    @State private var isProcessing = false

    var body: some View {
        ZStack {
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                configBar
                Divider()

                if queueItems.isEmpty {
                    dropZoneView
                        .padding(.top, 20)
                } else {
                    queueListView
                }

                Spacer(minLength: 0)

                if !queueItems.isEmpty {
                    bottomBar
                }
            }

            errorOverlay
        }
        .frame(minWidth: 400, minHeight: 320)
        .safeAreaInset(edge: .top, spacing: 0) {
            WindowHeaderUnderlay()
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(L.tr("File Transcription", "Транскрибация файла"))
                    .font(.system(size: 13, weight: .semibold))
            }
            
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    if !queueItems.isEmpty {
                        let totalCost = totalDisplayCost
                        let doneCount = queueItems.filter { $0.status == .done }.count
                        
                        if totalCost > 0 {
                            Text(L.tr("Est. $\(String(format: "%.3f", totalCost))", "Оценка $\(String(format: "%.3f", totalCost))"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(SW.warning)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(SW.warning.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
                        }
                        
                        Text(L.tr("\(doneCount)/\(queueItems.count) files", "\(doneCount)/\(queueItems.count) файлов"))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(SW.accent.opacity(0.12))
                            .foregroundStyle(SW.accent)
                            .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
                    }
                    
                    if !queueItems.isEmpty && !isProcessing {
                        Button(role: .destructive) {
                            for item in queueItems { item.cancel() }
                            queueItems.removeAll()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.red.opacity(0.8))
                        .help(L.tr("Clear All Files", "Очистить все файлы"))
                    }
                }
            }
        }
        .onDisappear {
            for item in queueItems { item.cancel() }
            queueItems.removeAll()
        }
        .onChange(of: appState.settings.cloudTranscriptionModel) { _, _ in
            updateVisibleCosts()
        }
        .onChange(of: appState.settings.engineType) { _, _ in
            updateVisibleCosts()
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.audio, .video, .movie, .quickTimeMovie, .mpeg4Movie, .wav, .mp3, .aiff],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                addToQueue(urls)
            case .failure(let err):
                self.error = err.localizedDescription
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text(L.tr("File Transcription", "Транскрибация файла"))
                .font(.system(size: 14, weight: .semibold))
            Spacer()

            if !queueItems.isEmpty {
                let doneCount = queueItems.filter { $0.status == .done }.count
                Text("\(doneCount)/\(queueItems.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    // MARK: - Config Bar

    private var configBar: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(appState.settings.allModes) { mode in
                    let isEnabled = appState.settings.isModeEnabled(mode)
                    Button {
                        appState.settings.selectedModeName = mode.name
                    } label: {
                        HStack {
                            Text(mode.localizedName)
                            if !isEnabled {
                                Spacer()
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 8))
                            }
                        }
                    }
                    .disabled(!isEnabled)
                }
            } label: {
                HStack(spacing: 4) {
                    let mode = appState.settings.selectedMode
                    Image(systemName: mode.icon)
                    Text(mode.localizedName)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                }
                .font(SW.compactFont)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(SW.rowBackground)
                .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Language Selection
            Menu {
                ForEach(AppSettings.supportedLanguages, id: \.code) { lang in
                    Button {
                        appState.settings.language = lang.code
                    } label: {
                        Text(L.languageName(code: lang.code, fallback: lang.name))
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    let currentLanguage = AppSettings.supportedLanguages.first { $0.code == appState.settings.language }
                    let currentLang = L.languageName(code: currentLanguage?.code ?? "auto", fallback: currentLanguage?.name ?? "Auto")
                    Text(currentLang)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                }
                .font(SW.compactFont)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(SW.rowBackground)
                .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if appState.settings.engineType == .cloud || appState.settings.canUseSpeakerDiarization || appState.settings.enableSpeakerDiarization {
                Toggle(isOn: $appState.settings.enableSpeakerDiarization) {
                    Text(L.tr("Diarization", "Диаризация"))
                        .font(.system(size: 10, weight: .medium))
                }
                .toggleStyle(.checkbox)
                .padding(.leading, 4)
            }

            Spacer()

            Menu {
                Button {
                    appState.settings.engineType = .local
                    appState.saveSettings()
                    updateVisibleCosts()
                } label: {
                    Label(L.tr("Local (whisper.cpp)", "Локально (whisper.cpp)"), systemImage: "cpu")
                }

                Button {
                    appState.settings.engineType = .cloud
                    appState.saveSettings()
                    updateVisibleCosts()
                } label: {
                    Label(L.tr("Cloud (OpenAI)", "Облако (OpenAI)"), systemImage: "cloud.fill")
                }
                .disabled(appState.settings.apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: appState.settings.engineType == .cloud ? "cloud.fill" : "cpu")
                    Text(appState.settings.engineType.localizedShortTitle)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                }
                .font(SW.compactFont)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(SW.rowBackground)
                .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(SW.windowBackground.opacity(0.45))
    }

    // MARK: - Queue List

    private var queueListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(queueItems) { item in
                    QueueCardView(item: item, onCancel: {
                        cancelItem(item)
                    }, onRemove: {
                        removeItem(item)
                    })
                }

                // Drop zone at the bottom of the queue
                addMoreDropZone
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var addMoreDropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isDragging ? SW.accent : SW.border,
                    style: StrokeStyle(lineWidth: 1, dash: [5, 3])
                )
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isDragging ? SW.accent.opacity(0.06) : Color.clear)
                )

            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(SW.secondaryText)
                Text(L.tr("Drop more files or click to add", "Перетащите ещё файлы или нажмите, чтобы добавить"))
                    .font(.system(size: 11))
                    .foregroundStyle(SW.secondaryText)
            }
        }
        .frame(height: 40)
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers)
        }
        .onTapGesture {
            showFilePicker = true
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                // Total estimated cost
                let totalCost = totalDisplayCost
                if totalCost > 0 {
                    SWMetricBadge(
                        title: L.tr("Estimate", "Оценка"),
                        value: "$\(String(format: "%.3f", totalCost))",
                        icon: "creditcard",
                        color: SW.warning
                    )
                }

                if !queueItems.isEmpty {
                    let queuedCount = queueItems.filter { $0.status == .queued }.count
                    if queuedCount > 0 {
                        Button {
                            startAllQueued()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                Text(L.tr("Start All (\(queuedCount))", "Запустить все (\(queuedCount))"))
                            }
                            .font(.system(size: 11, weight: .bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.accentColor)
                    }
                }

                Spacer()

                Button {
                    clearCompleted()
                } label: {
                    Text(L.tr("Clear Done", "Убрать готовые"))
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(queueItems.filter { $0.status == .done }.isEmpty)

                Button {
                    showFilePicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text(L.tr("Add Files", "Добавить файлы"))
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Drop Zone (empty state)

    private var dropZoneView: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isDragging ? SW.accent : SW.border,
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 3])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isDragging ? SW.accent.opacity(0.06) : SW.rowBackground)
                    )

                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(isDragging ? SW.accent : SW.tertiaryText)
                        .padding(.bottom, 2)

                    Text(L.tr("Drop audio or video here", "Перетащите сюда аудио или видео"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SW.primaryText)

                    Text(L.tr("MP3, WAV, M4A, MP4, MOV", "MP3, WAV, M4A, MP4, MOV"))
                        .font(.system(size: 10))
                        .foregroundStyle(SW.secondaryText)
                }
            }
            .frame(height: 160)
            .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
                handleDrop(providers)
            }

            Button {
                showFilePicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text(L.tr("Add to Queue...", "Добавить в очередь..."))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Error Overlay

    private var errorOverlay: some View {
        Group {
            if let error = error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.white)
                    Text(error)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Spacer()
                    Button { self.error = nil } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(SW.danger.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: SW.radiusMedium, style: .continuous))
                .padding(20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Drop Handling

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                DispatchQueue.main.async {
                    addToQueue([url])
                }
            }
        }
        return true
    }

    // MARK: - Queue Logic

    private func addToQueue(_ urls: [URL]) {
        for url in urls {
            let item = QueueItem(url: url)
            queueItems.append(item)

            // Load duration and cost estimate
            Task {
                await item.loadDuration(settings: appState.settings)
            }
        }
        // processNextInQueue() removed to wait for user confirmation
    }

    private var totalDisplayCost: Double {
        queueItems.compactMap { $0.displayCost(settings: appState.settings) }.reduce(0, +)
    }

    private func updateVisibleCosts() {
        for item in queueItems {
            item.updateCost(settings: appState.settings)
        }
    }

    private func processNextInQueue() {
        // Find the first queued item that hasn't started
        guard let nextItem = queueItems.first(where: { $0.status == .queued }) else {
            isProcessing = false
            return
        }

        isProcessing = true
        nextItem.startTranscription(settings: appState.settings, appState: appState)

        // When this item finishes, process the next one
        Task {
            // Observe the item's status
            while true {
                try? await Task.sleep(nanoseconds: 300_000_000)
                let status = nextItem.status
                if status == .done || status == .cancelled || {
                    if case .error = status { return true }
                    return false
                }() {
                    break
                }
            }
            processNextInQueue()
        }
    }

    private func cancelItem(_ item: QueueItem) {
        item.cancel()
    }

    private func removeItem(_ item: QueueItem) {
        item.cancel()
        queueItems.removeAll { $0.id == item.id }
    }

    private func clearCompleted() {
        queueItems.removeAll { $0.status == .done }
    }

    private func startAllQueued() {
        guard !isProcessing else { return }
        processNextInQueue()
    }
}

// MARK: - Range Slider Component

struct RangeSlider: View {
    @Binding var start: Double
    @Binding var end: Double
    let range: ClosedRange<Double>
    let onEditingChanged: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width - 20 // 10px padding on each side for thumbs

            NonDraggableContainer {
                ZStack(alignment: .leading) {
                    // Transparent background to claim the area
                    Color.black.opacity(0.0001)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())

                    // Background Track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.1))
                        .frame(height: 4)
                        .padding(.horizontal, 10)

                    // Active Track
                    let startX = CGFloat((start - range.lowerBound) / (range.upperBound - range.lowerBound)) * totalWidth
                    let endX = CGFloat((end - range.lowerBound) / (range.upperBound - range.lowerBound)) * totalWidth
                    let trackWidth = max(0, endX - startX)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(width: trackWidth, height: 4)
                        .offset(x: startX + 10)

                    // Start Thumb
                    ThumbView()
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                        .offset(x: startX - 5)
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("sliderTrack"))
                                .onChanged { value in
                                    let delta = Double(value.location.x - 10) / Double(totalWidth)
                                    let newValue = min(max(range.lowerBound, range.lowerBound + delta * (range.upperBound - range.lowerBound)), end - 0.5)
                                    start = newValue
                                    onEditingChanged()
                                }
                        )

                    // End Thumb
                    ThumbView()
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                        .offset(x: endX - 5)
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("sliderTrack"))
                                .onChanged { value in
                                    let delta = Double(value.location.x - 10) / Double(totalWidth)
                                    let newValue = max(min(range.upperBound, range.lowerBound + delta * (range.upperBound - range.lowerBound)), start + 0.5)
                                    end = newValue
                                    onEditingChanged()
                                }
                        )
                }
                .coordinateSpace(name: "sliderTrack")
            }
        }
        .frame(height: 32)
        .padding(.horizontal, 12)
    }

    struct ThumbView: View {
        var body: some View {
            ZStack {
                Circle()
                    .fill(Color.white)
                    .shadow(radius: 2, x: 0, y: 1)
                Circle()
                    .stroke(Color.accentColor.opacity(0.8), lineWidth: 1.5)
            }
            .frame(width: 20, height: 20)
            .contentShape(Circle())
        }
    }
}

// MARK: - Queue Card View

struct QueueCardView: View {
    @ObservedObject var item: QueueItem
    var onCancel: () -> Void
    var onRemove: () -> Void
    @EnvironmentObject private var appState: AppState

    private var fileExtIcon: String {
        let ext = item.url.pathExtension.lowercased()
        switch ext {
        case "mp4", "mov", "m4v", "avi", "mkv", "webm": return "film"
        case "mp3": return "music.note"
        case "wav", "aiff": return "waveform"
        case "m4a": return "music.quarternote.3"
        default: return "doc"
        }
    }

    private var isError: Bool {
        if case .error = item.status { return true }
        return false
    }

    private var isFinished: Bool {
        item.status == .done || item.status == .cancelled || isError
    }

    private var errorMessage: String? {
        if case .error(let msg) = item.status { return msg }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow
            
            if item.status == .queued, let duration = item.durationSeconds, duration > 1 {
                trimSection(totalDuration: duration)
            }
            
            progressRow
            metricsRow
            resultRow
        }
        .padding(10)
        .background(SW.rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: SW.radiusMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SW.radiusMedium, style: .continuous)
                .stroke(item.status == .done ? SW.accent.opacity(0.35) : SW.border, lineWidth: 1)
        )
        .padding(.vertical, 2)
    }

    // MARK: - Row 1: Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: fileExtIcon)
                .font(.system(size: 12))
                .foregroundStyle(item.status.color)
                .frame(width: 16)

            Text(item.fileName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            provenanceBadge
            statusBadge
            actionButton
        }
    }

    private var statusBadge: some View {
        SWStatusBadge(title: item.status.label, icon: item.status.icon, color: item.status.color)
    }

    @ViewBuilder
    private var provenanceBadge: some View {
        if let provenance = item.runProvenance {
            SWStatusBadge(
                title: provenance.displayName,
                icon: provenance.engineType == .cloud ? "cloud.fill" : "cpu",
                color: SW.secondaryText
            )
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if isFinished {
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .padding(4)
            }
            .buttonStyle(.plain)
            .help(L.tr("Remove from queue", "Удалить из очереди"))
        } else if item.status == .queued {
            HStack(spacing: 8) {
                Button {
                    item.startTranscription(settings: appState.settings, appState: appState)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                        Text(L.tr("Start", "Старт"))
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(SW.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help(L.tr("Cancel", "Отменить"))
            }
        } else {
            Button(action: onCancel) {
                ZStack {
                    Circle()
                        .fill(SW.danger.opacity(0.1))
                        .frame(width: 22, height: 22)
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(SW.danger)
                }
            }
            .buttonStyle(.plain)
            .help(L.tr("Stop Processing", "Остановить обработку"))
        }
    }

    // MARK: - Row 2: Progress

    @ViewBuilder
    private var progressRow: some View {
        if !isFinished && item.status != .queued {
            ProgressView(value: item.progress)
                .progressViewStyle(.linear)
                .tint(item.status.color)
        }
    }

    // MARK: - Row 3: Metrics

    private var metricsRow: some View {
        HStack(spacing: 8) {
            durationLabel
            costLabel
            speedLabel
            errorLabel
            Spacer()
            percentLabel
        }
    }

    @ViewBuilder
    private var durationLabel: some View {
        if item.selectedDuration > 0 {
            SWMetricBadge(
                title: L.tr("Audio", "Аудио"),
                value: formatDuration(item.selectedDuration),
                icon: "timer",
                color: SW.secondaryText
            )
        }
    }

    @ViewBuilder
    private var costLabel: some View {
        if let cost = item.displayCostEstimate(settings: appState.settings) {
            SWMetricBadge(
                title: cost.model.localizedTitle,
                value: cost.compactLabel,
                icon: "creditcard",
                color: SW.warning
            )
        }
    }

    @ViewBuilder
    private var speedLabel: some View {
        if let speed = item.transcriptionSpeed {
            HStack(spacing: 2) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8))
                Text(L.tr("\(String(format: "%.0f", speed))x realtime", "\(String(format: "%.0f", speed))x от реального времени"))
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(SW.accent)
        }
    }

    @ViewBuilder
    private var errorLabel: some View {
        if let msg = errorMessage {
            Text(msg)
                .font(.system(size: 9))
                .foregroundStyle(SW.danger)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var percentLabel: some View {
        if item.status == .done {
            Text("100%")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(SW.accent)
        } else if item.progress > 0 && !isError && item.status != .cancelled {
            Text(String(format: "%d%%", Int(item.progress * 100)))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
    @ViewBuilder
    private func trimSection(totalDuration: Double) -> some View {
        VStack(spacing: 8) {
            HStack {
                Label(L.tr("Trim Segment", "Обрезать сегмент"), systemImage: "scissors")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(formatDuration(item.rangeStart)) / \(formatDuration(item.rangeEnd))")
                    .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(SW.accent)
                Text(L.tr("(\(formatDuration(item.selectedDuration)) selected)", "(\(formatDuration(item.selectedDuration)) выбрано)"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            
            RangeSlider(
                start: $item.rangeStart,
                end: $item.rangeEnd,
                range: 0...totalDuration,
                onEditingChanged: {
                    item.updateCost(settings: appState.settings)
                }
            )
            .padding(.horizontal, 4)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(SW.rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
    }

    // MARK: - Row 4: Result

    @ViewBuilder
    private var resultRow: some View {
        if item.status == .done, let result = item.result {
            DisclosureGroup(isExpanded: $item.isExpanded) {
                resultContent(result)
            } label: {
                Text(L.tr("Show Result", "Показать результат"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func resultContent(_ result: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    transcriptBlock(title: L.tr("Transcript", "Транскрипт"), text: result)

                    if let summary = item.summary, !summary.isEmpty {
                        transcriptBlock(title: L.tr("Auto Summary", "Автосводка"), text: summary)
                    }

                    if let summaryError = item.summaryError, !summaryError.isEmpty {
                        Text(summaryError)
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 140)

            HStack(spacing: 8) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result, forType: .string)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text(L.tr("Copy", "Копировать"))
                    }
                    .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    item.summarize(appState: appState)
                } label: {
                    HStack(spacing: 4) {
                        if item.isSummarizing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(item.summary == nil ? L.tr("Summarize", "Суммировать") : L.tr("Re-Summarize", "Пересуммировать"))
                    }
                    .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(item.isSummarizing)

                if let summary = item.summary, !summary.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(summary, forType: .string)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                            Text(L.tr("Copy Summary", "Копировать сводку"))
                        }
                        .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.top, 4)
    }

    private func transcriptBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 11))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
