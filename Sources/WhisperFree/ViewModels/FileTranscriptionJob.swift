import SwiftUI
import CoreMedia

enum QueueItemStatus: Equatable {
    case queued
    case extracting
    case uploading
    case transcribing
    case postProcessing
    case done
    case error(String)
    case cancelled

    var label: String {
        switch self {
        case .queued: return L.tr("Queued", "В очереди")
        case .extracting: return L.tr("Preparing", "Подготовка")
        case .uploading: return L.tr("Uploading", "Загрузка")
        case .transcribing: return L.tr("Transcribing", "Транскрибация")
        case .postProcessing: return L.tr("Processing", "Обработка")
        case .done: return L.tr("Done", "Готово")
        case .error: return L.tr("Error", "Ошибка")
        case .cancelled: return L.tr("Cancelled", "Отменено")
        }
    }

    var icon: String {
        switch self {
        case .queued: return "clock"
        case .extracting: return "waveform"
        case .uploading: return "arrow.up.circle"
        case .transcribing: return "text.bubble"
        case .postProcessing: return "sparkles"
        case .done: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .queued: return SW.secondaryText
        case .extracting, .uploading, .transcribing, .postProcessing: return SW.accent
        case .done: return SW.success
        case .error: return SW.danger
        case .cancelled: return SW.warning
        }
    }

    var isTerminal: Bool {
        switch self {
        case .done, .cancelled, .error: return true
        default: return false
        }
    }
}

struct TranscriptionRunProvenance: Equatable {
    let engineType: TranscriptionEngineType
    let cloudModel: CloudTranscriptionModel?
    let language: String
    let modeName: String

    init(settings: AppSettings) {
        self.engineType = settings.engineType
        self.cloudModel = settings.engineType == .cloud ? settings.cloudTranscriptionModel : nil
        self.language = settings.language
        self.modeName = settings.selectedMode.name
    }

    var displayName: String {
        switch engineType {
        case .local:
            return TranscriptionEngineType.local.localizedShortTitle
        case .gigaAM:
            return TranscriptionEngineType.gigaAM.localizedShortTitle
        case .cloud:
            return cloudModel?.localizedTitle ?? TranscriptionEngineType.cloud.localizedShortTitle
        }
    }
}

struct CostEstimate: Equatable {
    let amount: Double
    let model: CloudTranscriptionModel
    let durationSeconds: TimeInterval

    var compactLabel: String {
        "$\(String(format: "%.3f", amount))"
    }

    static func audio(durationSeconds: TimeInterval, model: CloudTranscriptionModel) -> CostEstimate? {
        guard durationSeconds > 0,
              let amount = UsageLog.estimateAudioCost(durationSeconds: durationSeconds, model: model)
        else { return nil }
        return CostEstimate(amount: amount, model: model, durationSeconds: durationSeconds)
    }
}

@MainActor
final class QueueItem: ObservableObject, Identifiable {
    let id = UUID()
    let url: URL
    let fileName: String

    @Published var status: QueueItemStatus = .queued
    @Published var progress: Float = 0
    @Published var result: String?
    @Published var rawResult: String?
    @Published var summary: String?
    @Published var estimatedCost: Double?
    @Published var runProvenance: TranscriptionRunProvenance?
    @Published var rangeStart: Double = 0
    @Published var rangeEnd: Double = 0
    @Published var durationSeconds: TimeInterval?
    @Published var transcriptionSpeed: Double?
    @Published var isExpanded = false
    @Published var isSummarizing = false
    @Published var summaryError: String?
    @Published var markdownSaveURL: URL?
    @Published var markdownSaveError: String?

    var historyEntryID: UUID?

    var selectedDuration: TimeInterval {
        guard let total = durationSeconds else { return 0 }
        let end = rangeEnd > 0 ? rangeEnd : total
        return max(0, end - rangeStart)
    }

    var isRunning: Bool {
        !status.isTerminal && status != .queued
    }

    var engine: (any TranscriptionEngine)?
    private var transcriptionTask: Task<Void, Never>?
    private var startTime: Date?

    init(url: URL) {
        self.url = url
        self.fileName = url.lastPathComponent
    }

    func loadDuration(settings: AppSettings) async {
        if let dur = await CloudWhisper.fileDuration(url: url) {
            durationSeconds = dur
            rangeEnd = dur
            updateCost(settings: settings)
        }
    }

    func updateCost(settings: AppSettings) {
        estimatedCost = displayCost(settings: settings)
    }

