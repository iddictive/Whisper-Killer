import SwiftUI
import UniformTypeIdentifiers

// MARK: - Main View

struct FileTranscriptionView: View {
    @EnvironmentObject var appState: AppState
    @State private var isDragging = false
    @State private var showFilePicker = false
    @State private var showGoogleMeetImporter = false
    @State private var error: String?

    @State private var queueItems: [QueueItem] = []
    @State private var isProcessing = false
    @State private var queueStateRevision = 0
    @State private var shouldDrainCloudQueue = false
    @State private var cloudParallelLimit = 3
    @State private var cloudRecoverySuccesses = 0
    @State private var consumedImportRequestID: UUID?
    @State private var consumedGoogleMeetImportRequestID: UUID?

    private let defaultCloudParallelJobs = 3
    private let minCloudParallelJobs = 1

    var body: some View {
        ZStack {
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                .ignoresSafeArea()

            if showGoogleMeetImporter {
                GoogleMeetImportView(
                    onImport: { urls in
                        addToQueue(urls)
                        showGoogleMeetImporter = false
                    },
                    onClose: {
                        showGoogleMeetImporter = false
                    }
                )
            } else {
                fileTranscriptionContent
            }

            errorOverlay
        }
        .frame(minWidth: 800, minHeight: 550)
        .onDisappear {
            for item in queueItems { item.cancel() }
            queueItems.removeAll()
        }
        .onChange(of: appState.settings.cloudTranscriptionModel) { _, _ in
            updateVisibleCosts()
        }
        .onChange(of: appState.settings.enableSpeakerDiarization) { _, _ in
            appState.saveSettings()
            updateVisibleCosts()
        }
        .onChange(of: appState.settings.engineType) { _, _ in
            appState.saveSettings()
            updateVisibleCosts()
        }
        .onChange(of: appState.fileTranscriptionImportRequest) { _, request in
            consumeImportRequest(request)
        }
        .onChange(of: appState.googleMeetImportRequestID) { _, requestID in
            consumeGoogleMeetImportRequest(requestID)
        }
        .onAppear {
            consumeImportRequest(appState.fileTranscriptionImportRequest)
            consumeGoogleMeetImportRequest(appState.googleMeetImportRequestID)
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: FileTranscriptionSupport.allowedContentTypes,
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

    private var fileTranscriptionContent: some View {
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
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(L.tr("File Transcription", "Транскрибация файла"))
                    .font(.system(size: 13, weight: .semibold))
            }

            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    if !queueItems.isEmpty {
                        let doneCount = queueItems.filter { $0.status == .done }.count
                        Text("\(doneCount)/\(queueItems.count)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    if !queueItems.isEmpty && !hasRunningItems {
                        Button(role: .destructive) {
                            for item in queueItems { item.cancel() }
                            queueItems.removeAll()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.swPlainInteractive)
                        .foregroundStyle(SW.danger)
                        .help(L.tr("Clear All Files", "Очистить все файлы"))
                    }
                }
            }
        }
    }

    // MARK: - Config Bar

    private var configBar: some View {
        HStack(spacing: 10) {
            modeMenu
            languageMenu
            diarizationToggle

            Spacer(minLength: 0)

            meetButton
            engineMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(SW.windowBackground.opacity(0.45))
    }

    private var modeMenu: some View {
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
            .swInteractiveHover()
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var languageMenu: some View {
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
            .swInteractiveHover()
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var diarizationToggle: some View {
        if appState.settings.engineType == .cloud || appState.settings.enableSpeakerDiarization {
            Toggle(isOn: $appState.settings.enableSpeakerDiarization) {
                Text(L.tr("Diarization", "Диаризация"))
                    .font(.system(size: 10, weight: .medium))
            }
            .toggleStyle(.checkbox)
            .disabled(!appState.settings.canUseSpeakerDiarization)
            .help(appState.settings.canUseSpeakerDiarization
                  ? L.tr("Use native OpenAI speaker diarization.", "Использовать нативную OpenAI-диаризацию спикеров.")
                  : L.tr("Cloud (OpenAI) and an OpenAI API key are required for diarization.", "Для диаризации нужны Облако (OpenAI) и OpenAI API key."))
            .fixedSize()
        }
    }

    private var meetButton: some View {
        Button {
            showGoogleMeetImporter = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "video.badge.waveform")
                Text("Meet")
            }
            .font(SW.compactFont)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(SW.rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
        }
        .buttonStyle(.swPlainInteractive)
        .help(L.tr("Import Google Meet recording", "Импортировать запись Google Meet"))
        .fixedSize()
    }

    private var engineMenu: some View {
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

            Button {
                appState.settings.engineType = .qwenASR
                appState.settings.qwenASRModel = QwenASRModel.recommended
                appState.saveSettings()
                updateVisibleCosts()
            } label: {
                Label(L.tr("Local (Qwen3-ASR MLX)", "Локально (Qwen3-ASR MLX)"), systemImage: TranscriptionEngineType.qwenASR.icon)
            }
            .disabled(!QwenASRTranscriber.isAppleSilicon)

            Button {
                appState.settings.engineType = .gigaAM
                appState.settings.language = "ru"
                appState.saveSettings()
                updateVisibleCosts()
            } label: {
                Label(L.tr("GigaAM Russian", "GigaAM русский"), systemImage: TranscriptionEngineType.gigaAM.icon)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: appState.settings.engineType.fileTranscriptionIcon)
                Text(appState.settings.engineType.localizedShortTitle)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
            }
            .font(SW.compactFont)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(SW.rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
            .swInteractiveHover()
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Queue List

    private var queueListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(queueItems) { item in
                    QueueCardView(item: item, canStart: canStartQueuedItems, onStart: {
                        startItem(item)
                    }, onRerun: {
                        rerunItem(item)
                    }, onCancel: {
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
                Text(L.tr("Drop or click to add", "Перетащите или нажмите"))
                    .font(.system(size: 11))
                    .foregroundStyle(SW.secondaryText)
            }
        }
        .frame(height: 40)
        .swInteractiveHover()
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
                    let doneCount = queueItems.filter { $0.status == .done }.count
                    let queuedCount = queueItems.filter { $0.status == .queued }.count
                    Text("\(doneCount)/\(queueItems.count)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)

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
                        .disabled(appState.settings.engineType == .cloud ? runningItemCount >= cloudParallelLimit : hasRunningItems)
                    }
                }

                Spacer()

                Button {
                    clearCompleted()
                } label: {
                    Text(L.tr("Clear Done", "Убрать готовые"))
                        .font(.system(size: 11))
                }
                .buttonStyle(.swPlainInteractive)
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

                    Text(L.tr("Drop files or click to add", "Перетащите файлы или нажмите"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SW.primaryText)
                }
            }
            .frame(height: 160)
            .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
                handleDrop(providers)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .swInteractiveHover()
        .onTapGesture {
            showFilePicker = true
        }
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
                    .buttonStyle(.swPlainInteractive)
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
        let supportedURLs = FileTranscriptionSupport.supportedURLs(from: urls)
        let skippedCount = urls.count - supportedURLs.count

        guard !supportedURLs.isEmpty else {
            error = L.tr("No supported audio or video files selected.", "Не выбраны поддерживаемые аудио- или видеофайлы.")
            return
        }

        if skippedCount > 0 {
            error = L.tr(
                "\(skippedCount) unsupported file(s) skipped.",
                "\(skippedCount) \(L.russianPlural(skippedCount, one: "неподдерживаемый файл пропущен", few: "неподдерживаемых файла пропущены", many: "неподдерживаемых файлов пропущено"))."
            )
        }

        for url in supportedURLs {
            let item = QueueItem(url: url)
            queueItems.append(item)

            // Load duration and cost estimate
            Task {
                await item.loadDuration(settings: appState.settings)
            }
        }
        // processNextInQueue() removed to wait for user confirmation
    }

    private func consumeImportRequest(_ request: FileTranscriptionImportRequest?) {
        guard let request, consumedImportRequestID != request.id else { return }
        consumedImportRequestID = request.id
        addToQueue(request.urls)
        appState.consumeFileTranscriptionRequest(id: request.id)
    }

    private func consumeGoogleMeetImportRequest(_ requestID: UUID?) {
        guard let requestID, consumedGoogleMeetImportRequestID != requestID else { return }
        consumedGoogleMeetImportRequestID = requestID
        showGoogleMeetImporter = true
        appState.consumeGoogleMeetImportRequest(id: requestID)
    }

    private var totalDisplayCost: Double {
        queueItems.compactMap { $0.displayCost(settings: appState.settings) }.reduce(0, +)
    }

    private var hasRunningItems: Bool {
        runningItemCount > 0
    }

    private var runningItemCount: Int {
        _ = queueStateRevision
        return queueItems.filter { $0.isRunning }.count
    }

    private var canStartQueuedItems: Bool {
        if appState.settings.engineType == .cloud {
            return runningItemCount < cloudParallelLimit
        }

        return !isProcessing && !hasRunningItems
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
            queueStateRevision += 1
            return
        }

        isProcessing = true
        nextItem.startTranscription(settings: appState.settings, appState: appState)
        queueStateRevision += 1

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

    private func startItem(_ item: QueueItem) {
        guard item.status == .queued else { return }

        if appState.settings.engineType == .cloud {
            startCloudItem(item)
            return
        }

        guard !isProcessing && !hasRunningItems else { return }
        isProcessing = true
        item.startTranscription(settings: appState.settings, appState: appState)
        queueStateRevision += 1

        Task {
            while true {
                try? await Task.sleep(nanoseconds: 300_000_000)
                let status = item.status
                if status == .done || status == .cancelled || {
                    if case .error = status { return true }
                    return false
                }() {
                    break
                }
            }

            isProcessing = false
            queueStateRevision += 1
        }
    }

    private func startCloudItem(_ item: QueueItem) {
        guard item.status == .queued, runningItemCount < cloudParallelLimit else { return }
        item.startTranscription(settings: appState.settings, appState: appState)
        queueStateRevision += 1

        Task {
            while true {
                try? await Task.sleep(nanoseconds: 300_000_000)
                let status = item.status
                if status == .done || status == .cancelled || {
                    if case .error = status { return true }
                    return false
                }() {
                    break
                }
            }

            handleCloudItemFinished(item, status: item.status)
            queueStateRevision += 1
            if shouldDrainCloudQueue {
                startCloudJobsUpToLimit()
            }
        }
    }

    private func startCloudJobsUpToLimit() {
        while runningItemCount < cloudParallelLimit,
              let item = queueItems.first(where: { $0.status == .queued }) {
            startCloudItem(item)
        }

        if queueItems.allSatisfy({ $0.status != .queued }) && runningItemCount == 0 {
            shouldDrainCloudQueue = false
        }
    }

    private func handleCloudItemFinished(_ item: QueueItem, status: QueueItemStatus) {
        switch status {
        case .done:
            guard cloudParallelLimit < defaultCloudParallelJobs else {
                cloudRecoverySuccesses = 0
                return
            }

            cloudRecoverySuccesses += 1
            if cloudRecoverySuccesses >= cloudParallelLimit {
                cloudParallelLimit = min(defaultCloudParallelJobs, cloudParallelLimit + 1)
                cloudRecoverySuccesses = 0
                print("whisper_debug: ☁️ Cloud parallel limit recovered to \(cloudParallelLimit)")
            }
        case .error:
            guard item.shouldReduceCloudConcurrency else { return }
            cloudRecoverySuccesses = 0

            if cloudParallelLimit > minCloudParallelJobs {
                cloudParallelLimit = max(minCloudParallelJobs, cloudParallelLimit - 1)
                print("whisper_debug: ☁️ Cloud parallel limit reduced to \(cloudParallelLimit)")
            }
        default:
            break
        }
    }

    private func cancelItem(_ item: QueueItem) {
        item.cancel()
    }

    private func removeItem(_ item: QueueItem) {
        item.cancel()
        queueItems.removeAll { $0.id == item.id }
    }

    private func rerunItem(_ item: QueueItem) {
        guard item.status.isTerminal, canStartQueuedItems else { return }

        item.resetForRerun(settings: appState.settings)
        queueStateRevision += 1
        startItem(item)
    }

    private func clearCompleted() {
        queueItems.removeAll { $0.status == .done }
    }

    private func startAllQueued() {
        if appState.settings.engineType == .cloud {
            shouldDrainCloudQueue = true
            startCloudJobsUpToLimit()
            return
        }

        guard !isProcessing && !hasRunningItems else { return }
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
    var canStart: Bool
    var onStart: () -> Void
    var onRerun: () -> Void
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
                .layoutPriority(-1)

            Spacer()

            if item.status != .done {
                provenanceBadge
                statusBadge
                    .fixedSize(horizontal: true, vertical: false)
            }
            actionButton
                .layoutPriority(2)
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
                icon: provenance.engineType.fileTranscriptionIcon,
                color: SW.secondaryText
            )
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if item.status == .done, item.result != nil {
            HStack(spacing: 8) {
                Button {
                    item.saveResultAsMarkdown()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 10))
                        Text(L.tr("Save as MD", "Save as MD"))
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(SW.accent.opacity(0.12))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
                }
                .buttonStyle(.swPlainInteractive)
                .help(L.tr("Save transcript next to the original file", "Сохранить транскрипт рядом с исходным файлом"))

                rerunButton
                removeButton
            }
            .fixedSize(horizontal: true, vertical: false)
        } else if isFinished {
            HStack(spacing: 8) {
                rerunButton
                removeButton
            }
            .fixedSize(horizontal: true, vertical: false)
        } else if item.status == .queued {
            HStack(spacing: 8) {
                Button {
                    onStart()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                        Text(L.tr("Start", "Старт"))
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(SW.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
                    .opacity(canStart ? 1 : 0.45)
                }
                .buttonStyle(.swPlainInteractive)
                .disabled(!canStart)

                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .padding(4)
                }
                .buttonStyle(.swPlainInteractive)
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
            .buttonStyle(.swPlainInteractive)
            .help(L.tr("Stop Processing", "Остановить обработку"))
        }
    }

    private var rerunButton: some View {
        Button {
            onRerun()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10))
                Text(L.tr("Rerun", "Повторить"))
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(canStart ? SW.accent.opacity(0.12) : SW.rowBackground)
            .foregroundStyle(canStart ? Color.accentColor : SW.secondaryText)
            .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
            .opacity(canStart ? 1 : 0.55)
        }
        .buttonStyle(.swPlainInteractive)
        .disabled(!canStart)
        .help(L.tr("Run this file again with the current settings", "Запустить этот файл снова с текущими настройками"))
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.secondary.opacity(0.6))
                .padding(4)
        }
        .buttonStyle(.swPlainInteractive)
        .help(L.tr("Remove from queue", "Удалить из очереди"))
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
        Group {
            if item.status != .queued || isError {
                HStack(spacing: 8) {
                    durationLabel
                    costLabel
                    speedLabel
                    errorLabel
                    markdownSaveLabel
                    Spacer()
                }
            }
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
    private var markdownSaveLabel: some View {
        if let error = item.markdownSaveError {
            Text(error)
                .font(.system(size: 9))
                .foregroundStyle(SW.danger)
                .lineLimit(1)
        } else if let url = item.markdownSaveURL {
            HStack(spacing: 2) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 8))
                Text(L.tr("Saved \(url.lastPathComponent)", "Сохранено \(url.lastPathComponent)"))
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(SW.success)
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
            ClickableDisclosure(isExpanded: $item.isExpanded) {
                resultContent(result)
            } label: {
                Text(item.isExpanded
                     ? L.tr("Hide Result", "Скрыть результат")
                     : L.tr("Show Result", "Показать результат"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func resultContent(_ result: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    transcriptBlock(text: result)

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

    private func transcriptBlock(title: String? = nil, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
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

private extension TranscriptionEngineType {
    var fileTranscriptionIcon: String {
        switch self {
        case .cloud: return "cloud.fill"
        case .local: return "cpu"
        case .qwenASR: return icon
        case .gigaAM: return icon
        }
    }
}
