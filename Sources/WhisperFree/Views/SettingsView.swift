import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var modelManager: ModelManager
    @ObservedObject var recorder: AudioRecorder
    @ObservedObject private var updater = GitHubUpdater.shared
    @ObservedObject private var dependencyInstaller = DependencyInstaller.shared
    @ObservedObject private var launchAtLogin = LaunchAtLoginManager.shared
    @State private var selectedTab: String? = "app"

    // Custom Mode State
    @State private var editingModeID: String?
    @State private var newModeName = ""
    @State private var newModeDescription = ""
    @State private var newModeExampleInput = ""
    @State private var newModeExampleOutput = ""
    @State private var newModePrompt = ""
    @State private var newModeIcon = "sparkles"
    @State private var isGeneratingExample = false
    @State private var modeEditorMessage: String?

    // API Testing State
    @State private var apiValidationState: OpenAIAPIKeyValidationState = .idle
    @State private var isRunningNetworkDiagnostics = false
    @State private var networkDiagnosticLines: [String] = []
    @State private var showProfanityDictionaryImporter = false
    @State private var isProfanityDictionaryDropTarget = false
    @State private var profanityDictionaryMessage: String?
    @State private var showProfanityDictionaries = false
    @State private var showGigaAMManualCommand = false
    @State private var showRecentActivityDetails = false

    private var appVersionText: String {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String

        switch (shortVersion, buildVersion) {
        case let (short?, build?) where !short.isEmpty && !build.isEmpty && short != build:
            return L.tr("Version \(short) (\(build))", "Версия \(short) (\(build))")
        case let (short?, _) where !short.isEmpty:
            return L.tr("Version \(short)", "Версия \(short)")
        case let (_, build?) where !build.isEmpty:
            return L.tr("Version \(build)", "Версия \(build)")
        default:
            return L.tr("Version Unknown", "Версия неизвестна")
        }
    }

    private var updateVersionText: String {
        guard let latest = updater.latestVersion, !latest.isEmpty else {
            return appVersionText
        }

        return L.tr(
            "Installed \(updater.currentVersion) / Latest \(latest)",
            "Установлена \(updater.currentVersion) / Последняя \(latest)"
        )
    }

    private var isEditingCustomMode: Bool {
        editingModeID != nil
    }

    private var normalizedModeName: String {
        newModeName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedModeDescription: String {
        newModeDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedModeExampleInput: String {
        newModeExampleInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedModeExampleOutput: String {
        newModeExampleOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedModePrompt: String {
        newModePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var duplicateModeExists: Bool {
        appState.settings.allModes.contains {
            $0.name.caseInsensitiveCompare(normalizedModeName) == .orderedSame && $0.id != editingModeID
        }
    }

    private var canSaveMode: Bool {
        !normalizedModeName.isEmpty && !normalizedModePrompt.isEmpty && !duplicateModeExists
    }

    private var apiValidationText: String? {
        switch apiValidationState {
        case .idle:
            return appState.settings.hasOpenAIAPIKey
                ? L.tr("Key not checked yet.", "Ключ ещё не проверен.")
                : nil
        case .checking:
            return L.tr("Checking key…", "Проверяю ключ…")
        case .valid:
            return L.tr("Key is valid.", "Ключ валиден.")
        case .invalid:
            return L.tr("Key is invalid.", "Ключ невалиден.")
        case .networkError(let message):
            return L.tr("Could not reach OpenAI. \(message)", "Не удалось связаться с OpenAI. \(message)")
        case .failed(let statusCode):
            return L.tr("Validation failed (HTTP \(statusCode)).", "Проверка не удалась (HTTP \(statusCode)).")
        }
    }

    private var apiValidationColor: Color {
        switch apiValidationState {
        case .valid:
            return Color.accentColor
        case .invalid, .networkError, .failed:
            return .orange
        case .idle, .checking:
            return .secondary
        }
    }

    private var networkDiagnosticText: String? {
        guard !networkDiagnosticLines.isEmpty else { return nil }
        return networkDiagnosticLines.joined(separator: "\n")
    }

    private var isCheckingOpenAI: Bool {
        isRunningNetworkDiagnostics || apiValidationState == .checking
    }

    private var recordingHotkeyText: String {
        appState.settings.hotkeyConfig.displayString
    }

    var body: some View {
        ZStack {
            // Unified glass background for the whole window
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                .ignoresSafeArea()

            HStack(spacing: 0) {
                // Custom Sidebar
                VStack(spacing: 0) {
                    List(selection: $selectedTab) {
                        Section {
                            Label(L.tr("App", "Приложение"), systemImage: "apps.iphone")
                                .tag("app")
                            Label(L.tr("Capture & Automation", "Запись и автоматизация"), systemImage: "mic.fill")
                                .tag("capture")
                            Label(L.tr("Engine & API", "Движок и API"), systemImage: "cpu.fill")
                                .tag("engine")
                            Label(L.tr("Integrations", "Интеграции"), systemImage: "link")
                                .tag("integrations")
                            Label(L.tr("AI Modes", "AI-режимы"), systemImage: "sparkles")
                                .tag("modes")
                            if AppState.liveTranslatorFeatureAvailable {
                                Label(L.tr("Live Translator", "Live Translator"), systemImage: "text.bubble.fill")
                                    .tag("liveTranslator")
                            }
                            Label(L.tr("Usage & About", "Использование и О программе"), systemImage: "info.circle.fill")
                                .tag("info")
                        }
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .frame(width: 230)

                    Spacer()
                }
                .padding(.top, 8)

                Divider()
                    .opacity(0.1) // Subtler divider

                // Detail Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let tab = selectedTab {
                            if !appState.isHotkeyTrusted && tab != "info" {
                                permissionBanner
                            }

                            switch tab {
                            case "app": appSection
                            case "capture":
                                captureSection
                                    .onAppear { appState.recorder.startMonitoring() }
                                    .onDisappear { appState.recorder.stopMonitoring() }
                            case "engine": engineSection
                            case "integrations": integrationsSection
                            case "modes": modesSection
                            case "liveTranslator":
                                if AppState.liveTranslatorFeatureAvailable {
                                    LiveTranslatorSettingsView(appState: appState)
                                } else {
                                    EmptyView()
                                }
                            case "info": infoSection
                            default: EmptyView()
                            }
                        }
                    }
                    .padding(24)
                }
                .scrollContentBackground(.hidden)
                .background(SW.contentBackground.opacity(0.12))
            }
        }
        .onAppear {
            dependencyInstaller.refreshHomebrewStatus()
            launchAtLogin.refresh()
            modelManager.refreshDownloadedModels()
        }
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(columnTitle)
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .fileImporter(
            isPresented: $showProfanityDictionaryImporter,
            allowedContentTypes: [.plainText, .utf8PlainText, .commaSeparatedText, .json],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importProfanityDictionaries(from: urls)
            case .failure(let error):
                profanityDictionaryMessage = error.localizedDescription
            }
        }
    }

    private var columnTitle: String {
        switch selectedTab {
        case "app": return L.tr("App Preferences", "Настройки приложения")
        case "capture": return L.tr("Capture & Automation", "Запись и автоматизация")
        case "engine": return L.tr("Engine & API", "Движок и API")
        case "integrations": return L.tr("Integrations", "Интеграции")
        case "modes": return L.tr("AI Modes", "AI-режимы")
        case "liveTranslator": return L.tr("Live Translator", "Live Translator")
        case "info": return L.tr("Usage & About", "Использование и О программе")
        default: return L.tr("Settings", "Настройки")
        }
    }

    private var permissionBanner: some View {
        HStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(SW.warning)

            VStack(alignment: .leading, spacing: 4) {
                Text(L.tr("Accessibility required", "Нужен Accessibility"))
                    .font(SW.titleFont)
                Text(L.tr("Enable it for global hotkeys.", "Включите доступ для глобальных хоткеев."))
                    .font(SW.compactFont)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(L.tr("Grant Access…", "Выдать доступ…")) {
                appState.requestAccessibilityPermission()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(14)
        .background(SW.warning.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: SW.radiusMedium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SW.radiusMedium, style: .continuous).strokeBorder(SW.warning.opacity(0.22), lineWidth: 1))
    }

    // MARK: - Sections

    @ViewBuilder
    private var appSection: some View {
        VStack(alignment: .leading, spacing: 16) {

            VStack(spacing: 0) {
                HStack {
                    Text(L.tr("Preferred Language", "Предпочитаемый язык"))
                    Spacer()
                    Picker("", selection: $appState.settings.language) {
                        ForEach(AppSettings.supportedLanguages, id: \.code) { lang in
                            Text(L.languageName(code: lang.code, fallback: lang.name)).tag(lang.code)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                .padding()
                .onChange(of: appState.settings.language) { _, _ in
                    appState.saveSettings()
                }

                Divider().padding(.horizontal)

                Toggle(L.tr("Monochrome menu bar icon", "Монохромная иконка в menu bar"), isOn: $appState.settings.useMonochromeMenuIcon)
                    .padding()
                    .onChange(of: appState.settings.useMonochromeMenuIcon) { _, _ in
                        appState.saveSettings()
                    }

                Divider().padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(
                        L.tr("Launch at login", "Запускать при входе в систему"),
                        isOn: Binding(
                            get: { launchAtLogin.isEnabled },
                            set: { launchAtLogin.setEnabled($0) }
                        )
                    )

                    if let message = launchAtLogin.message {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if launchAtLogin.requiresApproval {
                                Button(L.tr("Open Settings", "Открыть настройки")) {
                                    launchAtLogin.openLoginItemsSettings()
                                }
                                .buttonStyle(.link)
                                .font(.caption)
                            }
                        }
                        .padding(.leading, 22)
                    }
                }
                .padding()
            }
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }

        VStack(alignment: .leading, spacing: 16) {
            Text(L.tr("Software Updates", "Обновления"))
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                Toggle(L.tr("Automatically check for updates", "Автоматически проверять обновления"), isOn: $appState.settings.automaticallyChecksForUpdates)
                    .padding()

                Divider().padding(.horizontal)

                Toggle(L.tr("Automatically download updates", "Автоматически загружать обновления"), isOn: $appState.settings.automaticallyDownloadsUpdates)
                    .disabled(!appState.settings.automaticallyChecksForUpdates)
                    .padding()

                if updater.updateAvailable || updater.isDownloading || updater.error != nil {
                    Divider().padding(.horizontal)

                    VStack(alignment: .leading, spacing: 12) {
                        if let error = updater.error {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .onAppear {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                                        updater.error = nil
                                    }
                                }
                        }

                        if updater.isDownloading {
                            VStack(alignment: .leading, spacing: 4) {
                                ProgressView(value: updater.downloadProgress)
                                    .progressViewStyle(.linear)
                                Text(L.tr("Downloading update... \(Int(updater.downloadProgress * 100))%", "Загрузка обновления... \(Int(updater.downloadProgress * 100))%"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        } else if updater.updateAvailable {
                            HStack {
                                Text(L.tr("Version v\(updater.latestVersion ?? "") is available.", "Доступна версия v\(updater.latestVersion ?? "")."))
                                    .font(.subheadline)
                                Spacer()
                                Button(L.tr("Download & Install", "Скачать и установить")) {
                                    updater.startDownload()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding()
                } else {
                    Divider().padding(.horizontal)
                    HStack {
                        Spacer()
                        Button(updater.isChecking ? L.tr("Checking...", "Проверка...") : L.tr("Check for Updates Now...", "Проверить обновления сейчас...")) {
                            updater.checkForUpdates(manual: true)
                        }
                        .disabled(updater.isChecking)
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                    .padding()
                }
            }
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    private var captureSection: some View {
        VStack(alignment: .leading, spacing: 16) {

            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(RecordingMode.allCases, id: \.self) { mode in
                            recordingModeCard(mode)
                        }
                    }
                    .padding(.horizontal, 1)
                }

                Text(appState.settings.recordingMode.localizedDescription(hotkey: recordingHotkeyText))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding()
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }

        VStack(alignment: .leading, spacing: 16) {
            Text(L.tr("Global Recording Shortcut", "Глобальная горячая клавиша"))
                .font(.headline)
                .foregroundStyle(.secondary)

            HotkeyRecorderView(config: $appState.settings.hotkeyConfig)
                .padding()
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }

        VStack(alignment: .leading, spacing: 16) {
            Text(L.tr("Automation & Interface", "Автоматизация и интерфейс"))
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                Toggle(L.tr("Auto-type into active app", "Автопечать в активное приложение"), isOn: $appState.settings.autoTypeResult)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()

                Divider().padding(.horizontal)

                Toggle(L.tr("Auto-Enter automatically", "Автоматически нажимать Enter"), isOn: $appState.settings.experimentalAutoEnter)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()

                Divider().padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    Picker(L.tr("Insertion Method", "Метод вставки"), selection: $appState.settings.insertionMethod) {
                        ForEach(InsertionMethod.allCases, id: \.self) { method in
                            Text(method.localizedTitle).tag(method)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()

                    Text(appState.settings.insertionMethod.localizedDescription)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding()

                Divider().padding(.horizontal)

                Toggle(L.tr("Show floating recording pill", "Показывать плавающий индикатор записи"), isOn: $appState.settings.showOverlay)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }

            VStack(alignment: .leading, spacing: 12) {
                Text(L.tr("Output Text", "Текст результата"))
                    .font(.headline)
                    .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                Toggle(L.tr("Profanity filter", "Мат-фильтр"), isOn: $appState.settings.enableProfanityFilter)
                    .onChange(of: appState.settings.enableProfanityFilter) { _, _ in
                        appState.saveSettings()
                    }

                ClickableDisclosure(isExpanded: $showProfanityDictionaries) {
                    profanityDictionaryManager
                } label: {
                    Text(L.tr("Custom dictionaries", "Пользовательские словари"))
                }
                .font(.subheadline)
            }
            .padding()
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var profanityDictionaryManager: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L.tr("\(appState.settings.customProfanityDictionaries.count) files", "\(appState.settings.customProfanityDictionaries.count) файлов"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L.tr("Add Files", "Добавить файлы")) {
                    showProfanityDictionaryImporter = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            profanityDictionaryDropZone

            if let profanityDictionaryMessage {
                Text(profanityDictionaryMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !appState.settings.customProfanityDictionaries.isEmpty {
                VStack(spacing: 0) {
                    ForEach(appState.settings.customProfanityDictionaries) { dictionary in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dictionary.fileName)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(L.tr("\(dictionary.entryCount) entries", "\(dictionary.entryCount) слов"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button(role: .destructive) {
                                removeProfanityDictionary(dictionary)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 10)

                        if dictionary.id != appState.settings.customProfanityDictionaries.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(.top, 8)
    }

    private func recordingModeCard(_ mode: RecordingMode) -> some View {
        let selected = appState.settings.recordingMode == mode

        return Button {
            appState.settings.recordingMode = mode
            appState.saveSettings()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: mode.icon)
                        .font(.system(size: 13, weight: .semibold))
                    Text(mode.localizedTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                Text(mode.localizedDescription(hotkey: recordingHotkeyText))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 164, height: 74, alignment: .topLeading)
            .padding(10)
            .background(selected ? SW.accent.opacity(0.10) : Color.primary.opacity(0.035))
            .foregroundStyle(selected ? SW.accent : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? SW.accent.opacity(0.35) : Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var engineSelector: some View {
        HStack(spacing: 0) {
            ForEach(TranscriptionEngineType.allCases, id: \.self) { type in
                Button {
                    appState.settings.engineType = type
                    if type == .qwenASR {
                        appState.settings.qwenASRModel = QwenASRModel.recommended
                    }
                    appState.saveSettings()
                } label: {
                    Text(type.localizedTitle)
                        .font(.system(size: 12, weight: appState.settings.engineType == type ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .padding(.horizontal, 6)
                        .foregroundStyle(appState.settings.engineType == type ? .primary : .secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(appState.settings.engineType == type ? Color(nsColor: .controlBackgroundColor).opacity(0.92) : Color.clear)
                        )
                }
                .buttonStyle(.plain)

                if type != TranscriptionEngineType.allCases.last {
                    Divider()
                        .frame(height: 18)
                }
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    @ViewBuilder
    private var engineSection: some View {
        VStack(alignment: .leading, spacing: 16) {

            VStack(alignment: .leading, spacing: 16) {
                engineSelector
                    .padding(.horizontal)

                Divider().padding(.horizontal)

                VStack(alignment: .leading, spacing: 10) {
                    if appState.settings.engineType == .cloud {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker(L.tr("Cloud model", "Облачная модель"), selection: $appState.settings.cloudTranscriptionModel) {
                                ForEach(CloudTranscriptionModel.allCases, id: \.self) { model in
                                    Text(model.localizedTitle).tag(model)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .onChange(of: appState.settings.cloudTranscriptionModel) { _, _ in
                                appState.saveSettings()
                            }

                            Text(appState.settings.cloudTranscriptionModel.localizedDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                    }

                    if shouldShowOpenAIKeyCard {
                        OpenAIAPIKeySettingsCard(
                            apiKey: $appState.settings.apiKey,
                            validationState: apiValidationState,
                            isValidating: isCheckingOpenAI,
                            statusText: apiValidationText,
                            statusColor: apiValidationColor,
                            diagnosticText: networkDiagnosticText,
                            onValidate: checkOpenAI,
                            onChanged: handleAPIKeyChanged
                        )
                        .padding(.horizontal)
                    }

                    if appState.settings.engineType == .local {
                        VStack(spacing: 0) {
                            if !dependencyInstaller.isHomebrewInstalled {
                                homebrewStatusRow
                                Divider().padding(.horizontal)
                            }

                            if !dependencyInstaller.isWhisperCppInstalled {
                                whisperCppStatusRow
                                Divider().padding(.horizontal)
                            }

                            if dependencyInstaller.isHomebrewInstalled && dependencyInstaller.isWhisperCppInstalled {
                                localModelRows
                            }
                        }
                    }

                    if appState.settings.engineType == .qwenASR {
                        qwenASRSettingsCard
                            .padding(.horizontal)
                    }

                    if appState.settings.engineType == .gigaAM {
                        gigaAMExperimentCard
                            .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical, 12)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }

        VStack(alignment: .leading, spacing: 16) {
            Text(L.tr("API Refinement", "AI-обработка"))
                .font(.headline)
                .foregroundStyle(.secondary)

            AIConfigView(settings: $appState.settings, onSave: { appState.saveSettings() })
                .padding()
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var shouldShowOpenAIKeyCard: Bool {
        appState.settings.engineType == .cloud ||
        appState.settings.enablePostProcessing ||
        appState.settings.enableSpeakerDiarization ||
        appState.settings.hasOpenAIAPIKey
    }

    private var integrationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L.tr("Google", "Google"))
                .font(.headline)
                .foregroundStyle(.secondary)

            GoogleAccountsSettingsCard()
        }
    }

    private var localModelRows: some View {
        ForEach(LocalModelSize.allCases, id: \.self) { size in
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(size.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                    Text(size.sizeDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if size.forcesEnglishDecoding {
                        Text(L.tr("English-first model", "Модель в первую очередь для английского"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()

                if modelManager.isModelDownloaded(size) {
                    if appState.settings.localModelSize == size {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .font(.title3)
                    } else {
                        Button(L.tr("Use", "Использовать")) {
                            appState.settings.localModelSize = size
                            appState.saveSettings()
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(role: .destructive) {
                        modelManager.deleteModel(size)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 8)
                } else if let state = modelManager.activeDownloads[size.rawValue] {
                    if state.error != nil {
                        Button(L.tr("Retry", "Повторить")) { modelManager.downloadModel(size) }
                            .buttonStyle(.plain)
                            .font(.caption2)
                            .foregroundStyle(SW.accent)
                    } else {
                        VStack(alignment: .trailing, spacing: 4) {
                            ProgressView(value: state.progress).frame(width: 80)
                            HStack(spacing: 4) {
                                if state.speed > 0 {
                                    Text(formatSpeed(state.speed))
                                }
                                if let remaining = state.timeRemaining {
                                    Text("• \(formatDuration(remaining))")
                                }
                            }
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Button(L.tr("Download", "Скачать")) { modelManager.downloadModel(size) }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            if size != LocalModelSize.allCases.last { Divider().padding(.horizontal) }
        }
    }

    private var qwenASRSettingsCard: some View {
        let runtimeReady = dependencyInstaller.isQwenASRRuntimeInstalled
        let selectedModel = appState.settings.qwenASRModel
        let selectedModelReady = modelManager.isQwenModelDownloaded(selectedModel)
        let selectedModelPartial = modelManager.hasPartialQwenModelDownload(selectedModel)
        let selectedModelDownloading = dependencyInstaller.downloadingQwenASRModel == selectedModel
        let qwenReady = runtimeReady && selectedModelReady

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: TranscriptionEngineType.qwenASR.icon)
                    .foregroundStyle(SW.accent)
                Text(L.tr("Local Qwen3-ASR", "Локальный Qwen3-ASR"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(L.tr("Local only", "Только локально"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            Text(L.tr("Private on-device transcription. Models download once and stay on this Mac.", "Приватная транскрибация на устройстве. Модели скачиваются один раз и остаются на этом Mac."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Image(systemName: qwenReady ? "checkmark.circle.fill" : (selectedModelPartial ? "exclamationmark.circle.fill" : "xmark.circle.fill"))
                    .foregroundStyle(qwenReady ? Color.accentColor : .orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedModelDownloading ? L.tr("Downloading model", "Скачивание модели") : qwenStatusTitle(runtimeReady: runtimeReady, modelReady: selectedModelReady, partial: selectedModelPartial))
                        .font(.system(size: 13, weight: .semibold))

                    if selectedModelDownloading {
                        ProgressView(value: Double(dependencyInstaller.qwenASRModelDownloadProgress))
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 240)
                    } else if dependencyInstaller.isInstallingQwenASR {
                        Text(L.tr("Preparing local transcription...", "Подготавливаю локальную транскрибацию..."))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else if !QwenASRTranscriber.isAppleSilicon {
                        Text(L.tr("Apple Silicon is required.", "Нужен Apple Silicon."))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else if !dependencyInstaller.qwenASRStatus.isEmpty && !runtimeReady {
                        Text(dependencyInstaller.qwenASRStatus)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    } else {
                        Text(qwenStatusSubtitle(runtimeReady: runtimeReady, modelReady: selectedModelReady, partial: selectedModelPartial, model: selectedModel))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if dependencyInstaller.isInstallingQwenASR {
                    ProgressView()
                        .controlSize(.small)
                } else if selectedModelDownloading {
                    ProgressView()
                        .controlSize(.small)
                } else if runtimeReady && !selectedModelReady {
                    Button(selectedModelPartial ? L.tr("Retry", "Повторить") : L.tr("Download", "Скачать")) {
                        if selectedModelPartial {
                            modelManager.deleteQwenModel(selectedModel)
                        }
                        dependencyInstaller.downloadQwenASRModel(selectedModel, modelManager: modelManager)
                    }
                    .buttonStyle(.borderedProminent)
                } else if runtimeReady {
                    Button(L.tr("Refresh", "Обновить")) {
                        dependencyInstaller.refreshQwenASRStatus()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(L.tr("Install", "Установить")) {
                        dependencyInstaller.installQwenASRRuntime()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!QwenASRTranscriber.isAppleSilicon)
                }
            }

            Divider()

            ForEach(QwenASRModel.allCases, id: \.self) { model in
                let modelReady = modelManager.isQwenModelDownloaded(model)
                let modelPartial = modelManager.hasPartialQwenModelDownload(model)
                let modelDownloading = dependencyInstaller.downloadingQwenASRModel == model

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.localizedTitle)
                            .font(.system(size: 13, weight: .semibold))
                        Text(model.sizeDescription)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        if let size = modelManager.qwenModelFileSize(model) {
                            Text(modelPartial ? L.tr("Partial: \(size)", "Частично: \(size)") : L.tr("Cached: \(size)", "В кэше: \(size)"))
                                .font(.system(size: 10))
                                .foregroundStyle(modelPartial ? .orange : .secondary)
                        } else if modelDownloading {
                            Text(L.tr("Downloading...", "Скачивается..."))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if modelDownloading {
                        ProgressView(value: Double(dependencyInstaller.qwenASRModelDownloadProgress))
                            .progressViewStyle(.linear)
                            .frame(width: 82)
                    } else if appState.settings.qwenASRModel == model && modelReady {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .font(.title3)
                    } else if modelReady {
                        Button(L.tr("Use", "Использовать")) {
                            appState.settings.qwenASRModel = model
                            appState.saveSettings()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button(modelPartial ? L.tr("Retry", "Повторить") : L.tr("Download", "Скачать")) {
                            if modelPartial {
                                modelManager.deleteQwenModel(model)
                            }
                            dependencyInstaller.downloadQwenASRModel(model, modelManager: modelManager) {
                                self.appState.settings.qwenASRModel = model
                                self.appState.saveSettings()
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(dependencyInstaller.downloadingQwenASRModel != nil)
                    }

                    if modelReady || modelPartial {
                        Button(role: .destructive) {
                            modelManager.deleteQwenModel(model)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func qwenStatusTitle(runtimeReady: Bool, modelReady: Bool, partial: Bool) -> String {
        if runtimeReady && modelReady {
            return L.tr("Qwen3-ASR ready", "Qwen3-ASR готов")
        }
        if partial {
            return L.tr("Model download incomplete", "Модель скачана не полностью")
        }
        if runtimeReady {
            return L.tr("Model not installed", "Модель не установлена")
        }
        return L.tr("Qwen3-ASR runtime not ready", "Runtime Qwen3-ASR не готов")
    }

    private func qwenStatusSubtitle(runtimeReady: Bool, modelReady: Bool, partial: Bool, model: QwenASRModel) -> String {
        if runtimeReady && modelReady {
            return L.tr("\(model.localizedTitle) is cached locally.", "\(model.localizedTitle) сохранена локально.")
        }
        if partial {
            return L.tr("Delete the partial download or retry transcription.", "Удалите partial-загрузку или повторите транскрибацию.")
        }
        if runtimeReady {
            return L.tr("\(model.localizedTitle) will download on first use.", "\(model.localizedTitle) скачается при первом запуске.")
        }
        return L.tr("Install the local runtime first.", "Сначала установите локальный runtime.")
    }

    private var whisperCppStatusRow: some View {
        let isInstalled = dependencyInstaller.isWhisperCppInstalled
        let hasHomebrew = dependencyInstaller.isHomebrewInstalled

        return HStack(spacing: 10) {
            Image(systemName: isInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isInstalled ? Color.accentColor : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(
                    isInstalled
                        ? L.tr("whisper-cpp detected", "whisper-cpp найден")
                        : L.tr("whisper-cpp not found", "whisper-cpp не найден")
                )
                .font(.system(size: 13, weight: .semibold))

                if dependencyInstaller.isInstallingWhisperCpp {
                    Text(L.tr("Installing with Homebrew…", "Устанавливаю через Homebrew…"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else if !hasHomebrew {
                    Text(L.tr("Homebrew required", "Сначала нужен Homebrew"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else if !dependencyInstaller.whisperCppStatus.isEmpty {
                    Text(dependencyInstaller.whisperCppStatus)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if dependencyInstaller.isInstallingWhisperCpp {
                ProgressView()
                    .controlSize(.small)
            } else if !isInstalled && hasHomebrew {
                Button(L.tr("Install", "Установить")) {
                    dependencyInstaller.installWhisperCpp()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var gigaAMExperimentCard: some View {
        let isInstalled = dependencyInstaller.isGigaAMEnvironmentInstalled
        let hasPython = GigaAMTranscriber.findBasePythonBinary() != nil

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: TranscriptionEngineType.gigaAM.icon)
                    .foregroundStyle(SW.accent)
                Text(L.tr("Russian ASR experiment", "Эксперимент для русского ASR"))
                    .font(.system(size: 13, weight: .semibold))
            }

            Text(L.tr("Best for Russian comparison runs. First launch downloads the model cache.", "Для сравнения качества на русском. Первый запуск скачает кэш модели."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Image(systemName: isInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(isInstalled ? Color.accentColor : .orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isInstalled ? L.tr("GigaAM runtime detected", "GigaAM runtime найден") : L.tr("GigaAM runtime not found", "GigaAM runtime не найден"))
                        .font(.system(size: 13, weight: .semibold))

                    if dependencyInstaller.isInstallingGigaAM {
                        Text(L.tr("Installing Python runtime and model packages...", "Устанавливаю Python runtime и пакеты модели..."))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else if !hasPython {
                        Text(L.tr("Python 3.10-3.13 required", "Нужен Python 3.10-3.13"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else if !dependencyInstaller.gigaAMStatus.isEmpty {
                        Text(dependencyInstaller.gigaAMStatus)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    } else {
                        Text(L.tr("Installs into an isolated app venv.", "Ставит зависимости в отдельный venv приложения."))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if dependencyInstaller.isInstallingGigaAM {
                    ProgressView()
                        .controlSize(.small)
                } else if isInstalled {
                    Button(L.tr("Refresh", "Обновить")) {
                        dependencyInstaller.refreshGigaAMStatus()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(L.tr("Install", "Установить")) {
                        dependencyInstaller.installGigaAMDependencies()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasPython)
                }
            }

            ClickableDisclosure(isExpanded: $showGigaAMManualCommand) {
                Text(GigaAMTranscriber.setupCommand)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } label: {
                Text(L.tr("Manual command", "Команда вручную"))
            }
            .font(.system(size: 11))
        }
        .padding(12)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var homebrewStatusRow: some View {
        let isInstalled = dependencyInstaller.isHomebrewInstalled

        return HStack(spacing: 10) {
            Image(systemName: isInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isInstalled ? Color.accentColor : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(
                    isInstalled
                        ? L.tr("Homebrew detected", "Homebrew найден")
                        : L.tr("Homebrew not found", "Homebrew не найден")
                )
                .font(.system(size: 13, weight: .semibold))

                if !dependencyInstaller.homebrewStatus.isEmpty {
                    Text(dependencyInstaller.homebrewStatus)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if isInstalled {
                EmptyView()
            } else if dependencyInstaller.isInstallingHomebrew {
                Button(L.tr("Refresh", "Обновить")) {
                    dependencyInstaller.refreshHomebrewStatus()
                }
                .buttonStyle(.bordered)
            } else {
                Button(L.tr("Install", "Установить")) {
                    dependencyInstaller.installHomebrew()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var modesSection: some View {
        Group {
            ForEach(appState.settings.allModes, id: \.id) { mode in
                let isDictation = mode.name == TranscriptionMode.dictation.name
                let isDisabledByEngine = isDictation && appState.settings.engineType == .local
                let isLocked = !appState.settings.isModeEnabled(mode)

                if !isDisabledByEngine {
                    Section {
                        ModeCard(
                            mode: mode,
                            isSelected: appState.settings.selectedModeName == mode.name,
                            isEnabled: !isLocked,
                            onSelect: {
                                if !isLocked {
                                    appState.settings.selectedModeName = mode.name
                                    appState.saveSettings()
                                }
                            },
                            onEdit: mode.isBuiltIn ? nil : {
                                beginEditing(mode)
                            },
                            onDelete: mode.isBuiltIn ? nil : {
                                appState.settings.customModes.removeAll { $0.id == mode.id }
                                if appState.settings.selectedModeName == mode.name {
                                    appState.settings.selectedModeName = TranscriptionMode.dictation.name
                                }
                                if editingModeID == mode.id {
                                    resetModeEditor()
                                }
                                appState.saveSettings()
                            }
                        )
                    }
                }
            }

            CustomModeEditorCard(
                isEditing: isEditingCustomMode,
                modeName: $newModeName,
                modeDescription: $newModeDescription,
                exampleInput: $newModeExampleInput,
                exampleOutput: $newModeExampleOutput,
                prompt: $newModePrompt,
                icon: $newModeIcon,
                isGeneratingExample: isGeneratingExample,
                editorMessage: modeEditorMessage,
                canSave: canSaveMode,
                hasDuplicateName: duplicateModeExists,
                onGenerateExample: runModeExample,
                onCancel: resetModeEditor,
                onSave: saveCustomMode
            )
        }
    }

    @ViewBuilder
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 16) {

            let logs = appState.settings.usageLogs
            let totalTokens = logs.reduce(0) { $0 + $1.totalTokens }
            let totalCost = logs.reduce(0.0) { $0 + $1.estimatedCost }

            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 40) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.tr("Total Tokens", "Всего токенов")).font(.caption).foregroundStyle(.secondary)
                        Text("\(totalTokens)").font(.title2).bold().foregroundStyle(SW.accent)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.tr("Est. Cost", "Оценка стоимости")).font(.caption).foregroundStyle(.secondary)
                        Text("$\(String(format: "%.4f", totalCost))").font(.title2).bold().foregroundStyle(Color.accentColor)
                    }

                    Spacer()

                    Button(L.tr("Reset Logs", "Сбросить логи")) {
                        appState.settings.usageLogs.removeAll()
                        appState.saveSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if !logs.isEmpty {
                    Divider()

                    ClickableDisclosure(isExpanded: $showRecentActivityDetails) {
                        VStack(spacing: 8) {
                            ForEach(logs.reversed().prefix(20)) { log in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(log.modeName).font(.system(size: 11, weight: .bold))
                                        Text(log.date.formatted(date: .abbreviated, time: .shortened))
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("\(log.totalTokens) tokens").font(.system(size: 10, design: .monospaced))
                                        Text(log.engine).font(.system(size: 8)).foregroundStyle(.secondary).italic()
                                    }
                                }
                                if log.id != logs.reversed().prefix(20).last?.id {
                                    Divider().opacity(0.5)
                                }
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text(L.tr("Recent Activity Details", "Детали недавней активности"))
                            .font(.caption)
                            .foregroundStyle(SW.accent)
                    }
                }
            }
            .padding(20)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }

        VStack(alignment: .leading, spacing: 16) {
            Text(L.tr("About Whisper Killer", "О Whisper Killer"))
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [SW.accent, SW.accentBlue], startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.1))
                    Image(systemName: "microphone.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: [SW.accent, SW.accentBlue], startPoint: .top, endPoint: .bottom))
                }
                .frame(width: 80, height: 80)

                VStack(spacing: 8) {
                    Text("Whisper Killer").font(.system(size: 28, weight: .bold))
                    Text(updateVersionText).font(.subheadline).foregroundStyle(.secondary)
                }

                Text(L.tr("Hyper-fast voice to text for macOS.", "Очень быстрая голосовая транскрибация для macOS."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 24) {
                    Link("GitHub", destination: URL(string: "https://github.com/iddictive/Whisper-Killer")!)
                    Link("iddictive", destination: URL(string: "https://github.com/iddictive")!)
                }
                .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(32)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }

    private func handleAPIKeyChanged() {
        apiValidationState = .idle
        modeEditorMessage = nil
        networkDiagnosticLines.removeAll()
        Storage.shared.saveSettings(appState.settings)
    }

    private func checkOpenAI() {
        isRunningNetworkDiagnostics = true
        apiValidationState = .idle
        networkDiagnosticLines = []
        apiValidationState = .checking
        let currentKey = appState.settings.apiKey

        Task {
            let report = await OpenAIAPIKeyValidator.diagnoseNetwork()
            let result = currentKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? OpenAIAPIKeyValidationState.idle
                : await OpenAIAPIKeyValidator.validate(currentKey)
            await MainActor.run {
                isRunningNetworkDiagnostics = false
                networkDiagnosticLines = report.lines
                apiValidationState = result
            }
        }
    }

    private func beginEditing(_ mode: TranscriptionMode) {
        editingModeID = mode.id
        newModeName = mode.name
        newModeDescription = mode.description
        newModeExampleInput = mode.exampleInput
        newModeExampleOutput = mode.exampleOutput
        newModePrompt = mode.systemPrompt
        newModeIcon = mode.icon
        modeEditorMessage = nil
    }

    private func resetModeEditor() {
        editingModeID = nil
        newModeName = ""
        newModeDescription = ""
        newModeExampleInput = ""
        newModeExampleOutput = ""
        newModePrompt = ""
        newModeIcon = "sparkles"
        modeEditorMessage = nil
        isGeneratingExample = false
    }

    private func saveCustomMode() {
        guard canSaveMode else { return }

        let mode = TranscriptionMode(
            name: normalizedModeName,
            icon: newModeIcon,
            description: normalizedModeDescription.isEmpty ? TranscriptionMode.placeholderDescription : normalizedModeDescription,
            exampleInput: normalizedModeExampleInput.isEmpty ? TranscriptionMode.placeholderExampleInput : normalizedModeExampleInput,
            exampleOutput: normalizedModeExampleOutput.isEmpty ? TranscriptionMode.placeholderExampleOutput : normalizedModeExampleOutput,
            systemPrompt: normalizedModePrompt,
            isBuiltIn: false
        )

        if let editingModeID,
           let index = appState.settings.customModes.firstIndex(where: { $0.id == editingModeID }) {
            let previousName = appState.settings.customModes[index].name
            appState.settings.customModes[index] = mode
            if appState.settings.selectedModeName == previousName {
                appState.settings.selectedModeName = mode.name
            }
        } else {
            appState.settings.customModes.append(mode)
        }

        appState.saveSettings()
        resetModeEditor()
    }

    private func runModeExample() {
        let exampleInput = normalizedModeExampleInput
        let prompt = normalizedModePrompt

        guard !exampleInput.isEmpty else {
            modeEditorMessage = L.tr("Add example input first.", "Сначала добавьте пример входа.")
            return
        }

        guard !prompt.isEmpty else {
            modeEditorMessage = L.tr("Add a system prompt first.", "Сначала добавьте системный промпт.")
            return
        }

        guard appState.settings.hasOpenAIAPIKey else {
            modeEditorMessage = L.tr("Add and validate an OpenAI API key first.", "Сначала добавьте и проверьте OpenAI API key.")
            return
        }

        isGeneratingExample = true
        modeEditorMessage = nil

        let temporaryMode = TranscriptionMode(
            name: normalizedModeName.isEmpty ? TranscriptionMode.placeholderName : normalizedModeName,
            icon: newModeIcon,
            description: normalizedModeDescription.isEmpty ? TranscriptionMode.placeholderDescription : normalizedModeDescription,
            exampleInput: exampleInput,
            exampleOutput: normalizedModeExampleOutput,
            systemPrompt: prompt,
            isBuiltIn: false
        )

        Task {
            do {
                let result = try await PostProcessor(settings: appState.settings).process(text: exampleInput, mode: temporaryMode)
                await MainActor.run {
                    newModeExampleOutput = result.text
                    isGeneratingExample = false
                    modeEditorMessage = L.tr("Example output updated.", "Пример выхода обновлён.")
                }
            } catch {
                await MainActor.run {
                    isGeneratingExample = false
                    modeEditorMessage = error.localizedDescription
                }
            }
        }
    }

    private var profanityDictionaryDropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isProfanityDictionaryDropTarget ? Color.accentColor : Color.secondary.opacity(0.2),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 3])
                )
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isProfanityDictionaryDropTarget ? Color.accentColor.opacity(0.05) : Color.primary.opacity(0.02))
                )

            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 22))
                    .foregroundStyle(isProfanityDictionaryDropTarget ? Color.accentColor : .secondary)
                Text(L.tr("Drop dictionary files here", "Перетащите сюда файлы словаря"))
                    .font(.system(size: 12, weight: .medium))
                Text(L.tr("or click to choose files", "или нажмите, чтобы выбрать файлы"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 18)
        }
        .onDrop(of: [.fileURL], isTargeted: $isProfanityDictionaryDropTarget) { providers in
            handleProfanityDictionaryDrop(providers)
        }
        .onTapGesture {
            showProfanityDictionaryImporter = true
        }
    }

    private func handleProfanityDictionaryDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                DispatchQueue.main.async {
                    importProfanityDictionaries(from: [url])
                }
            }
        }
        return true
    }

    private func importProfanityDictionaries(from urls: [URL]) {
        guard !urls.isEmpty else { return }

        var importedFiles = 0
        var importedEntries = 0
        var errors: [String] = []

        for url in urls {
            do {
                let dictionary = try ProfanityFilter.importDictionary(from: url)
                appState.settings.customProfanityDictionaries.removeAll { $0.fileName == dictionary.fileName }
                appState.settings.customProfanityDictionaries.append(dictionary)
                importedFiles += 1
                importedEntries += dictionary.entryCount
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if importedFiles > 0 {
            appState.saveSettings()
        }

        if importedFiles > 0 && errors.isEmpty {
            profanityDictionaryMessage = L.tr("Imported \(importedFiles) file(s), \(importedEntries) entries.", "Импортировано файлов: \(importedFiles), слов: \(importedEntries).")
        } else if importedFiles > 0 {
            profanityDictionaryMessage = ([L.tr("Imported \(importedFiles) file(s), \(importedEntries) entries.", "Импортировано файлов: \(importedFiles), слов: \(importedEntries).")] + errors).joined(separator: "\n")
        } else {
            profanityDictionaryMessage = errors.joined(separator: "\n")
        }
    }

    private func removeProfanityDictionary(_ dictionary: CustomProfanityDictionary) {
        appState.settings.customProfanityDictionaries.removeAll { $0.id == dictionary.id }
        appState.saveSettings()
        profanityDictionaryMessage = nil
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return "\(Int(duration))s"
        } else {
            let mins = Int(duration / 60)
            let secs = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(mins)m \(secs)s"
        }
    }

} // End of SettingsView

// MARK: - Helper Views


struct AIConfigView: View {
    @Binding var settings: AppSettings
    var onSave: () -> Void

    private var shouldShowDiarizationControls: Bool {
        settings.engineType == .cloud || settings.enableSpeakerDiarization
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(L.tr("Enable AI Refinement", "Включить AI-обработку"), isOn: $settings.enablePostProcessing)
                    .onChange(of: settings.enablePostProcessing) { _, _ in
                        settings.selectedModeName = settings.validatedModeName(currentName: settings.selectedModeName)
                        onSave()
                    }
            }

            if shouldShowDiarizationControls {
                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Toggle(L.tr("Speaker Diarization (AI-powered)", "Диаризация спикеров (AI)"), isOn: $settings.enableSpeakerDiarization)
                        .disabled(!settings.canUseSpeakerDiarization)
                        .onChange(of: settings.enableSpeakerDiarization) { _, _ in
                            onSave()
                        }

                    if !settings.canUseSpeakerDiarization {
                        Text(L.tr("Use Cloud (OpenAI) and add an OpenAI API key to enable diarization.", "Для диаризации выберите Облако (OpenAI) и добавьте OpenAI API key."))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }
}

struct OpenAIAPIKeySettingsCard: View {
    @Binding var apiKey: String
    let validationState: OpenAIAPIKeyValidationState
    let isValidating: Bool
    let statusText: String?
    let statusColor: Color
    let diagnosticText: String?
    let onValidate: () -> Void
    let onChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.tr("OpenAI API Key", "OpenAI API Key"))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                SecureField("sk-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: apiKey) { _, _ in
                        onChanged()
                    }

                Button(action: onValidate) {
                    Group {
                        if isValidating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(L.tr("Check OpenAI", "Проверить OpenAI"))
                        }
                    }
                    .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isValidating)
            }

            if let statusText {
                HStack(spacing: 6) {
                    Image(systemName: validationIcon)
                    Text(statusText)
                }
                .font(.caption)
                .foregroundStyle(statusColor)
            }

            if let diagnosticText {
                Text(diagnosticText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

        }
        .padding(16)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var validationIcon: String {
        switch validationState {
        case .valid:
            return "checkmark.circle.fill"
        case .invalid, .networkError, .failed:
            return "exclamationmark.triangle.fill"
        case .idle, .checking:
            return "info.circle.fill"
        }
    }
}

struct GoogleAccountsSettingsCard: View {
    @State private var accounts: [GoogleOAuthAccount] = GoogleDriveMeetImporter.shared.accounts
    @State private var selectedAccountID: String? = GoogleDriveMeetImporter.shared.selectedAccountID
    @State private var isConnecting = false
    @State private var message: String?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.tr("Google Accounts", "Google аккаунты"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(L.tr("Connect any number of Google accounts for Meet Calendar imports.", "Подключайте любое число Google аккаунтов для импорта Meet Calendar."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    addAccount()
                } label: {
                    HStack(spacing: 6) {
                        if isConnecting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "person.crop.circle.badge.plus")
                        }
                        Text(L.tr("Add Account", "Добавить аккаунт"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isConnecting)
            }

            Divider()

            if accounts.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .foregroundStyle(SW.secondaryText)
                    Text(L.tr("No Google accounts connected.", "Google аккаунты не подключены."))
                        .font(SW.compactFont)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(accounts) { account in
                        GoogleAccountSettingsRow(
                            account: account,
                            isSelected: account.id == selectedAccountID,
                            isBusy: isConnecting,
                            onSelect: {
                                GoogleDriveMeetImporter.shared.selectAccount(id: account.id)
                                reload()
                                message = L.tr("Default Google account updated.", "Google аккаунт по умолчанию обновлён.")
                                error = nil
                            },
                            onReconnect: {
                                reconnectAccount(account)
                            },
                            onRemove: {
                                GoogleDriveMeetImporter.shared.disconnect(accountID: account.id)
                                reload()
                                message = L.tr("Google account removed.", "Google аккаунт удалён.")
                                error = nil
                            }
                        )

                        if account.id != accounts.last?.id {
                            Divider()
                        }
                    }
                }
            }

            if let error {
                settingsMessage(text: error, icon: "exclamationmark.triangle.fill", color: SW.danger)
            } else if let message {
                settingsMessage(text: message, icon: "checkmark.circle.fill", color: SW.accent)
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            reload()
            refreshMissingIdentities()
        }
    }

    private func addAccount() {
        isConnecting = true
        message = nil
        error = nil

        Task {
            do {
                let account = try await GoogleDriveMeetImporter.shared.connect()
                await MainActor.run {
                    reload()
                    selectedAccountID = account.id
                    message = L.tr("Google account connected.", "Google аккаунт подключён.")
                    isConnecting = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isConnecting = false
                }
            }
        }
    }

    private func reconnectAccount(_ oldAccount: GoogleOAuthAccount) {
        isConnecting = true
        message = nil
        error = nil

        Task {
            do {
                let account = try await GoogleDriveMeetImporter.shared.connect()
                if !oldAccount.hasIdentity && oldAccount.id != account.id {
                    GoogleDriveMeetImporter.shared.disconnect(accountID: oldAccount.id)
                }
                await MainActor.run {
                    reload()
                    selectedAccountID = account.id
                    message = L.tr("Google account reconnected.", "Google аккаунт переподключён.")
                    isConnecting = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isConnecting = false
                }
            }
        }
    }

    private func refreshMissingIdentities() {
        guard accounts.contains(where: { !$0.hasIdentity }) else { return }

        Task {
            await GoogleDriveMeetImporter.shared.refreshMissingAccountIdentities()
            await MainActor.run {
                reload()
            }
        }
    }

    private func reload() {
        accounts = GoogleDriveMeetImporter.shared.accounts
        selectedAccountID = GoogleDriveMeetImporter.shared.selectedAccountID
    }

    private func settingsMessage(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
                .lineLimit(2)
            Spacer()
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(color)
        .padding(8)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct GoogleAccountSettingsRow: View {
    let account: GoogleOAuthAccount
    let isSelected: Bool
    let isBusy: Bool
    let onSelect: () -> Void
    let onReconnect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: account.hasIdentity ? (isSelected ? "checkmark.circle.fill" : "person.crop.circle") : "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(account.hasIdentity ? (isSelected ? SW.accent : SW.secondaryText) : SW.warning)

            VStack(alignment: .leading, spacing: 3) {
                Text(account.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SW.primaryText)
                    .lineLimit(1)
                Text(account.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if !account.hasIdentity {
                Button(L.tr("Reconnect", "Переподключить"), action: onReconnect)
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy)
            } else if !isSelected {
                Button(L.tr("Use", "Использовать"), action: onSelect)
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
            }

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(isBusy)
            .help(L.tr("Remove Google account", "Удалить Google аккаунт"))
        }
        .padding(.vertical, 10)
    }
}

struct CustomModeEditorCard: View {
    let isEditing: Bool
    @Binding var modeName: String
    @Binding var modeDescription: String
    @Binding var exampleInput: String
    @Binding var exampleOutput: String
    @Binding var prompt: String
    @Binding var icon: String
    let isGeneratingExample: Bool
    let editorMessage: String?
    let canSave: Bool
    let hasDuplicateName: Bool
    let onGenerateExample: () -> Void
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isEditing ? L.tr("Edit Custom Mode", "Изменить custom mode") : L.tr("Create Custom Mode", "Создать custom mode"))
                        .font(.headline)
                    Text(L.tr("Define the prompt, then run an example input and save the result as the mode preview.", "Задайте промпт, затем прогоните пример входа и сохраните результат как превью режима."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isEditing {
                    Button(L.tr("Cancel", "Отмена"), action: onCancel)
                        .buttonStyle(.bordered)
                }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.tr("Mode Name", "Название режима")).font(.caption).foregroundStyle(.secondary)
                    TextField(TranscriptionMode.placeholderName, text: $modeName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L.tr("Icon", "Иконка")).font(.caption).foregroundStyle(.secondary)
                    TextField("sparkles", text: $icon)
                        .textFieldStyle(.roundedBorder)
                }
                .frame(width: 120)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L.tr("Description", "Описание")).font(.caption).foregroundStyle(.secondary)
                TextField(TranscriptionMode.placeholderDescription, text: $modeDescription)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.tr("Example Input", "Пример входа")).font(.caption).foregroundStyle(.secondary)
                    TextEditorCustom(text: $exampleInput, placeholder: TranscriptionMode.placeholderExampleInput)
                        .frame(height: 100)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L.tr("Example Output", "Пример выхода")).font(.caption).foregroundStyle(.secondary)
                    TextEditorCustom(text: $exampleOutput, placeholder: TranscriptionMode.placeholderExampleOutput)
                        .frame(height: 100)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L.tr("System Prompt", "Системный промпт")).font(.caption).foregroundStyle(.secondary)
                TextEditorCustom(text: $prompt, placeholder: TranscriptionMode.placeholderPrompt, isMonospaced: true)
                    .frame(minHeight: 120)
            }

            HStack(spacing: 10) {
                Button(action: onGenerateExample) {
                    Group {
                        if isGeneratingExample {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label(L.tr("Run Example", "Прогнать пример"), systemImage: "play.fill")
                        }
                    }
                    .frame(minWidth: 150)
                }
                .buttonStyle(.bordered)
                .disabled(isGeneratingExample)

                Button(action: onSave) {
                    Label(isEditing ? L.tr("Save Changes", "Сохранить изменения") : L.tr("Add Mode", "Добавить режим"), systemImage: isEditing ? "checkmark.circle.fill" : "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }

            if hasDuplicateName {
                Text(L.tr("A mode with this name already exists.", "Режим с таким названием уже существует."))
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if let editorMessage, !editorMessage.isEmpty {
                Text(editorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ModeCard: View {
    let mode: TranscriptionMode
    let isSelected: Bool
    let isEnabled: Bool
    let onSelect: () -> Void
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: mode.icon)
                            .font(.title3)
                            .foregroundStyle(isSelected ? SW.accent : (isEnabled ? .primary : .secondary))

                        Text(mode.localizedName)
                            .font(.headline)
                            .foregroundStyle(isSelected ? SW.accent : (isEnabled ? .primary : .secondary))

                        if !isEnabled {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }

                    Text(mode.localizedDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if !isEnabled {
                        Text(L.tr("Requires API Key & AI Refinement Enabled", "Нужен API key и включённая AI-обработка"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.orange.opacity(0.8))
                            .padding(.top, 4)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 12) {
                    let binding = Binding<Bool>(
                        get: { isSelected },
                        set: { if $0 && isEnabled { onSelect() } }
                    )
                    Toggle("", isOn: binding)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(!isEnabled)

                    if let onEdit = onEdit {
                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    if let onDelete = onDelete {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .opacity(isEnabled ? 1.0 : 0.6)

            VStack(alignment: .leading, spacing: 12) {
                ExampleBox(title: L.tr("Input:", "Вход:"), text: mode.exampleInput, icon: "mic")
                ExampleBox(title: L.tr("Output:", "Выход:"), text: mode.exampleOutput, icon: "sparkles", isOutput: true)
            }
            .opacity(isEnabled || mode.name == TranscriptionMode.dictation.name ? 1.0 : 0.4)
        }
        .padding(20)
        .background(isSelected ? SW.accent.opacity(0.05) : Color.primary.opacity(0.03))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? SW.accent.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            if isEnabled { onSelect() }
        }
    }
}
