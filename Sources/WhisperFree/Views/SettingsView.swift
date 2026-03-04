import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    private var modelManager: ModelManager { appState.modelManager }
    @State private var selectedTab = "general"
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
        NavigationSplitView {
            List(selection: $selectedTab) {
                Label("General", systemImage: "gearshape")
                    .tag("general")
                Label("Recording", systemImage: "mic")
                    .tag("recording")
                Label("Transcription", systemImage: "cpu")
                    .tag("transcription")
                Label("AI Modes", systemImage: "sparkles")
                    .tag("modes")
                Label("About", systemImage: "info.circle")
                    .tag("about")
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            Form {
                if !appState.isHotkeyTrusted && selectedTab != "about" {
                    permissionBanner
                }
                
                switch selectedTab {
                case "general": generalSection
                case "recording": recordingSection
                case "transcription": transcriptionSection
                case "modes": modesSection
                case "about": aboutSection
                default: Text("Select a category")
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 780, minHeight: 520)
        .onAppear {
            modelManager.refreshDownloadedModels()
        }
    }

    private var permissionBanner: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility Permission Required")
                        .font(.headline)
                    Text("Global hotkeys won't work without this permission.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button("Grant Access…") {
                    let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
                    AXIsProcessTrustedWithOptions(options)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Sections

    private var generalSection: some View {
        Section(header: Text("AI Credentials")) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("OpenAI API Key", systemImage: "sparkles")
                        .font(.subheadline.bold())
                    
                    SecureField("sk-...", text: $appState.settings.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: appState.settings.apiKey) { _, _ in
                            appState.saveSettings()
                        }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Label("Perplexity API Key", systemImage: "magnifyingglass")
                        .font(.subheadline.bold())
                    
                    SecureField("pplx-...", text: $appState.settings.perplexityApiKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: appState.settings.perplexityApiKey) { _, _ in
                            appState.saveSettings()
                        }
                }
                
                Text("API keys are stored securely in your system.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            
            Picker("Preferred Language", selection: $appState.settings.language) {
                ForEach(AppSettings.supportedLanguages, id: \.code) { lang in
                    Text(lang.name).tag(lang.code)
                }
            }
            .onChange(of: appState.settings.language) { _, _ in
                appState.saveSettings()
            }
            
            Section("Software Updates") {
                Toggle("Automatically check for updates", isOn: $appState.settings.automaticallyChecksForUpdates)
                    
                Toggle("Automatically download updates", isOn: $appState.settings.automaticallyDownloadsUpdates)
                    .disabled(!appState.settings.automaticallyChecksForUpdates)
                
                Button("Check for Updates Now...") {
                    GitHubUpdater.shared.checkForUpdates(manual: true)
                }
                .padding(.top, 4)
                .font(.caption)
            }
        }
    }

    private var recordingSection: some View {
        Group {
            Section("Audio Capture") {
                Picker("Recording Mode", selection: $appState.settings.recordingMode) {
                    ForEach(RecordingMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                    }
                }
                .onChange(of: appState.settings.recordingMode) { _, _ in
                    appState.saveSettings()
                }
                
                Text(appState.settings.recordingMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("Shortcut") {
                HotkeyRecorderView(config: $appState.settings.hotkeyConfig)
                    .padding(.vertical, 4)
                    .onChange(of: appState.settings.hotkeyConfig) { _, _ in
                        appState.saveSettings()
                        appState.reloadHotkeyManager()
                    }
            }
            
            Section("Preferences") {
                Toggle("Auto-type into active app", isOn: $appState.settings.autoTypeResult)
                    .onChange(of: appState.settings.autoTypeResult) { _, _ in
                        appState.saveSettings()
                    }
                
                Toggle("Show floating recording pill", isOn: $appState.settings.showOverlay)
                    .onChange(of: appState.settings.showOverlay) { _, _ in
                        appState.saveSettings()
                    }
            }
        }
    }

    private var transcriptionSection: some View {
        Group {
            Section("Transcription Provider") {
                Picker("Provider", selection: $appState.settings.engineType) {
                    ForEach(TranscriptionEngineType.allCases, id: \.self) { type in
                        HStack {
                            Image(systemName: type.icon)
                                .frame(width: 20)
                            Text(type.rawValue)
                        }.tag(type)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: appState.settings.engineType) { _, _ in
                    appState.saveSettings()
                }
            }

            Section("Language Settings") {
                Picker("Primary Language", selection: $appState.settings.language) {
                    ForEach(AppSettings.supportedLanguages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .onChange(of: appState.settings.language) { _, _ in
                    appState.saveSettings()
                }
            }

            Section("AI Refinement (Post-processing)") {
                Picker("Engine", selection: $appState.settings.postProcessingEngine) {
                    ForEach(PostProcessingEngine.allCases, id: \.self) { engine in
                        Text(engine.rawValue).tag(engine)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: appState.settings.postProcessingEngine) { _, _ in
                    appState.saveSettings()
                }
                
                if appState.settings.postProcessingEngine == .perplexity {
                    Text("Perplexity Sonar: Best for intelligent grammar fix and natural flow.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("OpenAI GPT: Reliable formatting and structured refinement.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if appState.settings.engineType == .local {
                Section("Local Models") {
                    ForEach(LocalModelSize.allCases, id: \.self) { size in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(size.rawValue)
                                    .font(.system(size: 13, weight: .medium))
                                Text(size.sizeDescription)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            if modelManager.isModelDownloaded(size) {
                                if appState.settings.localModelSize == size {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Button("Use") {
                                        appState.settings.localModelSize = size
                                        appState.saveSettings()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                
                                Button(role: .destructive) {
                                    modelManager.deleteModel(size)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            } else if modelManager.isDownloading(size) {
                                ProgressView(value: modelManager.activeDownloads[size.rawValue]?.progress ?? 0)
                                    .progressViewStyle(.linear)
                                    .frame(width: 80)
                            } else {
                                Button("Download") {
                                    modelManager.downloadModel(size)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("Advanced") {
                Toggle("Auto-insert into active app", isOn: $appState.settings.autoTypeResult)
                    .onChange(of: appState.settings.autoTypeResult) { _, _ in
                        appState.saveSettings()
                    }
            }
        }
    }

    private var modesSection: some View {
        Group {
            Section("Active Transcription Mode") {
                ForEach(appState.settings.allModes) { mode in
                    ModeCard(
                        mode: mode,
                        isSelected: appState.settings.selectedModeName == mode.name,
                        onSelect: {
                            appState.settings.selectedModeName = mode.name
                            appState.saveSettings()
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
            
            Section("Create Custom Mode") {
                TextField("Mode Name", text: $newModeName)
                TextField("Description", text: $newModeDescription)
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Example Input").font(.caption).foregroundStyle(.secondary)
                            TextEditor(text: $newModeExampleInput)
                                .frame(height: 60)
                                .font(.system(size: 11))
                                .padding(4)
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                .cornerRadius(4)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Example Output").font(.caption).foregroundStyle(.secondary)
                            TextEditor(text: $newModeExampleOutput)
                                .frame(height: 60)
                                .font(.system(size: 11))
                                .padding(4)
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                .cornerRadius(4)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("System Prompt (Instructions for AI)").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $newModePrompt)
                            .frame(minHeight: 100)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(4)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                            .cornerRadius(4)
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
                        Label("Save Custom Mode", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(newModeName.isEmpty || newModePrompt.isEmpty)
                    .padding(.top, 8)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var aboutSection: some View {
        Section {
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
            .padding(.vertical, 40)
        }
    }

    // MARK: - API Test

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

struct ModeCard: View {
    let mode: TranscriptionMode
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(mode.name, systemImage: mode.icon)
                    .font(.headline)
                    .foregroundStyle(isSelected ? SW.accent : .primary)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(SW.accent)
                }
                
                if let onDelete = onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 8)
                }
            }
            
            Text(mode.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 10) {
                ExampleBox(title: "Input:", text: mode.exampleInput, icon: "mic")
                ExampleBox(title: "Output:", text: mode.exampleOutput, icon: "sparkles", isOutput: true)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

struct ExampleBox: View {
    let title: String
    let text: String
    let icon: String
    var isOutput: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(isOutput ? SW.accentBlue : SW.text3)
            
            Text(text)
                .font(.system(size: 11, weight: .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isOutput ? SW.accentBlue.opacity(0.3) : Color.primary.opacity(0.05), lineWidth: 1)
                )
                .cornerRadius(6)
                .foregroundStyle(.primary)
        }
    }
}
