import SwiftUI
import Combine
import AVFoundation

// MARK: - App State

enum AppRecordingState: Equatable {
    case idle
    case recording
    case processing
    case typing
}

enum ProcessingStage: String {
    case converting = "Converting..."
    case preparing = "Preparing local engine..."
    case transcribing = "Transcribing..."
    case postProcessing = "Post-processing..."
    case none = ""
}

private struct RecordingProcessingJob {
    let id: UUID
    let audioURL: URL
    let duration: TimeInterval
    let modeName: String
    let engineUsed: String
    var rawText: String = ""
    var processedText: String = ""
    var stage: ProcessingStage = .transcribing
}


@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    static let liveTranslatorFeatureAvailable = true
    // MARK: - Published State
    @Published var state: AppRecordingState = .idle
    @Published var processingStage: ProcessingStage = .none
    @Published var settings: AppSettings
    @Published var history: [TranscriptionHistoryEntry] = []
    @Published var lastError: String?
    @Published var lastTranscription: String?
    @Published var fileTranscriptionImportRequest: FileTranscriptionImportRequest?
    @Published var googleMeetImportRequestID: UUID?
    @Published private(set) var backgroundProcessingCount: Int = 0
    @Published var aiChatConversations: [AIChatConversation] = []
    @Published var availableAIChatModels: [String] = []
    @Published var isLoadingAIChatModels = false
    @Published var isAIChatSending = false
    @Published var isAIChatVoiceRecording = false
    @Published var aiChatError: String?

    @Published var copiedFeedback = false
    @Published var availableInputDevices: [AVCaptureDevice] = []

    // Statistics calculated directly from history for accuracy/self-healing
    var totalWords: Int {
        history.filter { countsTowardDictationStats($0) }
               .reduce(0) { $0 + $1.processedText.split { $0.isWhitespace }.count }
    }
    var activeHistoryCount: Int {
        history.filter { countsTowardDictationStats($0) }.count
    }
    var fileImportCount: Int {
        history.filter { $0.isFromFileImport }.count
    }
    var totalDuration: TimeInterval {
        history.filter { countsTowardDictationStats($0) }
               .reduce(0) { $0 + $1.duration }
    }
    var averageWPM: Int {
        let minutes = totalDuration / 60.0
        // Safeguard: only show WPM if we have enough data to be meaningful
        guard minutes > 0.05, totalWords > 0 else { return 0 } 
        return Int(Double(totalWords) / minutes)
    }
    var estimatedTimeSaved: TimeInterval {
        // Average person types at ~40 WPM. Dictation + AI is much faster.
        // Formula: (Words / 40) - (Words / WPM) -> approximated as 2.5x duration
        return totalDuration * 2.5
    }

    private func countsTowardDictationStats(_ entry: TranscriptionHistoryEntry) -> Bool {
        !entry.isFromFileImport && !entry.engineUsed.localizedCaseInsensitiveContains("cancelled")
    }

    var isProcessingActive: Bool {
        state == .processing || backgroundProcessingCount > 0
    }

    private var shouldShowOverlay: Bool {
        state == .recording || state == .processing || state == .typing || backgroundProcessingCount > 0 || lastError != nil
    }

    @Published var showOverlayWindow = false {
        didSet {
            if !showOverlayWindow {
                errorTimer?.cancel()
                errorTimer = nil
            }
        }
    }
    @Published var showLiveTranslatorOverlay = false
    @Published var isHotkeyTrusted = false
    @Published var isMicrophoneGranted = false
    @Published var isMicrophoneDenied = false
    @Published var isTranslocated = false
    @Published var isRecordingHotkey = false {
        didSet {
            if isRecordingHotkey {
                hotkeyManager.stop()
            } else {
                setupHotkey()
            }
        }
    }

    // MARK: - Services
    let recorder = AudioRecorder()
    private let aiChatRecorder = AudioRecorder()
    let modelManager = ModelManager()
    private let hotkeyManager = HotkeyManager()
    private let liveTranslatorHotkeyManager = HotkeyManager()
    private var cancellables = Set<AnyCancellable>()
    var overlayCancellables = Set<AnyCancellable>()
    private var errorTimer: AnyCancellable?
    
    // Hold-mode tracking
    private var keyDownTime: Date?
    private var isHoldActive = false
    private var pendingStopTask: Task<Void, Never>?
    private var currentProcessingTask: Task<Void, Never>?
    private var currentProcessingToken: UUID?
    private var processingQueue: [RecordingProcessingJob] = []
    private var activeProcessingRecording: RecordingProcessingJob?
    private let postReleaseTail: TimeInterval = 0.45

    private init() {
        print("🚀 AppState initializing...")
        self.settings = Storage.shared.loadSettings()
        self.history = Storage.shared.loadHistory()
        self.aiChatConversations = Storage.shared.loadAIChatConversations()
        self.settings.normalizeBeforeSaving()
        ensureSelectedAIChatConversation()
        sanitizeDisabledFeatureState()
        Storage.shared.saveSettings(self.settings)
        print("📦 Settings and History loaded")
        
        // Initial setup
        Task {
            if settings.automaticallyChecksForUpdates {
                print("🔄 Triggering automatic update check")
                GitHubUpdater.shared.checkForUpdates()
            }
        }
        
        checkTranslocation()
        checkAccessibility()
        refreshAvailableDevices()
        observeLiveTranslatorState()
        
        // Listen for device changes
        NotificationCenter.default.addObserver(forName: .AVCaptureDeviceWasConnected, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAvailableDevices()
            }
        }
        NotificationCenter.default.addObserver(forName: .AVCaptureDeviceWasDisconnected, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAvailableDevices()
            }
        }
        self.isHotkeyTrusted = hotkeyManager.isTrusted
        self.isMicrophoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        
        print("🔑 Hotkey trusted: \(isHotkeyTrusted)")
        print("🎤 Microphone granted: \(isMicrophoneGranted)")
        setupHotkey()
        startPermissionCheckTimer()
        print("✅ AppState init complete")
    }

    private func checkAccessibility() {
        self.isHotkeyTrusted = hotkeyManager.isTrusted
    }

    private func sanitizeDisabledFeatureState() {
        guard !Self.liveTranslatorFeatureAvailable else { return }

        let hadDisabledFeatureState =
            settings.liveTranslatorEnabled ||
            settings.useScreenCaptureKit ||
            showLiveTranslatorOverlay

        guard hadDisabledFeatureState else { return }

        settings.liveTranslatorEnabled = false
        settings.useScreenCaptureKit = false
        showLiveTranslatorOverlay = false
        Storage.shared.saveSettings(settings)
    }

    private func observeLiveTranslatorState() {
        NotificationCenter.default.publisher(for: .liveTranslatorDidStart)
            .sink { [weak self] _ in
                self?.showLiveTranslatorOverlay = true
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .liveTranslatorDidStop)
            .sink { [weak self] _ in
                self?.showLiveTranslatorOverlay = false
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .liveTranslatorDidFailToStart)
            .sink { [weak self] notification in
                guard let message = notification.object as? String, !message.isEmpty else { return }
                self?.showError(message)
            }
            .store(in: &cancellables)
    }

    func refreshAvailableDevices() {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        self.availableInputDevices = session.devices
    }

    private func checkTranslocation() {
        // Simple check for App Translocation (security scoping)
        // If the path contains "/AppTranslocation/", it's likely translocated
        let path = Bundle.main.bundlePath
        self.isTranslocated = path.contains("/AppTranslocation/")
        if isTranslocated {
            print("⚠️ App is running in TRANSLOCATED mode. Path: \(path)")
        }
    }

    func clearError() {
        lastError = nil
        errorTimer?.cancel()
        errorTimer = nil
        if state == .idle && backgroundProcessingCount == 0 {
            showOverlayWindow = false
        }
    }

    // MARK: - Settings

    func saveSettings() {
        settings.normalizeBeforeSaving()
        Storage.shared.saveSettings(settings)
        hotkeyManager.config = settings.hotkeyConfig
    }

    var selectedAIChatConversation: AIChatConversation? {
        guard let selectedID = settings.selectedAIChatConversationID else { return aiChatConversations.first }
        return aiChatConversations.first { $0.id == selectedID } ?? aiChatConversations.first
    }

    @discardableResult
    func ensureSelectedAIChatConversation() -> UUID {
        if let selectedID = settings.selectedAIChatConversationID,
           aiChatConversations.contains(where: { $0.id == selectedID }) {
            return selectedID
        }

        if let first = aiChatConversations.first {
            settings.selectedAIChatConversationID = first.id
            return first.id
        }

        let conversation = AIChatConversation(title: L.tr("New Chat", "Новый чат"))
        aiChatConversations = [conversation]
        settings.selectedAIChatConversationID = conversation.id
        Storage.shared.saveAIChatConversations(aiChatConversations)
        return conversation.id
    }

    func selectAIChatConversation(_ id: UUID) {
        guard aiChatConversations.contains(where: { $0.id == id }) else { return }
        settings.selectedAIChatConversationID = id
        saveSettings()
    }

    func createAIChatConversation() {
        let number = aiChatConversations.count + 1
        let conversation = AIChatConversation(title: L.tr("Chat \(number)", "Чат \(number)"))
        aiChatConversations.insert(conversation, at: 0)
        settings.selectedAIChatConversationID = conversation.id
        saveSettings()
        Storage.shared.saveAIChatConversations(aiChatConversations)
    }

    func refreshAIChatModelsIfNeeded(force: Bool = false) {
        guard settings.hasOpenAIAPIKey else {
            availableAIChatModels = []
            return
        }
        if !force, !availableAIChatModels.isEmpty { return }
        guard !isLoadingAIChatModels else { return }

        isLoadingAIChatModels = true
        aiChatError = nil

        Task {
            do {
                let models = try await AIChatService.fetchOpenAIChatModels(apiKey: settings.normalizedAPIKey)
                await MainActor.run {
                    self.availableAIChatModels = models
                    if !models.isEmpty, !models.contains(self.settings.selectedAIChatModel) {
                        self.settings.selectedAIChatModel = models[0]
                        self.saveSettings()
                    }
                    self.isLoadingAIChatModels = false
                }
            } catch {
                await MainActor.run {
                    self.aiChatError = error.localizedDescription
                    self.isLoadingAIChatModels = false
                }
            }
        }
    }

    func setAIChatModel(_ model: String) {
        settings.selectedAIChatModel = model
        saveSettings()
    }

    func attachLatestTranscriptionToAIChat() {
        if let last = history.first {
            attachToAIChat(
                title: L.tr("Latest transcript", "Последняя транскрипция"),
                content: preferredAIChatText(for: last)
            )
            return
        }

        if let lastTranscription, !lastTranscription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            attachToAIChat(title: L.tr("Latest transcript", "Последняя транскрипция"), content: lastTranscription)
        }
    }

    func attachLiveTranslationToAIChat() {
        let manager = LiveTranslatorManager.shared
        let segments = manager.transcriptSegments.suffix(12).map {
            "\($0.originalText)\n-> \($0.translatedText)"
        }
        let fallback = [manager.originalText, manager.translatedText]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n-> ")
        let content = segments.isEmpty ? fallback : segments.joined(separator: "\n\n")
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            aiChatError = L.tr("No live translation to attach.", "Нет live-перевода для прикрепления.")
            return
        }
        attachToAIChat(title: L.tr("Live translation", "Live-перевод"), content: content)
    }

    func attachHistoryEntryToAIChat(_ entry: TranscriptionHistoryEntry) {
        attachToAIChat(title: entry.modeName, content: preferredAIChatText(for: entry))
    }

    func sendAIChatMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard settings.hasOpenAIAPIKey else {
            aiChatError = L.tr("Add an OpenAI API key in Settings first.", "Сначала добавьте OpenAI API key в настройках.")
            return
        }

        let conversationID = ensureSelectedAIChatConversation()
        appendAIChatMessage(
            AIChatMessage(role: .user, content: trimmed),
            to: conversationID
        )
        runAIChatRequest(conversationID: conversationID)
    }

    func toggleAIChatVoiceMessage() {
        if isAIChatVoiceRecording {
            stopAIChatVoiceMessage()
        } else {
            startAIChatVoiceMessage()
        }
    }

    private func attachToAIChat(title: String, content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let conversationID = ensureSelectedAIChatConversation()
        appendAIChatMessage(
            AIChatMessage(
                role: .user,
                content: "Attached context: \(title)\n\n\(trimmed)",
                attachmentTitle: title
            ),
            to: conversationID
        )
    }

    private func appendAIChatMessage(_ message: AIChatMessage, to conversationID: UUID) {
        guard let index = aiChatConversations.firstIndex(where: { $0.id == conversationID }) else { return }
        aiChatConversations[index].messages.append(message)
        aiChatConversations[index].updatedAt = Date()
        updateAIChatTitleIfNeeded(at: index, using: message)
        aiChatConversations.sort { $0.updatedAt > $1.updatedAt }
        Storage.shared.saveAIChatConversations(aiChatConversations)
    }

    private func updateAIChatTitleIfNeeded(at index: Int, using message: AIChatMessage) {
        guard aiChatConversations[index].messages.count == 1 else { return }
        let words = message.content
            .split(whereSeparator: { $0.isWhitespace })
            .prefix(5)
            .joined(separator: " ")
        if !words.isEmpty {
            aiChatConversations[index].title = String(words.prefix(44))
        }
    }

    private func runAIChatRequest(conversationID: UUID) {
        guard let conversation = aiChatConversations.first(where: { $0.id == conversationID }) else { return }
        isAIChatSending = true
        aiChatError = nil

        Task {
            do {
                let result = try await AIChatService.send(
                    messages: conversation.messages,
                    model: self.settings.selectedAIChatModel,
                    apiKey: self.settings.normalizedAPIKey
                )
                await MainActor.run {
                    self.appendAIChatMessage(
                        AIChatMessage(role: .assistant, content: result.text),
                        to: conversationID
                    )
                    let usage = UsageLog(
                        date: Date(),
                        modeName: "AI Chat",
                        engine: "openai",
                        promptTokens: result.promptTokens,
                        completionTokens: result.completionTokens,
                        totalTokens: result.promptTokens + result.completionTokens,
                        estimatedCost: UsageLog.estimateCost(prompt: result.promptTokens, completion: result.completionTokens, engine: .openai)
                    )
                    self.settings.usageLogs.append(usage)
                    self.saveSettings()
                    self.isAIChatSending = false
                }
            } catch {
                await MainActor.run {
                    self.aiChatError = error.localizedDescription
                    self.isAIChatSending = false
                }
            }
        }
    }

    private func startAIChatVoiceMessage() {
        guard state == .idle else {
            aiChatError = L.tr("Finish the current recording first.", "Сначала завершите текущую запись.")
            return
        }

        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            guard aiChatRecorder.startRecording(inputDeviceID: settings.selectedInputDeviceID) else {
                aiChatError = aiChatRecorder.error ?? L.tr("Could not start voice message.", "Не удалось начать голосовое сообщение.")
                return
            }
            isAIChatVoiceRecording = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.startAIChatVoiceMessage()
                    } else {
                        self?.aiChatError = "Microphone access denied. Please enable it in System Settings -> Privacy & Security."
                    }
                }
            }
        case .denied, .restricted:
            aiChatError = "Microphone access denied. Please enable it in System Settings -> Privacy & Security."
        @unknown default:
            aiChatError = "Microphone access denied. Please enable it in System Settings -> Privacy & Security."
        }
    }

    private func stopAIChatVoiceMessage() {
        isAIChatVoiceRecording = false
        let (audioURL, _) = aiChatRecorder.stopRecording()
        guard let audioURL else {
            aiChatError = L.tr("Voice message is too short.", "Голосовое сообщение слишком короткое.")
            return
        }

        guard validateTranscriptionPrerequisites(requiresMicrophone: false) else {
            try? FileManager.default.removeItem(at: audioURL)
            return
        }

        isAIChatSending = true
        aiChatError = nil
        let settingsSnapshot = settings

        Task {
            do {
                let engine = TranscriptionEngineFactory.create(for: settingsSnapshot.engineType, settings: settingsSnapshot)
                let text = try await engine.transcribe(
                    audioURL: audioURL,
                    language: settingsSnapshot.language == "auto" ? nil : settingsSnapshot.language,
                    timeRange: nil,
                    onProgress: nil
                )
                try? FileManager.default.removeItem(at: audioURL)
                await MainActor.run {
                    self.isAIChatSending = false
                    self.sendAIChatMessage(text)
                }
            } catch {
                try? FileManager.default.removeItem(at: audioURL)
                await MainActor.run {
                    self.aiChatError = error.localizedDescription
                    self.isAIChatSending = false
                }
            }
        }
    }

    private func preferredAIChatText(for entry: TranscriptionHistoryEntry) -> String {
        if let summary = entry.summaryText?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            return summary
        }
        let processed = entry.processedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !processed.isEmpty { return processed }
        return entry.rawText
    }

    func requestFileTranscription(urls: [URL]) -> Bool {
        let supportedURLs = FileTranscriptionSupport.supportedURLs(from: urls)
        guard !supportedURLs.isEmpty else {
            showError(L.tr("No supported audio or video files selected.", "Не выбраны поддерживаемые аудио- или видеофайлы."))
            return false
        }

        fileTranscriptionImportRequest = FileTranscriptionImportRequest(urls: supportedURLs)
        return true
    }

    func consumeFileTranscriptionRequest(id: UUID) {
        guard fileTranscriptionImportRequest?.id == id else { return }
        fileTranscriptionImportRequest = nil
    }

    func requestGoogleMeetImport() {
        googleMeetImportRequestID = UUID()
    }

    func consumeGoogleMeetImportRequest(id: UUID) {
        guard googleMeetImportRequestID == id else { return }
        googleMeetImportRequestID = nil
    }

    // MARK: - Hotkey Setup

    func reloadHotkeyManager() {
        hotkeyManager.stop()
        liveTranslatorHotkeyManager.stop()
        setupHotkey()
    }

    private func setupHotkey() {
        // Main Dictation Hotkey
        hotkeyManager.config = settings.hotkeyConfig
        hotkeyManager.start(
            promptUser: false, // Don't prompt automatically on launch, user triggers via Settings
            onKeyDown: { [weak self] in self?.handleKeyDown() },
            onKeyUp: { [weak self] in self?.handleKeyUp() }
        )
        
        // Live Translator Hotkey
        if Self.liveTranslatorFeatureAvailable && settings.liveTranslatorEnabled {
            liveTranslatorHotkeyManager.config = settings.liveTranslatorHotkeyConfig
            liveTranslatorHotkeyManager.start(
                promptUser: false,
                onKeyDown: { [weak self] in self?.handleLiveTranslatorKeyDown() },
                onKeyUp: { } // Live translator is a toggle, we only care about onKeyDown
            )
        } else {
            liveTranslatorHotkeyManager.stop()
        }
    }

    func requestAccessibilityPermission() {
        // First check silently — if already trusted, just update state
        if hotkeyManager.isTrusted {
            self.isHotkeyTrusted = true
            reloadHotkeyManager()
            return
        }
        resetStaleAccessibilityEntries()
        // Not trusted — AXIsProcessTrustedWithOptions(prompt: true) shows the native
        // system dialog with "Deny" / "Open System Settings" buttons.
        AppDelegate.shared?.showAccessibilityDragHelper()
        let trusted = hotkeyManager.checkTrust(prompt: true)
        self.isHotkeyTrusted = trusted
        if trusted {
            AppDelegate.shared?.hideAccessibilityDragHelper()
            reloadHotkeyManager()
        }
    }

    private func resetStaleAccessibilityEntries() {
        let bundleIDs = [
            "com.whisperkiller.app",
            "com.whisperfree.app",
            "com.whisperflow.app",
            "WhisperFree",
            "WhisperFlow"
        ]

        for bundleID in bundleIDs {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", "Accessibility", bundleID]
            process.standardOutput = Pipe()
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                print("Accessibility reset failed for \(bundleID): \(error)")
            }
        }
    }

    func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }

    private func startPermissionCheckTimer() {
        // Run every 1 second while in common modes (prevents blocking during UI interaction)
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                let trusted = self.hotkeyManager.isTrusted
                if self.isHotkeyTrusted != trusted {
                    self.isHotkeyTrusted = trusted
                    if trusted {
                        // Automatically start manager if it was blocked before
                        AppDelegate.shared?.hideAccessibilityDragHelper()
                        self.reloadHotkeyManager()
                    }
                }
                
                let micStatus = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                if self.isMicrophoneGranted != micStatus {
                    self.isMicrophoneGranted = micStatus
                }
                
                let denied = AVCaptureDevice.authorizationStatus(for: .audio) == .denied
                if self.isMicrophoneDenied != denied {
                    self.isMicrophoneDenied = denied
                    // Auto-dismiss permission error overlay when access is granted
                    if !denied, let error = self.lastError, error.contains("Microphone access denied") {
                        self.lastError = nil
                        if self.state == .idle && self.backgroundProcessingCount == 0 {
                            self.showOverlayWindow = false
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Recording Mode Logic
    
    // MARK: Live Translator Toggle
    private func handleLiveTranslatorKeyDown() {
        guard Self.liveTranslatorFeatureAvailable else { return }
        guard settings.liveTranslatorEnabled else { return }
        
        // Microphone permission is required only for microphone capture.
        guard settings.useScreenCaptureKit || AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            DispatchQueue.main.async {
                self.lastError = "Microphone access denied. Please grant permission in System Settings."
                self.showOverlayWindow = true
            }
            return
        }

        toggleLiveTranslator()
    }

    // MARK: Main App Hotkey
    private func handleKeyDown() {
        switch settings.recordingMode {
        case .hold:
            if state == .idle {
                keyDownTime = Date()
                startRecording()
            }

        case .toggle:
            if state == .recording {
                stopAndTranscribe()
            } else if state == .idle {
                startRecording()
            }

        case .pushToTalk:
            if state == .idle {
                keyDownTime = Date()
                startRecording()
            } else if state == .recording {
                stopAndTranscribe()
            }
        }
    }

    private func handleKeyUp() {
        let now = Date()
        let duration = keyDownTime.map { now.timeIntervalSince($0) } ?? 0
        
        switch settings.recordingMode {
        case .hold:
            if state == .recording {
                // If held more than 0.8s, it's a real recording. 
                // If less, it might be a misclick or the user wants to cancel.
                if duration > 0.8 {
                    scheduleStopAndTranscribe(after: postReleaseTail)
                } else {
                    cancelRecording()
                }
            }

        case .toggle:
            break

        case .pushToTalk:
            if state == .recording {
                if duration >= 0.8 {
                    // It was a long press (PTT), stop on release
                    scheduleStopAndTranscribe(after: postReleaseTail)
                } else {
                    // It was a short tap (< 800ms), let it keep recording (Toggle behavior)
                }
            }
        }
        keyDownTime = nil
    }


    // MARK: - Recording Actions

    private func validateTranscriptionPrerequisites(requiresMicrophone: Bool) -> Bool {
        if settings.engineType == .cloud && !settings.hasOpenAIAPIKey {
            showError("No API key configured. Go to Settings → Engine & API to add your OpenAI API key.")
            return false
        }

        if settings.selectedMode.requiresAI && !settings.enablePostProcessing {
            showError("The selected mode requires AI Refinement. Enable it in Settings → Engine & API.")
            return false
        }

        if settings.selectedMode.requiresAI && !settings.hasOpenAIAPIKey {
            showError("The selected mode requires a valid OpenAI API key. Add it in Settings → Engine & API.")
            return false
        }

        if settings.engineType == .local && !modelManager.isModelDownloaded(settings.localModelSize) {
            showError("Model '\(settings.localModelSize.rawValue)' not downloaded. Go to Settings → Engine to download.")
            return false
        }

        if settings.engineType == .qwenASR && !QwenASRTranscriber.isAppleSilicon {
            showError("Qwen3-ASR MLX requires Apple Silicon. Choose another local engine in Settings.")
            return false
        }

        if settings.engineType == .gigaAM && GigaAMTranscriber.findPythonBinary() == nil {
            showError("Python 3 not found. Install Python 3, then install the GigaAM packages in Settings → Engine & API.")
            return false
        }

        if requiresMicrophone {
            guard hotkeyManager.isTrusted else {
                isHotkeyTrusted = false
                AppDelegate.shared?.showAccessibilityDragHelper()
                showError("Enable Accessibility in System Settings, then start recording again.")
                return false
            }

            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                isMicrophoneGranted = true
                isMicrophoneDenied = false
            case .notDetermined:
                isMicrophoneGranted = false
                isMicrophoneDenied = false
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                    DispatchQueue.main.async {
                        self?.isMicrophoneGranted = granted
                        self?.isMicrophoneDenied = !granted
                        if !granted {
                            self?.showError("Enable Microphone in System Settings, then start recording again.")
                        }
                    }
                }
                showError("Allow microphone access, then start recording again.")
                return false
            case .denied, .restricted:
                isMicrophoneGranted = false
                isMicrophoneDenied = true
                showError("Enable Microphone in System Settings, then start recording again.")
                return false
            @unknown default:
                isMicrophoneGranted = false
                isMicrophoneDenied = true
                showError("Enable Microphone in System Settings, then start recording again.")
                return false
            }
        }

        return true
    }

    private func initialTranscriptionStage(for settings: AppSettings) -> ProcessingStage {
        guard settings.engineType == .qwenASR else {
            return .transcribing
        }

        let runtimeReady = QwenASRTranscriber.isRuntimeInstalled
        let modelReady = modelManager.isQwenModelDownloaded(settings.qwenASRModel)
        return runtimeReady && modelReady ? .transcribing : .preparing
    }

    func startRecording() {
        guard state == .idle else { return }
        guard validateTranscriptionPrerequisites(requiresMicrophone: true) else {
            resetFailedRecordingStart(keepErrorOverlay: true)
            return
        }
        cancelPendingStopTask()

        lastError = nil

        guard recorder.startRecording(inputDeviceID: settings.selectedInputDeviceID) else {
            let message = recorder.error ?? "Could not start recording. Check microphone access and try again."
            resetFailedRecordingStart()
            showError(message)
            return
        }

        state = .recording
        showOverlayWindow = true
    }

    private func resetFailedRecordingStart(keepErrorOverlay: Bool = false) {
        cancelPendingStopTask()
        _ = recorder.stopRecording()
        recorder.stopMonitoring()
        recorder.cleanup()
        state = .idle
        keyDownTime = nil
        refreshBackgroundProcessingState()
        if !keepErrorOverlay && backgroundProcessingCount == 0 {
            showOverlayWindow = false
        }
    }




    func cancelRecording() {
        cancelPendingStopTask()
        if state == .processing {
            cancelProcessing()
            return
        }
        
        let (audioURL, duration) = recorder.stopRecording()
        if let audioURL {
            saveCancelledRecordingHistoryEntry(
                audioURL: audioURL,
                duration: duration,
                modeName: settings.selectedMode.name,
                engineUsed: settings.engineType.rawValue + " + Cancelled",
                rawText: "",
                processedText: "",
                preserveSource: false
            )
        }
        recorder.cleanup()
        state = .idle
        refreshBackgroundProcessingState()
    }

    private var currentEngine: TranscriptionEngine?

    func cancelProcessing() {
        guard state == .processing || backgroundProcessingCount > 0 else { return }

        cancelPendingStopTask()
        if let cancelledRecording = activeProcessingRecording {
            saveCancelledRecordingHistoryEntry(
                audioURL: cancelledRecording.audioURL,
                duration: cancelledRecording.duration,
                modeName: cancelledRecording.modeName,
                engineUsed: cancelledRecording.engineUsed + " + Cancelled",
                rawText: cancelledRecording.rawText,
                processedText: cancelledRecording.processedText,
                preserveSource: true
            )
            activeProcessingRecording = nil
        } else if !processingQueue.isEmpty {
            let cancelledRecording = processingQueue.removeFirst()
            saveCancelledRecordingHistoryEntry(
                audioURL: cancelledRecording.audioURL,
                duration: cancelledRecording.duration,
                modeName: cancelledRecording.modeName,
                engineUsed: cancelledRecording.engineUsed + " + Cancelled",
                rawText: cancelledRecording.rawText,
                processedText: cancelledRecording.processedText,
                preserveSource: false
            )
        }
        currentProcessingToken = nil
        currentProcessingTask?.cancel()
        currentProcessingTask = nil
        currentEngine?.cancel()
        currentEngine = nil

        if state == .processing {
            _ = recorder.stopRecording()
            recorder.cleanup()
            state = .idle
        }
        refreshBackgroundProcessingState()
        startNextProcessingJobIfNeeded()
    }

    func retranscribeHistoryEntry(_ entry: TranscriptionHistoryEntry) async {
        guard state == .idle && backgroundProcessingCount == 0 else {
            showError("Wait for the current transcription to finish first.")
            return
        }

        guard let path = entry.audioFilePath else {
            showError("No saved audio found for this history entry.")
            return
        }

        guard FileManager.default.fileExists(atPath: path) else {
            showError("Saved audio file is no longer available.")
            return
        }

        guard validateTranscriptionPrerequisites(requiresMicrophone: false) else { return }

        lastError = nil
        state = .processing
        processingStage = initialTranscriptionStage(for: settings)

        defer {
            currentEngine = nil
            state = .idle
            processingStage = .none
        }

        do {
            let audioURL = URL(fileURLWithPath: path)
            let fileAttrs = try? FileManager.default.attributesOfItem(atPath: audioURL.path)
            let fileSize = fileAttrs?[.size] as? Int64 ?? 0
            print("whisper_debug: 🔁 Retranscribing audio file: \(audioURL.lastPathComponent), size: \(fileSize) bytes")

            processingStage = initialTranscriptionStage(for: settings)
            let engine = TranscriptionEngineFactory.create(for: settings.engineType, settings: settings)
            currentEngine = engine

            let lang = settings.language == "auto" ? nil : settings.language
            let rawText = try await engine.transcribe(audioURL: audioURL, language: lang, timeRange: nil, onProgress: nil)

            guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                showError("No speech detected. Try a different recording.")
                return
            }

            var processedText = rawText
            var usage: UsageLog? = nil
            var processingErrorMessage: String?

            let shouldRunDiarization = settings.enableSpeakerDiarization && settings.canUseSpeakerDiarization
            let shouldRunStandardPostProcessing = !shouldRunDiarization
                && settings.enablePostProcessing
                && settings.selectedMode.name != "Raw"
                && !settings.selectedMode.systemPrompt.isEmpty

            if shouldRunDiarization {
                print("ℹ️ Skipping standard AI refinement because Diarization is active.")
            } else if shouldRunStandardPostProcessing {
                processingStage = .postProcessing
                do {
                    let processor = PostProcessor(settings: settings)
                    let result = try await processor.process(text: rawText, mode: settings.selectedMode)
                    processedText = result.text

                    let totalTokens = result.promptTokens + result.completionTokens
                    if totalTokens > 0 {
                        let engine = settings.postProcessingEngine
                        usage = UsageLog(
                            date: Date(),
                            modeName: settings.selectedMode.name,
                            engine: engine.rawValue,
                            promptTokens: result.promptTokens,
                            completionTokens: result.completionTokens,
                            totalTokens: totalTokens,
                            estimatedCost: UsageLog.estimateCost(prompt: result.promptTokens, completion: result.completionTokens, engine: engine)
                        )
                    }
                } catch {
                    print("⚠️ AI refinement failed during retranscription: \(error)")
                    processingErrorMessage = error.localizedDescription
                    processingStage = .transcribing
                }
            }

            if shouldRunDiarization {
                processingStage = .postProcessing
                do {
                    let processor = PostProcessor(settings: settings)
                    let diarizationResult = try await processor.diarize(text: processedText)
                    processedText = diarizationResult.text

                    let currentTokens = (usage?.totalTokens ?? 0) + diarizationResult.promptTokens + diarizationResult.completionTokens
                    let currentPromptTokens = (usage?.promptTokens ?? 0) + diarizationResult.promptTokens
                    let currentCompletionTokens = (usage?.completionTokens ?? 0) + diarizationResult.completionTokens

                    usage = UsageLog(
                        date: Date(),
                        modeName: "Diarization",
                        engine: PostProcessingEngine.openai.rawValue,
                        promptTokens: currentPromptTokens,
                        completionTokens: currentCompletionTokens,
                        totalTokens: currentTokens,
                        estimatedCost: UsageLog.estimateCost(prompt: currentPromptTokens, completion: currentCompletionTokens, engine: .openai)
                    )
                } catch {
                    print("⚠️ Diarization failed during retranscription: \(error)")
                    processingErrorMessage = error.localizedDescription
                }
            }

            let filteredRawText = ProfanityFilter.apply(to: rawText, settings: settings)
            let filteredProcessedText = ProfanityFilter.apply(to: processedText, settings: settings)

            guard let index = history.firstIndex(where: { $0.entryId == entry.entryId }) else { return }

            history[index].rawText = filteredRawText
            history[index].processedText = filteredProcessedText
            history[index].summaryText = nil
            history[index].processingError = processingErrorMessage
            history[index].modeName = settings.selectedMode.name
            history[index].engineUsed = settings.engineType.rawValue
                + (shouldRunStandardPostProcessing ? " + AI" : "")
                + (shouldRunDiarization ? " + Diarization" : "")
            history[index].usage = usage

            Storage.shared.updateTranscriptionHistoryEntry(history[index])

            if let usage {
                settings.usageLogs.append(usage)
                cleanupOldLogs()
                saveSettings()
            }

            lastTranscription = filteredProcessedText
        } catch {
            if let index = history.firstIndex(where: { $0.entryId == entry.entryId }) {
                history[index].processingError = error.localizedDescription
                Storage.shared.updateTranscriptionHistoryEntry(history[index])
            }
            showError(error.localizedDescription)
        }
    }

    func stopAndTranscribe() {
        cancelPendingStopTask()
        guard state == .recording else { return }

        let (audioURLOptional, recordingDuration) = recorder.stopRecording()
        guard let audioURL = audioURLOptional else {
            // Recording too short or failed
            state = .idle
            refreshBackgroundProcessingState()
            return
        }

        let job = RecordingProcessingJob(
            id: UUID(),
            audioURL: audioURL,
            duration: recordingDuration,
            modeName: settings.selectedMode.name,
            engineUsed: settings.engineType.rawValue
        )
        state = .idle
        enqueueRecordingForProcessing(job)
    }

    private func enqueueRecordingForProcessing(_ job: RecordingProcessingJob) {
        processingQueue.append(job)
        refreshBackgroundProcessingState()
        startNextProcessingJobIfNeeded()
    }

    private func startNextProcessingJobIfNeeded() {
        guard activeProcessingRecording == nil,
              currentProcessingTask == nil,
              !processingQueue.isEmpty
        else { return }

        var job = processingQueue.removeFirst()
        job.stage = .transcribing
        activeProcessingRecording = job
        currentProcessingToken = job.id
        refreshBackgroundProcessingState()

        let jobID = job.id
        currentProcessingTask = Task { @MainActor in
            await self.processRecordingJob(id: jobID)
        }
    }

    private func processRecordingJob(id jobID: UUID) async {
        guard let job = activeProcessingRecording, job.id == jobID else { return }

        let audioURL = job.audioURL
        let recordingDuration = job.duration
        let selectedModeName = job.modeName
        let selectedEngine = job.engineUsed
        var rawText = ""
        var processedText = ""
        var usage: UsageLog? = nil
        var processingErrorMessage: String?

        do {
            let fileAttrs = try? FileManager.default.attributesOfItem(atPath: audioURL.path)
            let fileSize = fileAttrs?[.size] as? Int64 ?? 0
            print("whisper_debug: 📁 Audio file for transcription: \(audioURL.lastPathComponent), size: \(fileSize) bytes")

            if fileSize < 1000 {
                print("whisper_debug: ⚠️ WARNING: Audio file is suspiciously small (\(fileSize) bytes)!")
            }

            updateActiveProcessingText(for: jobID, rawText: nil, processedText: nil, stage: initialTranscriptionStage(for: settings))
            let engine = TranscriptionEngineFactory.create(for: settings.engineType, settings: settings)
            currentEngine = engine
            let lang = settings.language == "auto" ? nil : settings.language
            rawText = try await engine.transcribe(audioURL: audioURL, language: lang, timeRange: nil, onProgress: nil)
            updateActiveProcessingText(for: jobID, rawText: rawText, processedText: nil, stage: nil)
            if currentProcessingToken == jobID {
                currentEngine = nil
            }
            try Task.checkCancellation()

            print("whisper_debug: 📝 Raw transcription result: '\(rawText)' (length: \(rawText.count))")

            let trimmedRawText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedRawText.isEmpty else {
                let errorMessage = "No speech detected. Try speaking more clearly or check your microphone."
                saveFailedRecordingHistoryEntry(
                    audioURL: audioURL,
                    rawText: rawText,
                    processedText: processedText,
                    errorMessage: errorMessage,
                    modeName: selectedModeName,
                    duration: recordingDuration,
                    engineUsed: selectedEngine + " + Error",
                    usage: usage
                )
                finishProcessingJob(id: jobID)
                showError(errorMessage)
                return
            }

            processedText = rawText
            updateActiveProcessingText(for: jobID, rawText: nil, processedText: processedText, stage: nil)

            let shouldRunDiarization = settings.enableSpeakerDiarization && settings.canUseSpeakerDiarization
            let shouldRunStandardPostProcessing = !shouldRunDiarization
                && settings.enablePostProcessing
                && settings.selectedMode.name != "Raw"
                && !settings.selectedMode.systemPrompt.isEmpty

            if shouldRunDiarization {
                print("ℹ️ Skipping standard AI refinement because Diarization is active.")
            } else if shouldRunStandardPostProcessing {
                updateActiveProcessingText(for: jobID, rawText: nil, processedText: nil, stage: .postProcessing)
                do {
                    let processor = PostProcessor(settings: settings)
                    let result = try await processor.process(text: rawText, mode: settings.selectedMode)
                    try Task.checkCancellation()
                    processedText = result.text
                    updateActiveProcessingText(for: jobID, rawText: nil, processedText: processedText, stage: nil)

                    let totalTokens = result.promptTokens + result.completionTokens
                    if totalTokens > 0 {
                        let engine = settings.postProcessingEngine
                        usage = UsageLog(
                            date: Date(),
                            modeName: settings.selectedMode.name,
                            engine: engine.rawValue,
                            promptTokens: result.promptTokens,
                            completionTokens: result.completionTokens,
                            totalTokens: totalTokens,
                            estimatedCost: UsageLog.estimateCost(prompt: result.promptTokens, completion: result.completionTokens, engine: engine)
                        )
                    }
                } catch {
                    print("⚠️ AI refinement failed: \(error)")
                    processingErrorMessage = error.localizedDescription
                    self.showError(postProcessingFallbackMessage(for: error))
                    updateActiveProcessingText(for: jobID, rawText: nil, processedText: nil, stage: .transcribing)
                }
            }

            if shouldRunDiarization {
                updateActiveProcessingText(for: jobID, rawText: nil, processedText: nil, stage: .postProcessing)
                do {
                    let processor = PostProcessor(settings: settings)
                    let diarizationResult = try await processor.diarize(text: processedText)
                    try Task.checkCancellation()
                    processedText = diarizationResult.text
                    updateActiveProcessingText(for: jobID, rawText: nil, processedText: processedText, stage: nil)

                    let currentTokens = (usage?.totalTokens ?? 0) + diarizationResult.promptTokens + diarizationResult.completionTokens
                    let currentPromptTokens = (usage?.promptTokens ?? 0) + diarizationResult.promptTokens
                    let currentCompletionTokens = (usage?.completionTokens ?? 0) + diarizationResult.completionTokens

                    usage = UsageLog(
                        date: Date(),
                        modeName: "Diarization",
                        engine: PostProcessingEngine.openai.rawValue,
                        promptTokens: currentPromptTokens,
                        completionTokens: currentCompletionTokens,
                        totalTokens: currentTokens,
                        estimatedCost: UsageLog.estimateCost(prompt: currentPromptTokens, completion: currentCompletionTokens, engine: .openai)
                    )
                } catch {
                    print("⚠️ Diarization failed: \(error)")
                    processingErrorMessage = error.localizedDescription
                }
            }

            let filteredRawText = ProfanityFilter.apply(to: rawText, settings: settings)
            processedText = ProfanityFilter.apply(to: processedText, settings: settings)
            try Task.checkCancellation()

            if settings.autoTypeResult {
                let shouldOwnTypingState = state != .recording
                if shouldOwnTypingState {
                    state = .typing
                }
                try await Task.sleep(nanoseconds: 50_000_000)
                try Task.checkCancellation()
                AutoTyper.insert(text: processedText, method: settings.insertionMethod)

                if settings.experimentalAutoEnter {
                    AutoTyper.simulateReturn()
                }

                if shouldOwnTypingState, state == .typing {
                    state = .idle
                }
            }

            let wordCount = processedText.split { $0.isWhitespace || $0.isPunctuation }.count
            settings.lifetimeWords += wordCount
            settings.lifetimeDuration += recordingDuration
            saveSettings()

            let persistentAudioPath = persistRecordingAudio(from: audioURL)

            let entry = TranscriptionHistoryEntry(
                rawText: filteredRawText,
                processedText: processedText,
                processingError: processingErrorMessage,
                modeName: selectedModeName,
                duration: recordingDuration,
                engineUsed: selectedEngine + (shouldRunStandardPostProcessing ? " + AI" : "") + (shouldRunDiarization ? " + Diarization" : ""),
                usage: usage,
                audioFilePath: persistentAudioPath,
                ownsAudioFile: persistentAudioPath != nil
            )
            Storage.shared.addTranscriptionHistoryEntry(entry)
            history.insert(entry, at: 0)

            if let u = usage {
                settings.usageLogs.append(u)
                cleanupOldLogs()
            }
            saveSettings()

            lastTranscription = processedText
            finishProcessingJob(id: jobID)
        } catch {
            if Task.isCancelled || error is CancellationError {
                print("whisper_debug: ⏹️ Processing cancelled by user")
                finishProcessingJob(id: jobID)
                return
            }

            print("whisper_debug: ❌ Transcription task failed: \(error)")
            saveFailedRecordingHistoryEntry(
                audioURL: audioURL,
                rawText: rawText,
                processedText: processedText,
                errorMessage: error.localizedDescription,
                modeName: selectedModeName,
                duration: recordingDuration,
                engineUsed: selectedEngine + " + Error",
                usage: usage
            )
            finishProcessingJob(id: jobID)
            showError(error.localizedDescription)
        }
    }

    private func persistRecordingAudio(from sourceURL: URL, preserveSource: Bool = false) -> String? {
        let fileName = "recording_\(UUID().uuidString).wav"
        let targetURL = Storage.recordingsDirectory.appendingPathComponent(fileName)

        do {
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }

            if preserveSource {
                try FileManager.default.copyItem(at: sourceURL, to: targetURL)
                print("whisper_debug: 📁 Copied recording to: \(targetURL.path)")
            } else {
                try FileManager.default.moveItem(at: sourceURL, to: targetURL)
                print("whisper_debug: 📁 Moved recording to: \(targetURL.path)")
            }
            return targetURL.path
        } catch {
            print("whisper_debug: ❌ Failed to persist recording: \(error)")
            return nil
        }
    }

    private func refreshBackgroundProcessingState() {
        backgroundProcessingCount = processingQueue.count + (activeProcessingRecording == nil ? 0 : 1)

        if let stage = activeProcessingRecording?.stage {
            processingStage = stage
        } else if backgroundProcessingCount == 0 && state != .processing {
            processingStage = .none
        }

        showOverlayWindow = shouldShowOverlay
    }

    private func finishProcessingJob(id jobID: UUID) {
        if activeProcessingRecording?.id == jobID {
            activeProcessingRecording = nil
        }
        if currentProcessingToken == jobID {
            currentEngine = nil
            currentProcessingTask = nil
            currentProcessingToken = nil
        }
        refreshBackgroundProcessingState()
        startNextProcessingJobIfNeeded()
    }

    private func updateActiveProcessingText(for jobID: UUID, rawText: String?, processedText: String?, stage: ProcessingStage?) {
        guard var recording = activeProcessingRecording, recording.id == jobID else { return }
        if let rawText {
            recording.rawText = rawText
        }
        if let processedText {
            recording.processedText = processedText
        }
        if let stage {
            recording.stage = stage
        }
        activeProcessingRecording = recording
        refreshBackgroundProcessingState()
    }

    private func saveCancelledRecordingHistoryEntry(
        audioURL: URL,
        duration: TimeInterval,
        modeName: String,
        engineUsed: String,
        rawText: String,
        processedText: String,
        preserveSource: Bool
    ) {
        let persistentAudioPath = persistRecordingAudio(from: audioURL, preserveSource: preserveSource)
        let filteredRawText = ProfanityFilter.apply(to: rawText, settings: settings)
        let filteredProcessedText = processedText.isEmpty ? "" : ProfanityFilter.apply(to: processedText, settings: settings)
        let entry = TranscriptionHistoryEntry(
            rawText: filteredRawText,
            processedText: filteredProcessedText,
            processingError: L.tr("Recording saved without transcription.", "Запись сохранена без транскрипции."),
            modeName: modeName,
            duration: duration,
            engineUsed: engineUsed,
            audioFilePath: persistentAudioPath,
            ownsAudioFile: persistentAudioPath != nil
        )
        Storage.shared.addTranscriptionHistoryEntry(entry)
        history.insert(entry, at: 0)
    }

    private func saveFailedRecordingHistoryEntry(
        audioURL: URL,
        rawText: String,
        processedText: String,
        errorMessage: String,
        modeName: String,
        duration: TimeInterval,
        engineUsed: String,
        usage: UsageLog?
    ) {
        let persistentAudioPath = persistRecordingAudio(from: audioURL)
        let filteredRawText = ProfanityFilter.apply(to: rawText, settings: settings)
        let fallbackText = processedText.isEmpty ? filteredRawText : ProfanityFilter.apply(to: processedText, settings: settings)
        let entry = TranscriptionHistoryEntry(
            rawText: filteredRawText,
            processedText: fallbackText,
            processingError: errorMessage,
            modeName: modeName,
            duration: duration,
            engineUsed: engineUsed,
            usage: usage,
            audioFilePath: persistentAudioPath,
            ownsAudioFile: persistentAudioPath != nil
        )
        Storage.shared.addTranscriptionHistoryEntry(entry)
        history.insert(entry, at: 0)
    }

    private func scheduleStopAndTranscribe(after delay: TimeInterval) {
        cancelPendingStopTask()
        pendingStopTask = Task { @MainActor [weak self] in
            let delayNanoseconds = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled, let self else { return }
            guard self.state == .recording else { return }
            self.stopAndTranscribe()
        }
    }

    private func cancelPendingStopTask() {
        pendingStopTask?.cancel()
        pendingStopTask = nil
    }

    private func postProcessingFallbackMessage(for error: Error) -> String {
        if let transcriptionError = error as? TranscriptionError {
            switch transcriptionError {
            case .noAPIKey:
                return "AI refinement skipped: OpenAI API key is missing. Using the raw transcript."
            case .networkError(let message):
                return "AI refinement failed: \(message) Using the raw transcript."
            case .invalidResponse:
                return "AI refinement failed: invalid response from the AI service. Using the raw transcript."
            case .modelNotDownloaded:
                return "AI refinement failed: local model is missing. Using the raw transcript."
            case .transcriptionFailed(let message):
                return "AI refinement failed: \(message) Using the raw transcript."
            }
        }

        return "AI refinement failed. Using the raw transcript."
    }

    func showError(_ message: String) {
        lastError = message
        showOverlayWindow = true
        
        errorTimer?.cancel()
        errorTimer = Just(())
            .delay(for: .seconds(5), scheduler: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                self.lastError = nil
                self.showOverlayWindow = self.shouldShowOverlay
            }
    }

    // MARK: - Tray toggle (always uses toggle behavior)

    func toggleFromMenuBar() {
        if state == .recording {
            stopAndTranscribe()
        } else if state == .idle {
            startRecording()
        }
    }

    func toggleLiveTranslator() {
        guard Self.liveTranslatorFeatureAvailable else {
            showError("Live Translator is planned for a future release.")
            return
        }

        if LiveTranslatorManager.shared.isRunning {
            LiveTranslatorManager.shared.stop()
        } else {
            LiveTranslatorManager.shared.start()
        }
    }

    func toggleRussianMicrophoneTranslator() {
        guard Self.liveTranslatorFeatureAvailable else {
            showError("Live Translator is planned for a future release.")
            return
        }

        if LiveTranslatorManager.shared.isRunning {
            LiveTranslatorManager.shared.stop()
            return
        }

        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .authorized:
            startRussianMicrophoneTranslator()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.startRussianMicrophoneTranslator()
                    } else {
                        self?.showError("Microphone access denied. Please enable it in System Settings → Privacy & Security.")
                    }
                }
            }
        case .denied, .restricted:
            showError("Microphone access denied. Please enable it in System Settings → Privacy & Security.")
        @unknown default:
            showError("Microphone access denied. Please enable it in System Settings → Privacy & Security.")
        }
    }

    private func startRussianMicrophoneTranslator() {
        settings.useScreenCaptureKit = false
        settings.liveTranslatorSourceLanguage = "ru"
        settings.liveTranslatorTargetLanguage = "Russian"
        saveSettings()
        NotificationCenter.default.post(name: NSNotification.Name("LiveTranslatorSettingsChanged"), object: nil)
        LiveTranslatorManager.shared.start()
    }

    // MARK: - History

    func deleteTranscriptionHistoryEntry(_ entry: TranscriptionHistoryEntry) {
        Storage.shared.deleteTranscriptionHistoryEntry(id: entry.entryId)
        history.removeAll { $0.entryId == entry.entryId }
    }

    func clearHistory() {
        Storage.shared.clearHistory()
        history.removeAll()
    }

    func updateTranscriptionText(entry: TranscriptionHistoryEntry, newText: String) {
        var updatedEntry = entry
        if updatedEntry.summaryText?.isEmpty == false {
            updatedEntry.summaryText = newText
        } else {
            updatedEntry.processedText = newText
        }
        
        // If it has an associated audio file, we could rename it too, 
        // but that might break references if not careful. 
        // For now, let's just update the text in storage and local state.
        
        if let index = history.firstIndex(where: { $0.entryId == entry.entryId }) {
            history[index] = updatedEntry
            Storage.shared.updateTranscriptionHistoryEntry(updatedEntry)
        }
    }

    func saveSummary(entryId: UUID, summary: String, usage: UsageLog?) {
        guard let index = history.firstIndex(where: { $0.entryId == entryId }) else { return }

        history[index].summaryText = summary

        if let usage {
            if let existingUsage = history[index].usage {
                history[index].usage = UsageLog(
                    date: usage.date,
                    modeName: existingUsage.modeName,
                    engine: usage.engine,
                    promptTokens: existingUsage.promptTokens + usage.promptTokens,
                    completionTokens: existingUsage.completionTokens + usage.completionTokens,
                    totalTokens: existingUsage.totalTokens + usage.totalTokens,
                    estimatedCost: existingUsage.estimatedCost + usage.estimatedCost,
                    audioDurationSeconds: existingUsage.audioDurationSeconds ?? usage.audioDurationSeconds
                )
            } else {
                history[index].usage = usage
            }

            settings.usageLogs.append(usage)
            cleanupOldLogs()
            saveSettings()
        }

        Storage.shared.updateTranscriptionHistoryEntry(history[index])
    }

    private func cleanupOldLogs() {
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        settings.usageLogs.removeAll { $0.date < sevenDaysAgo }
    }

    func stopAll() {
        print("🛑 AppState: Stopping all audio services...")
        _ = recorder.stopRecording()
        recorder.stopMonitoring()
        LiveTranslatorManager.shared.stop()
    }

}
