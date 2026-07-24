import SwiftUI
import AVFoundation

struct LiveTranslatorSettingsView: View {
    @ObservedObject var appState: AppState
    @StateObject private var installer = DependencyInstaller.shared
    @State private var pullStatus: String?
    @State private var isPulling: Bool = false
    
    // For Hotkey recording
    @State private var isRecordingHotkey = false
    @State private var modifierFlags: CGEventFlags = []
    
    @State private var localModels: [String] = []
    @State private var isLoadingModels = false
    @State private var isOllamaRunning: Bool?
    @State private var modelLoadError: String?
    @State private var showAdvanced = false
    @State private var showLocalModel = false
    
    // Check if Ollama exists
    @State private var isOllamaInstalled: Bool = {
        FileManager.default.fileExists(atPath: "/Applications/Ollama.app")
    }()

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.liveTranslatorEnabled },
            set: { appState.setLiveTranslatorEnabled($0) }
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: SW.spacingXL) {
            HStack(spacing: SW.spacingM) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(SW.accent)
                Text("Live Translator")
                    .font(.title2.bold())
                Spacer()
            }

            VStack(spacing: 0) {
                Toggle(
                    L.tr("Enable Live Translator", "Включить Live Translator"),
                    isOn: enabledBinding
                )
                    .toggleStyle(.switch)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if appState.settings.liveTranslatorEnabled {
                    Divider()
                        .padding(.vertical, SW.spacingM)

                    HStack {
                        Label(
                            L.tr("Microphone to Russian", "Микрофон → русский"),
                            systemImage: "mic.fill"
                        )
                        Spacer()
                        Button(
                            appState.showLiveTranslatorOverlay
                                ? L.tr("Stop", "Остановить")
                                : L.tr("Start", "Запустить")
                        ) {
                            appState.toggleRussianMicrophoneTranslator()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .swCard()
            
            if appState.settings.liveTranslatorEnabled {
                VStack(alignment: .leading, spacing: SW.spacingS) {
                    SWSectionHeader(title: L.tr("Languages", "Языки"))

                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(L.tr("Spoken Language", "Исходный язык"))
                            Spacer()
                            Picker("", selection: $appState.settings.liveTranslatorSourceLanguage) {
                                ForEach(AppSettings.supportedLanguages, id: \.code) { lang in
                                    Text(lang.name).tag(lang.code)
                                }
                            }
                            .frame(width: 150)
                            .onChange(of: appState.settings.liveTranslatorSourceLanguage) { _, _ in
                                appState.settings.liveTranslatorSourceLanguage = AppSettings.normalizedLiveTranslatorSourceLanguageCode(appState.settings.liveTranslatorSourceLanguage)
                                appState.saveSettings()
                                notifyLiveTranslatorSettingsChanged()
                            }
                        }

                        Divider()

                        HStack {
                            Text(L.tr("Target Language", "Язык перевода"))
                            Spacer()
                            Picker("", selection: $appState.settings.liveTranslatorTargetLanguage) {
                                ForEach(AppSettings.supportedLanguages, id: \.code) { lang in
                                    if lang.code != "auto" {
                                        Text(lang.name).tag(lang.name)
                                    }
                                }
                            }
                            .frame(width: 150)
                            .onChange(of: appState.settings.liveTranslatorTargetLanguage) { _, _ in
                                appState.saveSettings()
                                notifyLiveTranslatorSettingsChanged()
                            }
                        }
                    }
                    .swCard()
                }

                VStack(alignment: .leading, spacing: SW.spacingS) {
                    SWSectionHeader(title: L.tr("Translation Engine", "Движок перевода"))

                    VStack(alignment: .leading, spacing: 16) {
                        Picker("", selection: $appState.settings.liveTranslatorEngine) {
                            ForEach(LiveTranslationEngine.allCases, id: \.self) { engine in
                                Text(engine.rawValue).tag(engine)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: appState.settings.liveTranslatorEngine) { _, _ in
                            appState.saveSettings()
                            notifyLiveTranslatorSettingsChanged()
                        }

                        if appState.settings.liveTranslatorEngine == .local {
                            Divider()
                            if !isOllamaInstalled {
                                ollamaInstaller
                            } else {
                                ClickableDisclosure(isExpanded: $showLocalModel) {
                                    OllamaModelSelector(
                                        selectedModel: $appState.settings.liveTranslatorLocalModel,
                                        localModels: localModels,
                                        isLoadingModels: isLoadingModels,
                                        isOllamaRunning: isOllamaRunning,
                                        modelLoadError: modelLoadError,
                                        pullStatus: pullStatus,
                                        isPulling: isPulling,
                                        onRefresh: refreshModels,
                                        onDownload: {
                                            pullModel(name: appState.settings.liveTranslatorLocalModel)
                                        },
                                        onModelChange: {
                                            appState.saveSettings()
                                            notifyLiveTranslatorSettingsChanged()
                                        }
                                    )
                                    .padding(.top, 8)
                                } label: {
                                    Text("Local model")
                                }
                            }
                        }
                    }
                    .swCard()
                }

                ClickableDisclosure(isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(L.tr("Global Hotkey", "Глобальная горячая клавиша"))
                            Spacer()
                            Button(action: {
                                isRecordingHotkey.toggle()
                                if isRecordingHotkey {
                                    modifierFlags = []
                                }
                            }) {
                                Text(isRecordingHotkey ? hotkeyRecordingText : appState.settings.liveTranslatorHotkeyConfig.displayString)
                                    .frame(minWidth: 100)
                            }
                            .buttonStyle(.bordered)
                            .tint(isRecordingHotkey ? .orange : .none)
                            .onExitCommand {
                                isRecordingHotkey = false
                            }
                            .background(
                                Group {
                                    if isRecordingHotkey {
                                        KeyEventHandlingView(
                                            isRecording: $isRecordingHotkey,
                                            modifierFlags: $modifierFlags,
                                            onCommit: { keyCode, useOption, useCommand, useControl, useShift in
                                                let newConfig = HotkeyConfig(
                                                    keyCode: keyCode,
                                                    useOption: useOption,
                                                    useCommand: useCommand,
                                                    useControl: useControl,
                                                    useShift: useShift
                                                )
                                                appState.settings.liveTranslatorHotkeyConfig = newConfig
                                                appState.saveSettings()
                                                appState.reloadHotkeyManager()
                                                isRecordingHotkey = false
                                            }
                                        )
                                        .frame(width: 0, height: 0)
                                    }
                                }
                            )
                        }

                        Divider()

                        Toggle(
                            L.tr("Capture System Audio", "Захватывать системный звук"),
                            isOn: $appState.settings.useScreenCaptureKit
                        )
                        .toggleStyle(.switch)
                        .onChange(of: appState.settings.useScreenCaptureKit) { _, _ in
                            appState.saveSettings()
                            notifyLiveTranslatorSettingsChanged()
                        }

                        Divider()

                        HStack {
                            Text(L.tr("Audio Input", "Аудиовход"))
                            Spacer()
                            Picker("", selection: $appState.settings.liveTranslatorInputDeviceID) {
                                Text(L.tr("System Default", "Системный по умолчанию")).tag(String?.none)
                                Divider()
                                ForEach(appState.availableInputDevices, id: \.uniqueID) { device in
                                    Text(device.localizedName).tag(String?.some(device.uniqueID))
                                }
                            }
                            .frame(width: 250)
                            .disabled(appState.settings.useScreenCaptureKit)
                            .opacity(appState.settings.useScreenCaptureKit ? 0.5 : 1.0)
                            .onChange(of: appState.settings.liveTranslatorInputDeviceID) { _, _ in
                                appState.saveSettings()
                                notifyLiveTranslatorSettingsChanged()
                            }
                        }
                    }
                    .swCard()
                    .padding(.top, 8)
                } label: {
                    Text(L.tr("Advanced", "Дополнительно"))
                }
            }
        }
        .onAppear {
            isOllamaInstalled = FileManager.default.fileExists(atPath: "/Applications/Ollama.app")
            let normalizedLanguage = AppSettings.normalizedLiveTranslatorTargetLanguage(appState.settings.liveTranslatorTargetLanguage)
            if normalizedLanguage != appState.settings.liveTranslatorTargetLanguage {
                appState.settings.liveTranslatorTargetLanguage = normalizedLanguage
                appState.saveSettings()
            }
            let normalizedSourceLanguage = AppSettings.normalizedLiveTranslatorSourceLanguageCode(appState.settings.liveTranslatorSourceLanguage)
            if normalizedSourceLanguage != appState.settings.liveTranslatorSourceLanguage {
                appState.settings.liveTranslatorSourceLanguage = normalizedSourceLanguage
                appState.saveSettings()
            }
            if isOllamaInstalled {
                refreshModels()
            } else {
                isOllamaRunning = nil
                localModels = []
                modelLoadError = nil
                pullStatus = nil
            }
        }
    }

    private var ollamaInstaller: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
                Text("Ollama is required for local translation.")
                    .font(.headline)
            }

            HStack {
                Button(installer.isInstallingOllama ? "Installing..." : "Install Ollama") {
                    installer.installOllama()
                }
                .disabled(installer.isInstallingOllama)
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                if installer.isInstallingOllama {
                    ProgressView(value: installer.ollamaProgress)
                        .frame(width: 100)
                }

                Text(installer.ollamaStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
        .onReceive(installer.$ollamaStatus) { status in
            if status == "Installed Successfully" {
                isOllamaInstalled = true
                refreshModels()
            }
        }
    }
    
    private var hotkeyRecordingText: String {
        var str = ""
        if modifierFlags.contains(CGEventFlags.maskControl) { str += "⌃ " }
        if modifierFlags.contains(CGEventFlags.maskAlternate) { str += "⌥ " }
        if modifierFlags.contains(CGEventFlags.maskShift) { str += "⇧ " }
        if modifierFlags.contains(CGEventFlags.maskCommand) { str += "⌘ " }
        str += "Press any key..."
        return str
    }

    private func notifyLiveTranslatorSettingsChanged() {
        NotificationCenter.default.post(name: NSNotification.Name("LiveTranslatorSettingsChanged"), object: nil)
    }
    
    private func pullModel(name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let engine = LocalTranslationEngine()
        isPulling = true
        pullStatus = "Checking Ollama..."
        
        Task { @MainActor in
            if await !engine.isRunning() {
                isOllamaRunning = false
                modelLoadError = "Start Ollama to select or download local models."
                pullStatus = "Failed: Ollama isn't running."
                isPulling = false
                return
            }
            isOllamaRunning = true
            modelLoadError = nil
            pullStatus = "Starting download..."
            do {
                try await engine.pullModel(name: trimmedName) { status in
                    DispatchQueue.main.async {
                        self.pullStatus = status
                    }
                }
                pullStatus = "Downloaded '\(trimmedName)' successfully."
                refreshModels()
            } catch {
                pullStatus = "Failed: \(error.localizedDescription)"
            }
            isPulling = false
        }
    }

    private func refreshModels() {
        isLoadingModels = true
        modelLoadError = nil
        if !isPulling {
            pullStatus = nil
        }

        Task {
            let engine = LocalTranslationEngine()
            if await !engine.isRunning() {
                await MainActor.run {
                    self.localModels = []
                    self.isOllamaRunning = false
                    self.modelLoadError = "Start Ollama to select or download local models."
                    self.isLoadingModels = false
                }
                return
            }

            do {
                let models = try await engine.getLocalModels()
                await MainActor.run {
                    self.localModels = models
                    self.isOllamaRunning = true
                    self.modelLoadError = models.isEmpty ? "No local models found. Enter a model name to download one." : nil
                    self.isLoadingModels = false
                }
            } catch {
                print("❌ Failed to fetch Ollama models: \(error)")
                await MainActor.run {
                    self.localModels = []
                    self.isOllamaRunning = false
                    self.modelLoadError = "Can't reach Ollama. Start the app and refresh."
                    self.isLoadingModels = false
                }
            }
        }
    }
}

