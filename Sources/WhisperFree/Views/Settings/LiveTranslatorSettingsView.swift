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
    
    // Check if Ollama exists
    @State private var isOllamaInstalled: Bool = {
        FileManager.default.fileExists(atPath: "/Applications/Ollama.app")
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            // Header
            HStack(spacing: 16) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(SW.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Live Translator")
                        .font(.title2.bold())
                    Text("Translate speech to on-screen subtitles in real-time.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $appState.settings.liveTranslatorEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onChange(of: appState.settings.liveTranslatorEnabled) { _, _ in
                        appState.saveSettings()
                        appState.reloadHotkeyManager()
                    }
            }
            .padding(.bottom, 8)
            
            if appState.settings.liveTranslatorEnabled {
                
                // 1. Hotkey & Audio Setup
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Triggers & Routing").font(.headline)
                        
                        Divider()
                        
                        HStack {
                            Text("Global Hotkey")
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
                                // Invisible view to catch keyboard events while recording
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
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Capture System Audio")
                                Text("Grab sound directly from windows/apps (No drivers!)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $appState.settings.useScreenCaptureKit)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .onChange(of: appState.settings.useScreenCaptureKit) { _, _ in
                                    appState.saveSettings()
                                }
                        }
                        
                        Divider()
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Audio Input")
                                Text("Independent from main dictation.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            
                            Picker("", selection: $appState.settings.liveTranslatorInputDeviceID) {
                                Text("System Default").tag(String?.none)
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
                            }
                        }
                    }
                    .padding(8)
                }
                
                // 2. Translation Engine
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Translation Engine").font(.headline)
                        
                        Picker("", selection: $appState.settings.liveTranslatorEngine) {
                            ForEach(LiveTranslationEngine.allCases, id: \.self) { engine in
                                Text(engine.rawValue).tag(engine)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: appState.settings.liveTranslatorEngine) { _, _ in appState.saveSettings() }
                        
                        Divider()
                        
                        if appState.settings.liveTranslatorEngine == .local {
                            VStack(alignment: .leading, spacing: 12) {
                                if !isOllamaInstalled {
                                    // Big Ollama installer
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundStyle(.orange)
                                                .font(.title3)
                                            VStack(alignment: .leading) {
                                                Text("Ollama is required for local translation.")
                                                    .font(.headline)
                                                Text("We can download and install it for you securely.")
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        
                                        HStack {
                                            Button(installer.isInstallingOllama ? "Installing..." : "Install Ollama") {
                                                installer.installOllama()
                                            }
                                            .disabled(installer.isInstallingOllama)
                                            .buttonStyle(.borderedProminent)
                                            .tint(.blue)
                                            
                                            if installer.isInstallingOllama {
                                                ProgressView(value: installer.ollamaProgress).frame(width: 100)
                                            }
                                            Text(installer.ollamaStatus)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding()
                                    .background(Color.orange.opacity(0.1))
                                    .cornerRadius(8)
                                    // Listen for changes
                                    .onReceive(installer.$ollamaStatus) { status in
                                        if status == "Installed Successfully" {
                                            isOllamaInstalled = true
                                        }
                                    }
                                } else {
                                    // Ollama is installed -> Show model selector
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Ollama Model")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        
                                        HStack {
                                            if isLoadingModels {
                                                ProgressView().controlSize(.small)
                                                Text("Fetching models...").font(.caption2)
                                            } else if localModels.isEmpty {
                                                Text("No models found. Enter a name to pull.")
                                                    .font(.caption2).foregroundStyle(.secondary)
                                            } else {
                                                Picker("", selection: $appState.settings.liveTranslatorLocalModel) {
                                                    Text("Select a model...").tag("")
                                                    ForEach(localModels, id: \.self) { model in
                                                        HStack {
                                                            Text(model)
                                                            if appState.settings.liveTranslatorLocalModel == model {
                                                                Image(systemName: "checkmark").font(.caption2)
                                                            }
                                                        }.tag(model)
                                                    }
                                                }
                                                .pickerStyle(.menu)
                                                .frame(width: 250)
                                                .onChange(of: appState.settings.liveTranslatorLocalModel) { _, _ in 
                                                    appState.saveSettings()
                                                    NotificationCenter.default.post(name: NSNotification.Name("LiveTranslatorSettingsChanged"), object: nil)
                                                }
                                            }
                                            
                                            Spacer()
                                            
                                            Button { 
                                                refreshModels()
                                            } label: {
                                                Image(systemName: "arrow.clockwise")
                                                    .font(.system(size: 10))
                                            }
                                            .buttonStyle(.plain)
                                            .help("Refresh model list from Ollama")
                                        }

                                        HStack {
                                            TextField("Custom model name (e.g. qwen2.5:3b)", text: $appState.settings.liveTranslatorLocalModel)
                                                .textFieldStyle(.roundedBorder)
                                                .onChange(of: appState.settings.liveTranslatorLocalModel) { _, _ in appState.saveSettings() }
                                            
                                            Button(isPulling ? "Pulling..." : "Download") {
                                                pullModel(name: appState.settings.liveTranslatorLocalModel)
                                            }
                                            .disabled(isPulling || appState.settings.liveTranslatorLocalModel.isEmpty || localModels.contains(appState.settings.liveTranslatorLocalModel))
                                        }
                                        
                                        if let status = pullStatus {
                                            Text(status)
                                                .font(.caption2)
                                                .foregroundStyle(status.contains("Failed") ? .red : .accentColor)
                                        }
                                    }
                                }
                            }
                        } else {
                            Text("Uses the global Cloud Engine (OpenAI) specified in the 'Engine & API' tab.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                    }
                    .padding(8)
                }
                
                // 3. Target Language
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Target Language")
                                .font(.headline)
                            Spacer()
                            Picker("", selection: $appState.settings.liveTranslatorTargetLanguage) {
                                ForEach(AppSettings.supportedLanguages, id: \.code) { lang in
                                    if lang.code != "auto" {
                                        Text(lang.name).tag(lang.name)
                                    }
                                }
                            }
                            .frame(width: 150)
                            .onChange(of: appState.settings.liveTranslatorTargetLanguage) { _, _ in appState.saveSettings() }
                        }
                    }
                    .padding(8)
                }
            } else {
                Spacer()
            }
        }
        .onAppear {
            isOllamaInstalled = FileManager.default.fileExists(atPath: "/Applications/Ollama.app")
            if isOllamaInstalled {
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
    
    private func pullModel(name: String) {
        let engine = LocalTranslationEngine()
        isPulling = true
        pullStatus = "Checking Ollama..."
        
        Task {
            if await !engine.isRunning() {
                pullStatus = "Failed: Ollama isn't running."
                isPulling = false
                return
            }
            pullStatus = "Starting download..."
            do {
                try await engine.pullModel(name: name) { status in
                    DispatchQueue.main.async {
                        self.pullStatus = status
                    }
                }
                pullStatus = "Downloaded '\(name)' successfully!"
                refreshModels()
            } catch {
                pullStatus = "Failed: \(error.localizedDescription)"
            }
            isPulling = false
        }
    }

    private func refreshModels() {
        isLoadingModels = true
        Task {
            let engine = LocalTranslationEngine()
            do {
                let models = try await engine.getLocalModels()
                await MainActor.run {
                    self.localModels = models
                    self.isLoadingModels = false
                }
            } catch {
                print("❌ Failed to fetch Ollama models: \(error)")
                await MainActor.run {
                    self.isLoadingModels = false
                }
            }
        }
    }
}