    func displayCost(settings: AppSettings) -> Double? {
        displayCostEstimate(settings: settings)?.amount
    }

    func displayCostEstimate(settings: AppSettings) -> CostEstimate? {
        if let provenance = runProvenance {
            guard provenance.engineType == .cloud, let model = provenance.cloudModel else { return nil }
            return CostEstimate.audio(durationSeconds: selectedDuration, model: model)
        }

        guard settings.engineType == .cloud else { return nil }
        return CostEstimate.audio(durationSeconds: selectedDuration, model: settings.cloudTranscriptionModel)
    }

    func saveResultAsMarkdown() {
        guard let result = result?.trimmingCharacters(in: .whitespacesAndNewlines), !result.isEmpty else {
            markdownSaveURL = nil
            markdownSaveError = L.tr("Nothing to save.", "Нечего сохранить.")
            return
        }

        do {
            markdownSaveURL = try MarkdownTranscriptExporter.save(text: result, nextToSourceFile: url)
            markdownSaveError = nil
        } catch {
            markdownSaveURL = nil
            markdownSaveError = L.tr("Save failed.", "Не удалось сохранить.")
        }
    }

    func cancel() {
        engine?.cancel()
        transcriptionTask?.cancel()
        status = .cancelled
        progress = 0
    }

    func startTranscription(settings: AppSettings, appState: AppState) {
        guard status == .queued else { return }

        let runSettings = settings
        let provenance = TranscriptionRunProvenance(settings: runSettings)
        status = .extracting
        progress = 0
        startTime = Date()
        runProvenance = provenance
        updateCost(settings: runSettings)

        let engine = TranscriptionEngineFactory.create(for: runSettings.engineType, settings: runSettings)
        self.engine = engine

        transcriptionTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                self.status = .extracting

                let timeRange: CMTimeRange? = (rangeStart > 0 || (rangeEnd > 0 && rangeEnd < (self.durationSeconds ?? 0))) ? CMTimeRange(
                    start: CMTime(seconds: rangeStart, preferredTimescale: 1000),
                    duration: CMTime(seconds: max(0, rangeEnd - rangeStart), preferredTimescale: 1000)
                ) : nil

                let text = try await engine.transcribe(
                    audioURL: self.url,
                    language: runSettings.language == "auto" ? nil : runSettings.language,
                    timeRange: timeRange
                ) { p, _ in
                    Task { @MainActor in
                        self.progress = p
                        let isLocalRuntime = runSettings.engineType != .cloud

                        if p < (isLocalRuntime ? 0.15 : 0.10) {
                            self.status = .extracting
                        } else if !isLocalRuntime && p < 0.30 {
                            self.status = .uploading
                        } else {
                            self.status = .transcribing
                        }
                    }
                }

                var processedText = text
                var totalPromptTokens = 0
                var totalCompletionTokens = 0
                var usage: UsageLog? = nil
                let shouldRunDiarization = runSettings.enableSpeakerDiarization && runSettings.canUseSpeakerDiarization
                let shouldRunStandardPostProcessing = !shouldRunDiarization
                    && runSettings.enablePostProcessing
                    && runSettings.selectedMode.name != "Raw"
                    && !runSettings.selectedMode.systemPrompt.isEmpty

                if shouldRunDiarization {
                    print("Skipping standard AI refinement because diarization is active.")
                } else if shouldRunStandardPostProcessing {
                    await MainActor.run { self.status = .postProcessing }
                    do {
                        let processor = PostProcessor(settings: runSettings)
                        let result = try await processor.process(text: text, mode: runSettings.selectedMode)
                        processedText = result.text
                        totalPromptTokens += result.promptTokens
                        totalCompletionTokens += result.completionTokens
                    } catch {
                        print("File AI refinement failed: \(error)")
                    }
                }

                if shouldRunDiarization {
                    await MainActor.run { self.status = .postProcessing }
                    do {
                        let processor = PostProcessor(settings: runSettings)
                        let diarizationResult = try await processor.diarize(text: processedText)
                        processedText = diarizationResult.text
                        totalPromptTokens += diarizationResult.promptTokens
                        totalCompletionTokens += diarizationResult.completionTokens
                    } catch {
                        print("File diarization failed: \(error)")
                    }
                }

                if totalPromptTokens + totalCompletionTokens > 0 {
                    let usageEngine: PostProcessingEngine = shouldRunDiarization ? .openai : runSettings.postProcessingEngine
                    usage = UsageLog(
                        date: Date(),
                        modeName: shouldRunDiarization ? "Diarization" : runSettings.selectedMode.name,
                        engine: usageEngine.rawValue,
                        promptTokens: totalPromptTokens,
                        completionTokens: totalCompletionTokens,
                        totalTokens: totalPromptTokens + totalCompletionTokens,
                        estimatedCost: UsageLog.estimateCost(prompt: totalPromptTokens, completion: totalCompletionTokens, engine: usageEngine)
                    )
                }

                let filteredRawText = ProfanityFilter.apply(to: text, settings: runSettings)
                let filteredProcessedText = ProfanityFilter.apply(to: processedText, settings: runSettings)

                await MainActor.run {
                    self.updateCost(settings: runSettings)
                    self.rawResult = filteredRawText
                    self.result = filteredProcessedText
                    self.summary = nil
                    self.summaryError = nil
                    self.markdownSaveURL = nil
                    self.markdownSaveError = nil
                    self.status = .done
                    self.progress = 1.0
                    self.isExpanded = true

                    if let dur = self.durationSeconds, let start = self.startTime {
                        let elapsed = Date().timeIntervalSince(start)
                        if elapsed > 0 {
                            self.transcriptionSpeed = dur / elapsed
                        }
                    }

                    let entry = TranscriptionHistoryEntry(
                        rawText: filteredRawText,
                        processedText: filteredProcessedText,
                        modeName: runSettings.selectedMode.name,
                        duration: self.selectedDuration,
                        engineUsed: provenance.displayName + (totalPromptTokens + totalCompletionTokens > 0 ? " + AI" : ""),
                        usage: usage,
                        isFromFileImport: true,
                        audioFilePath: self.url.path,
                        ownsAudioFile: false
                    )
                    self.historyEntryID = entry.entryId
                    Storage.shared.addTranscriptionHistoryEntry(entry)
                    appState.history.insert(entry, at: 0)
                }
            } catch {
                await MainActor.run {
                    self.updateCost(settings: runSettings)
                    let rawText = self.rawResult ?? ""
                    let processedText = self.result ?? self.rawResult ?? ""
                    let entry = TranscriptionHistoryEntry(
                        rawText: rawText,
                        processedText: processedText,
                        processingError: error.localizedDescription,
                        modeName: runSettings.selectedMode.name,
                        duration: self.selectedDuration,
                        engineUsed: provenance.displayName + " + Error",
                        usage: nil,
                        isFromFileImport: true,
                        audioFilePath: self.url.path,
                        ownsAudioFile: false
                    )
                    self.historyEntryID = entry.entryId
                    Storage.shared.addTranscriptionHistoryEntry(entry)
                    appState.history.insert(entry, at: 0)

                    if self.status != .cancelled {
                        self.status = .error(error.localizedDescription)
                    }
                    self.progress = 0
                }
            }
        }
    }

    func summarize(appState: AppState) {
        guard !isSummarizing else { return }

        let sourceText = (rawResult ?? result ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else {
            summaryError = L.tr("Nothing to summarize yet.", "Пока нечего суммировать.")
            return
        }

        isSummarizing = true
        summaryError = nil

        Task { [weak self] in
            guard let self else { return }

            do {
                let processor = PostProcessor(settings: appState.settings)
                let summaryResult = try await processor.summarizeTranscript(text: sourceText)
                let totalTokens = summaryResult.promptTokens + summaryResult.completionTokens
                let usage = totalTokens > 0 ? UsageLog(
                    date: Date(),
                    modeName: "Auto Summary",
                    engine: summaryResult.engine.rawValue,
                    promptTokens: summaryResult.promptTokens,
                    completionTokens: summaryResult.completionTokens,
                    totalTokens: totalTokens,
                    estimatedCost: UsageLog.estimateCost(
                        prompt: summaryResult.promptTokens,
                        completion: summaryResult.completionTokens,
                        engine: summaryResult.engine
                    )
                ) : nil

                await MainActor.run {
                    self.summary = summaryResult.text
                    self.isSummarizing = false

                    if let historyEntryID = self.historyEntryID {
                        appState.saveSummary(entryId: historyEntryID, summary: summaryResult.text, usage: usage)
                    }
                }
            } catch {
                await MainActor.run {
                    self.summaryError = error.localizedDescription
                    self.isSummarizing = false
                }
            }
        }
    }
}