private struct OllamaModelSelector: View {
    @Binding var selectedModel: String

    let localModels: [String]
    let isLoadingModels: Bool
    let isOllamaRunning: Bool?
    let modelLoadError: String?
    let pullStatus: String?
    let isPulling: Bool
    let onRefresh: () -> Void
    let onDownload: () -> Void
    let onModelChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let modelLoadError {
                unavailableMessage(modelLoadError)
            }

            HStack(spacing: 10) {
                modelPicker
                modelTextField
                downloadButton
            }

            if let pullStatus {
                Text(pullStatus)
                    .font(SW.compactFont)
                    .foregroundStyle(pullStatusColor)
            }
        }
        .onChange(of: selectedModel) { _, _ in
            onModelChange()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Ollama Model")
                .font(SW.labelFont)
                .foregroundStyle(SW.secondaryText)

            SWStatusBadge(title: ollamaStatusTitle, icon: ollamaStatusIcon, color: ollamaStatusColor)

            if isLoadingModels {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.swPlainInteractive)
            .disabled(isLoadingModels)
            .help("Refresh model list from Ollama")
        }
    }

    private func unavailableMessage(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(SW.warning)
            Text(message)
                .font(SW.compactFont)
                .foregroundStyle(SW.secondaryText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(SW.warning.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
    }

    private var modelPicker: some View {
        Picker("", selection: $selectedModel) {
            if !selectedModel.isEmpty, !localModels.contains(selectedModel) {
                Text("Current: \(selectedModel)")
                    .tag(selectedModel)
            }

            if localModels.isEmpty {
                Text("No local models").tag("")
            } else {
                Text("Select a model").tag("")
                ForEach(localModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
        }
        .pickerStyle(.menu)
        .frame(width: 250)
        .disabled(isLoadingModels || isOllamaRunning != true || localModels.isEmpty)
    }

    private var modelTextField: some View {
        TextField("Model name, e.g. qwen2.5:3b", text: $selectedModel)
            .textFieldStyle(.roundedBorder)
            .disabled(isOllamaRunning != true || isPulling)
    }

    private var downloadButton: some View {
        Button(action: onDownload) {
            HStack(spacing: 6) {
                if isPulling {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(isPulling ? "Pulling" : "Download")
            }
        }
        .disabled(!canDownloadLocalModel)
    }

    private var trimmedSelectedModel: String {
        selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canDownloadLocalModel: Bool {
        isOllamaRunning == true &&
        !isPulling &&
        !trimmedSelectedModel.isEmpty &&
        !localModels.contains(trimmedSelectedModel)
    }

    private var ollamaStatusTitle: String {
        if isLoadingModels { return "Checking" }
        switch isOllamaRunning {
        case .some(true): return "Running"
        case .some(false): return "Offline"
        case .none: return "Unknown"
        }
    }

    private var ollamaStatusIcon: String {
        if isLoadingModels { return "arrow.triangle.2.circlepath" }
        return isOllamaRunning == true ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private var ollamaStatusColor: Color {
        if isLoadingModels { return SW.secondaryText }
        return isOllamaRunning == true ? SW.success : SW.danger
    }

    private var pullStatusColor: Color {
        guard let pullStatus else { return SW.secondaryText }
        return pullStatus.hasPrefix("Failed") ? SW.danger : SW.accent
    }
}
