import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var modelManager: ModelManager
    @ObservedObject var recorder: AudioRecorder
    @ObservedObject private var updater = GitHubUpdater.shared
    @State private var selectedTab: String? = "app"
    
    // Custom Mode State
    @State private var newModeName = ""
    @State private var newModeDescription = ""
    @State private var newModeExampleInput = ""
    @State private var newModeExampleOutput = ""
    @State private var newModePrompt = ""
    @State private var newModeIcon = "sparkles"
    
    // API Testing State
    @State private var isTestingAPI = false
    @State private var apiTestResult: String?

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
                    VStack(alignment: .leading, spacing: 32) { // More air between sections
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
                    .padding(32) // More air around content
                }
                .scrollContentBackground(.hidden)
                .background(Color.black.opacity(0.01)) // Helps with hit testing while remaining transparent
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            WindowHeaderUnderlay()
        }
        .onAppear {
            modelManager.refreshDownloadedModels()
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(columnTitle)
                    .font(.system(size: 13, weight: .semibold))
            }
        }
    }

    private var columnTitle: String {
        switch selectedTab {
        case "app": return L.tr("App Preferences", "Настройки приложения")
        case "capture": return L.tr("Capture & Automation", "Запись и автоматизация")
        case "engine": return L.tr("Engine & API", "Движок и API")
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
                .foregroundStyle(.orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(L.tr("Accessibility Permission Required", "Нужен доступ к Accessibility"))
                    .font(.headline)
                Text(L.tr("Global hotkeys won't work without this permission.", "Без этого разрешения глобальные хоткеи работать не будут."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button(L.tr("Grant Access…", "Выдать доступ…")) {
                appState.requestAccessibilityPermission()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(20)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                Picker(L.tr("Capture Style", "Режим записи"), selection: $appState.settings.recordingMode) {
                    ForEach(RecordingMode.allCases, id: \.self) { mode in
                        Label(mode.localizedTitle, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                
                Text(appState.settings.recordingMode.localizedDescription)
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
    }

    @ViewBuilder
    private var engineSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            VStack(alignment: .leading, spacing: 16) {
                Picker(L.tr("Model Source", "Источник модели"), selection: $appState.settings.engineType) {
                    ForEach(TranscriptionEngineType.allCases, id: \.self) { type in
                        Label(type.localizedTitle, systemImage: type.icon).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                Divider().padding(.horizontal)
                
                if appState.settings.engineType == .cloud {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L.tr("Cloud transcription uses OpenAI's Whisper API. It is fast and highly accurate, but requires an internet connection.", "Облачная транскрибация использует OpenAI Whisper API. Это быстро и точно, но требует интернет-соединения."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L.tr("OpenAI API Key", "OpenAI API Key")).font(.caption).foregroundStyle(.secondary)
                            SecureField("sk-...", text: $appState.settings.apiKey)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: appState.settings.apiKey) { _, _ in
                                    appState.settings.selectedModeName = appState.settings.validatedModeName(currentName: appState.settings.selectedModeName)
                                    appState.saveSettings()
                                }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L.tr("Local models run entirely on your Mac. They are private and work offline. Larger models are more accurate but use more memory.", "Локальные модели работают полностью на вашем Mac. Они приватные и доступны офлайн. Более крупные модели точнее, но требуют больше памяти."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                        
                        VStack(spacing: 0) {
                            ForEach(LocalModelSize.allCases, id: \.self) { size in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(size.rawValue)
                                            .font(.system(size: 14, weight: .semibold))
                                        Text(size.sizeDescription)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
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
                                                .buttonStyle(.plain).font(.caption2).foregroundStyle(SW.accent)
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
                    }
                }
            }
            .padding(.vertical)
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
                            onDelete: mode.isBuiltIn ? nil : {
                                appState.settings.customModes.removeAll { $0.id == mode.id }
                                if appState.settings.selectedModeName == mode.name {
                                    appState.settings.selectedModeName = TranscriptionMode.dictation.name
                                }
                                appState.saveSettings()
                            }
                        )
                    }
                }
            }
            
            Section("Create Custom Mode") {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.tr("Mode Name", "Название режима")).font(.caption).foregroundStyle(.secondary)
                        TextField(TranscriptionMode.placeholderName, text: $newModeName)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.tr("Description", "Описание")).font(.caption).foregroundStyle(.secondary)
                        TextField(TranscriptionMode.placeholderDescription, text: $newModeDescription)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L.tr("Example Input", "Пример входа")).font(.caption).foregroundStyle(.secondary)
                            TextEditorCustom(text: $newModeExampleInput, placeholder: TranscriptionMode.placeholderExampleInput)
                                .frame(height: 60)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L.tr("Example Output", "Пример выхода")).font(.caption).foregroundStyle(.secondary)
                            TextEditorCustom(text: $newModeExampleOutput, placeholder: TranscriptionMode.placeholderExampleOutput)
                                .frame(height: 60)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.tr("System Prompt (Instructions for AI)", "Системный промпт (инструкции для AI)")).font(.caption).foregroundStyle(.secondary)
                        TextEditorCustom(text: $newModePrompt, placeholder: TranscriptionMode.placeholderPrompt, isMonospaced: true)
                            .frame(minHeight: 100)
                    }
                    
                    Button {
                        let mode = TranscriptionMode(
                            name: newModeName,
                            icon: newModeIcon,
                            description: newModeDescription,
                            exampleInput: newModeExampleInput,
                            exampleOutput: newModeExampleOutput,
                            systemPrompt: newModePrompt,
                            isBuiltIn: false
                        )
                        appState.settings.customModes.append(mode)
                        appState.saveSettings()
                        newModeName = ""
                        newModeDescription = ""
                        newModeExampleInput = ""
                        newModeExampleOutput = ""
                        newModePrompt = ""
                    } label: {
                        Label(L.tr("Add Mode", "Добавить режим"), systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(newModeName.isEmpty || newModePrompt.isEmpty)
                }
                .padding(.vertical, 8)
            }
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
                    
                    DisclosureGroup {
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
                    Text(appVersionText).font(.subheadline).foregroundStyle(.secondary)
                }
                
                Text(L.tr("Hyper-fast voice to text for macOS.", "Очень быстрая голосовая транскрибация для macOS."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 24) {
                    Link("GitHub", destination: URL(string: "https://github.com/iddictive/Whisper-Free")!)
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
        settings.engineType == .cloud || settings.enableSpeakerDiarization || settings.hasOpenAIAPIKey
    }

    private var shouldShowDedicatedDiarizationAPIKey: Bool {
        settings.engineType != .cloud
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(L.tr("Enable AI Refinement", "Включить AI-обработку"), isOn: $settings.enablePostProcessing)
                    .onChange(of: settings.enablePostProcessing) { _, _ in
                        settings.selectedModeName = settings.validatedModeName(currentName: settings.selectedModeName)
                        onSave()
                    }
                Text(L.tr("Applies formatting, custom prompts, and grammar fixes after transcription is complete.", "Применяет форматирование, пользовательские промпты и исправления грамматики после завершения транскрибации."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 22)
            }
            
            if settings.enablePostProcessing {
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(L.tr("OpenAI API Key", "OpenAI API Key")).font(.caption).foregroundStyle(.secondary)
                            if settings.engineType == .cloud {
                                Text(L.tr("(Using key from Transcription Engine)", "(Используется ключ из блока транскрибации)")).font(.system(size: 9)).foregroundStyle(Color.accentColor)
                            }
                        }
                        SecureField("sk-...", text: $settings.apiKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: settings.apiKey) { _, _ in
                                settings.selectedModeName = settings.validatedModeName(currentName: settings.selectedModeName)
                                onSave()
                            }
                        Text(L.tr("OpenAI GPT: reliable formatting and structuring.", "OpenAI GPT: надёжное форматирование и структурирование."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            if shouldShowDiarizationControls {
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(L.tr("Speaker Diarization (AI-powered)", "Диаризация спикеров (AI)"), isOn: $settings.enableSpeakerDiarization)
                        .onChange(of: settings.enableSpeakerDiarization) { _, _ in 
                            onSave() 
                        }

                    if shouldShowDedicatedDiarizationAPIKey {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L.tr("OpenAI API Key", "OpenAI API Key")).font(.caption).foregroundStyle(.secondary)
                            SecureField("sk-...", text: $settings.apiKey)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: settings.apiKey) { _, _ in
                                    settings.selectedModeName = settings.validatedModeName(currentName: settings.selectedModeName)
                                    onSave()
                                }
                            Text(L.tr("Required for diarization when transcription runs locally.", "Нужно для диаризации, когда транскрибация выполняется локально."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Text(L.tr("Uses AI to identify and split different speakers in the transcription. Best for interviews and meetings.", "Использует AI для определения и разделения разных спикеров в транскрипции. Лучше всего подходит для интервью и встреч."))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if settings.enableSpeakerDiarization && !settings.canUseSpeakerDiarization {
                        Text(L.tr("Add an OpenAI API key to enable diarization.", "Добавьте OpenAI API key, чтобы включить диаризацию."))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if settings.enableSpeakerDiarization {
                        Text(L.tr("When diarization is enabled, standard AI refinement is skipped to preserve speaker turns.", "Когда включена диаризация, стандартная AI-обработка пропускается, чтобы сохранить очередность спикеров."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct ModeCard: View {
    let mode: TranscriptionMode
    let isSelected: Bool
    let isEnabled: Bool
    let onSelect: () -> Void
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
