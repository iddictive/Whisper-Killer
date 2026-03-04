import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    private var modelManager: ModelManager { appState.modelManager }
    @State private var selectedTab = "general"
    @State private var isTestingAPI = false
    @State private var apiTestResult: String?
    @State private var transcriptionTab = 0
    @State private var newModeName = ""
    @State private var newModePrompt = ""
    @State private var newModeIcon = "text.bubble"

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
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
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
            Section("Current Mode") {
                Picker("Active AI Mode", selection: $appState.settings.selectedModeName) {
                    ForEach(appState.settings.allModes) { mode in
                        Label(mode.name, systemImage: mode.icon).tag(mode.name)
                    }
                }
                .onChange(of: appState.settings.selectedModeName) { _, _ in
                    appState.saveSettings()
                }
            }
            
            Section("Custom Modes") {
                ForEach(appState.settings.customModes) { mode in
                    HStack {
                        Image(systemName: mode.icon)
                        Text(mode.name)
                        Spacer()
                        Button(role: .destructive) {
                            appState.settings.customModes.removeAll { $0.id == mode.id }
                            appState.saveSettings()
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            Section("New Mode") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Mode Name", text: $newModeName)
                        .textFieldStyle(.roundedBorder)
                    
                    TextEditor(text: $newModePrompt)
                        .frame(minHeight: 80)
                        .font(.system(size: 12, design: .monospaced))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2))
                        )
                    
                    Button("Create Mode") {
                        let mode = TranscriptionMode(name: newModeName, icon: "sparkles", systemPrompt: newModePrompt, isBuiltIn: false)
                        appState.settings.customModes.append(mode)
                        appState.saveSettings()
                        newModeName = ""
                        newModePrompt = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newModeName.isEmpty || newModePrompt.isEmpty)
                }
            }
        }
    }

    private var aboutSection: some View {
        Section {
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [SW.accent, SW.accentPink], startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.1))
                    Image(systemName: "microphone.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: [SW.accent, SW.accentPink], startPoint: .top, endPoint: .bottom))
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
