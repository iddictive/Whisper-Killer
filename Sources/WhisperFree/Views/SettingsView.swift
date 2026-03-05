import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    private var modelManager: ModelManager { appState.modelManager }
    @ObservedObject private var updater = GitHubUpdater.shared
    @State private var selectedTab: String? = "app"
    @State private var isTestingAPI = false
    @State private var apiTestResult: String?
    @State private var transcriptionTab = 0
    @State private var newModeName = ""
    @State private var newModeDescription = ""
    @State private var newModeExampleInput = ""
    @State private var newModeExampleOutput = ""
    @State private var newModePrompt = ""
    @State private var newModeIcon = "sparkles"

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
                            Label("App", systemImage: "apps.iphone")
                                .tag("app")
                            Label("Capture & Automation", systemImage: "mic.fill")
                                .tag("capture")
                            Label("Engine & API", systemImage: "cpu.fill")
                                .tag("engine")
                            Label("AI Modes", systemImage: "sparkles")
                                .tag("modes")
                            Label("Usage & About", systemImage: "info.circle.fill")
                                .tag("info")
                        }
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .frame(width: 230)
                    
                    Spacer()
                }
                .padding(.top, 40) // Space for traffic lights
                
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
        .onAppear {
            modelManager.refreshDownloadedModels()
        }
    }

    private var permissionBanner: some View {
        HStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Accessibility Permission Required")
                    .font(.headline)
                Text("Global hotkeys won't work without this permission.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button("Grant Access…") {
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
        Section("Preferences") {
            Picker("Preferred Language", selection: $appState.settings.language) {
                ForEach(AppSettings.supportedLanguages, id: \.code) { lang in
                    Text(lang.name).tag(lang.code)
                }
            }
            .onChange(of: appState.settings.language) { _, _ in
                appState.saveSettings()
            }
            
            Toggle("Monochrome menu bar icon", isOn: $appState.settings.useMonochromeMenuIcon)
                .onChange(of: appState.settings.useMonochromeMenuIcon) { _, _ in
                    appState.saveSettings()
                }
        }
        
        Section("Software Updates") {
            Toggle("Automatically check for updates", isOn: $appState.settings.automaticallyChecksForUpdates)
                
            Toggle("Automatically download updates", isOn: $appState.settings.automaticallyDownloadsUpdates)
                .disabled(!appState.settings.automaticallyChecksForUpdates)
            
            if let error = updater.error {
                VStack(alignment: .leading) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
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
                    Text("Downloading update... \(Int(updater.downloadProgress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else if updater.updateAvailable {
                Button("Download & Install (v\(updater.latestVersion ?? ""))") {
                    updater.startDownload()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Button(updater.isChecking ? "Checking..." : "Check for Updates Now...") {
                    updater.checkForUpdates(manual: true)
                }
                .disabled(updater.isChecking)
                .padding(.top, 4)
                .font(.caption)
            }
        }
    }

    @ViewBuilder
    private var captureSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recording Mode")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                Picker("Capture Style", selection: $appState.settings.recordingMode) {
                    ForEach(RecordingMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                
                Text(appState.settings.recordingMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding()
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        
        VStack(alignment: .leading, spacing: 16) {
            Text("Live Microphone Test")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    WaveformView(levels: appState.recorder.audioLevels)
                        .frame(height: 40)
                    
                    Spacer()
                    
                    if appState.recorder.isTooQuiet {
                        Text("SILENCE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(Capsule())
                    } else {
                        Text("SIGNAL DETECTED")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                
                Text("Speak to verify the application hears you. If the bars don't move, check your system microphone settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Button("Open System Audio Settings") {
                    appState.openMicrophoneSettings()
                }
                .buttonStyle(.link)
                .font(.caption)
            }
            .padding(20)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        
        VStack(alignment: .leading, spacing: 16) {
            Text("Global Shortcut")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            HotkeyRecorderView(config: $appState.settings.hotkeyConfig)
                .padding()
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        
        VStack(alignment: .leading, spacing: 16) {
            Text("Automation & Interface")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 0) {
                Toggle("Auto-type into active app", isOn: $appState.settings.autoTypeResult)
                    .padding()
                
                Divider().padding(.horizontal)
                
                Toggle("Auto-Enter automatically", isOn: $appState.settings.experimentalAutoEnter)
                    .padding()
                
                Divider().padding(.horizontal)
                
                Toggle("Show floating recording pill", isOn: $appState.settings.showOverlay)
                    .padding()
            }
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    private var engineSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcription Engine")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Picker("Model Source", selection: $appState.settings.engineType) {
                ForEach(TranscriptionEngineType.allCases, id: \.self) { type in
                    Label(type.rawValue, systemImage: type.icon).tag(type)
                }
            }
            .pickerStyle(.radioGroup)
            .padding()
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }

        if appState.settings.engineType == .local {
            VStack(alignment: .leading, spacing: 16) {
                Text("Local Models (whisper.cpp)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
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
                                        .foregroundStyle(.green)
                                        .font(.title3)
                                } else {
                                    Button("Use") {
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
                                    Button("Retry") { modelManager.downloadModel(size) }
                                        .buttonStyle(.plain).font(.caption2).foregroundStyle(SW.accent)
                                } else {
                                    ProgressView(value: state.progress).frame(width: 80)
                                }
                            } else {
                                Button("Download") { modelManager.downloadModel(size) }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding()
                        if size != LocalModelSize.allCases.last { Divider().padding(.horizontal) }
                    }
                }
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }

        VStack(alignment: .leading, spacing: 16) {
            Text("AI Refinement & API Keys")
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
            Text("Select Active Mode")
                .font(.headline)
                .padding(.top, 8)
                .padding(.leading, 16)

            ForEach(appState.settings.allModes) { mode in
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
                        Text("Mode Name").font(.caption).foregroundStyle(.secondary)
                        TextField(TranscriptionMode.placeholderName, text: $newModeName)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description").font(.caption).foregroundStyle(.secondary)
                        TextField(TranscriptionMode.placeholderDescription, text: $newModeDescription)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Example Input").font(.caption).foregroundStyle(.secondary)
                            TextEditorCustom(text: $newModeExampleInput, placeholder: TranscriptionMode.placeholderExampleInput)
                                .frame(height: 60)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Example Output").font(.caption).foregroundStyle(.secondary)
                            TextEditorCustom(text: $newModeExampleOutput, placeholder: TranscriptionMode.placeholderExampleOutput)
                                .frame(height: 60)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("System Prompt (Instructions for AI)").font(.caption).foregroundStyle(.secondary)
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
                        Label("Add Mode", systemImage: "plus.circle.fill")
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
        Section("Usage Statistics (7 Days)") {
            let logs = appState.settings.usageLogs
            let totalTokens = logs.reduce(0) { $0 + $1.totalTokens }
            let totalCost = logs.reduce(0.0) { $0 + $1.estimatedCost }
            
            HStack(spacing: 40) {
                VStack(alignment: .leading) {
                    Text("Total Tokens").font(.caption).foregroundStyle(.secondary)
                    Text("\(totalTokens)").font(.title2).bold().foregroundStyle(SW.accent)
                }
                
                VStack(alignment: .leading) {
                    Text("Est. Cost").font(.caption).foregroundStyle(.secondary)
                    Text("$\(String(format: "%.4f", totalCost))").font(.title2).bold().foregroundStyle(.green)
                }
                
                Spacer()
                
                Button("Reset Logs") {
                    appState.settings.usageLogs.removeAll()
                    appState.saveSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.vertical, 8)
            
            if !logs.isEmpty {
                 DisclosureGroup("Recent Activity Details") {
                    VStack {
                        ForEach(logs.reversed()) { log in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(log.modeName).font(.system(size: 12, weight: .bold))
                                    Text(log.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("\(log.totalTokens) tokens").font(.system(size: 11, design: .monospaced))
                                    Text(log.engine).font(.system(size: 9)).foregroundStyle(.secondary).italic()
                                }
                            }
                            .padding(.vertical, 2)
                            Divider()
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        
        Section("About Whisper Free") {
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [SW.accent, SW.accentBlue], startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.1))
                    Image(systemName: "microphone.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: [SW.accent, SW.accentBlue], startPoint: .top, endPoint: .bottom))
                }
                .frame(width: 80, height: 80)
                
                VStack(spacing: 8) {
                    Text("Whisper Free").font(.system(size: 28, weight: .bold))
                    Text("Version 2.0").font(.subheadline).foregroundStyle(.secondary)
                }
                
                Text("Hyper-fast voice to text for macOS.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 24) {
                    Link("GitHub", destination: URL(string: "https://github.com/iddictive/Whisper-Free")!)
                    Link("iddictive", destination: URL(string: "https://github.com/iddictive")!)
                }
                .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    private func testAPIKey() {
        isTestingAPI = true
        apiTestResult = nil

        Task {
            let url = URL(string: "https://api.openai.com/v1/models")!
            var request = URLRequest(url: url)
            request.setValue("Bearer \(appState.settings.apiKey)", forHTTPHeaderField: "Authorization")

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    apiTestResult = "✓ API key is valid"
                } else {
                    apiTestResult = "✗ Invalid API key"
                }
            } catch {
                apiTestResult = "✗ Connection error: \(error.localizedDescription)"
            }
            isTestingAPI = false
        }
    }
}

// MARK: - Helper Views

struct AIConfigView: View {
    @Binding var settings: AppSettings
    var onSave: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Toggle("Enable AI Refinement Globally", isOn: $settings.enablePostProcessing)
                .onChange(of: settings.enablePostProcessing) { _, _ in
                    settings.selectedModeName = settings.validatedModeName(currentName: settings.selectedModeName)
                    onSave()
                }
            
            Picker("AI Engine", selection: $settings.postProcessingEngine) {
                ForEach(PostProcessingEngine.allCases, id: \.self) { engine in
                    Text(engine.rawValue).tag(engine)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!settings.enablePostProcessing)
            .onChange(of: settings.postProcessingEngine) { _, _ in
                settings.selectedModeName = settings.validatedModeName(currentName: settings.selectedModeName)
                onSave()
            }
            
            let requiresOpenAI = settings.engineType == .cloud || (settings.enablePostProcessing && settings.postProcessingEngine == .openai)
            let requiresPerplexity = settings.enablePostProcessing && settings.postProcessingEngine == .perplexity
            
            if requiresOpenAI || requiresPerplexity {
                VStack(alignment: .leading, spacing: 12) {
                    if requiresOpenAI {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("OpenAI API Key").font(.caption).foregroundStyle(.secondary)
                                if settings.engineType == .cloud {
                                    Text("(Required for Transcription)").font(.system(size: 9)).foregroundStyle(.orange)
                                }
                            }
                            SecureField("sk-...", text: $settings.apiKey)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: settings.apiKey) { _, _ in
                                    settings.selectedModeName = settings.validatedModeName(currentName: settings.selectedModeName)
                                    onSave()
                                }
                        }
                    }
                    
                    if requiresPerplexity {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Perplexity API Key").font(.caption).foregroundStyle(.secondary)
                            SecureField("pplx-...", text: $settings.perplexityApiKey)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: settings.perplexityApiKey) { _, _ in
                                    settings.selectedModeName = settings.validatedModeName(currentName: settings.selectedModeName)
                                    onSave()
                                }
                        }
                    }
                    
                    if settings.enablePostProcessing {
                        Text(settings.postProcessingEngine == .perplexity 
                             ? "Perplexity Sonar: Best for intelligent grammar/flow." 
                             : "OpenAI GPT: Reliable formatting and structuring.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if requiresOpenAI {
                        Divider()
                        
                        Toggle("Speaker Diarization (AI-powered)", isOn: $settings.enableSpeakerDiarization)
                            .onChange(of: settings.enableSpeakerDiarization) { _, _ in 
                                onSave() 
                            }
                        
                        Text("Uses AI to identify and split different speakers in the transcription. Best for interviews and meetings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
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
                        
                        Text(mode.name)
                            .font(.headline)
                            .foregroundStyle(isSelected ? SW.accent : (isEnabled ? .primary : .secondary))
                        
                        if !isEnabled {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    
                    Text(mode.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    
                    if !isEnabled {
                        Text("Requires API Key & AI Refinement Enabled")
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
                ExampleBox(title: "Input:", text: mode.exampleInput, icon: "mic")
                ExampleBox(title: "Output:", text: mode.exampleOutput, icon: "sparkles", isOutput: true)
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

struct ExampleBox: View {
    let title: String
    let text: String
    let icon: String
    var isOutput: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(isOutput ? SW.accentBlue : SW.text3)
            
            Text(text)
                .font(.system(size: 12, weight: .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(.primary)
        }
    }
}

struct TextEditorCustom: View {
    @Binding var text: String
    let placeholder: String
    var isMonospaced: Bool = false
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(isMonospaced ? .system(size: 12, design: .monospaced) : .system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
            }
            
            TextEditor(text: $text)
                .font(isMonospaced ? .system(size: 12, design: .monospaced) : .system(size: 11))
                .scrollContentBackground(.hidden)
                .background(.clear)
                .padding(4)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}
