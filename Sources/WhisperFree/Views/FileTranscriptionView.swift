import SwiftUI
import UniformTypeIdentifiers

struct FileTranscriptionView: View {
    @EnvironmentObject var appState: AppState
    @State private var isDragging = false
    @State private var showFilePicker = false
    @State private var result: String?
    @State private var progress: Float = 0
    @State private var isProcessing = false
    @State private var currentFileName: String?
    @State private var error: String?
    @State private var remainingTime: TimeInterval?

    private var timeRemainingString: String? {
        guard let remaining = remainingTime else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        
        if remaining < 1 {
            return "Finishing..."
        } else if remaining < 60 {
            return "About \(Int(remaining)) seconds remaining"
        } else {
            let minutes = Int(remaining / 60)
            let seconds = Int(remaining.truncatingRemainder(dividingBy: 60))
            return "About \(minutes)m \(seconds)s remaining"
        }
    }

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                mainContent
            }
        }
        .frame(minWidth: 420, minHeight: 480)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Spacer().frame(width: 80)
            }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text("File Transcription")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                
                if isProcessing {
                    Button("Cancel") {
                        // TODO: cancel support
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red.opacity(0.8))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // Configuration Bar
            HStack(spacing: 16) {
                // Mode Selection
                Menu {
                    ForEach(appState.settings.allModes) { mode in
                        Button {
                            appState.settings.selectedModeName = mode.name
                        } label: {
                            Label(mode.name, systemImage: mode.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        let mode = appState.settings.selectedMode
                        Image(systemName: mode.icon)
                        Text(mode.name)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // Language Selection
                Menu {
                    ForEach(AppSettings.supportedLanguages, id: \.code) { lang in
                        Button {
                            appState.settings.language = lang.code
                        } label: {
                            Text(lang.name)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        let currentLang = AppSettings.supportedLanguages.first { $0.code == appState.settings.language }?.name ?? "Auto"
                        Text(currentLang)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()

                // Engine info
                HStack(spacing: 4) {
                    Image(systemName: appState.settings.engineType == .cloud ? "cloud.fill" : "cpu")
                    Text(appState.settings.engineType == .cloud ? "Cloud" : "Local")
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary.opacity(0.8))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.02))

            Divider()

            if isProcessing {
                // Progress view
                VStack(spacing: 20) {
                    Spacer()
                    
                    VStack(spacing: 12) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .frame(width: 280)
                        
                        HStack {
                            if progress < 0.1 {
                                Text("Extracting audio...")
                            } else if progress < 0.15 {
                                Text("Initializing engine...")
                            } else {
                                Text("Transcribing...")
                            }
                            Spacer()
                            if let timeStr = timeRemainingString {
                                Text(timeStr)
                            }
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 280)
                    }
                    .padding(.bottom, 12)
                    
                    VStack(spacing: 8) {
                        Text(currentFileName ?? "Processing...")
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                        
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 42, weight: .bold, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                    
                    Spacer()
                }
                .padding(32)
                
            } else if let result = result {
                // Result view
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Transcription Complete")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Button {
                            self.result = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    ScrollView {
                        Text(result)
                            .font(.system(size: 13))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 220)
                    .padding(16)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    
                    HStack(spacing: 12) {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(result, forType: .string)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.on.doc.fill")
                                Text("Copy Result")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        
                        Button {
                            self.result = nil
                        } label: {
                            Text("New File")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
                .padding(24)
                
            } else {
                // Drop zone
                VStack(spacing: 12) {
                    Spacer().frame(height: 8)
                    
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                isDragging ? Color.accentColor : Color.secondary.opacity(0.3),
                                style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(isDragging ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
                            )
                        
                        VStack(spacing: 16) {
                            Image(systemName: "arrow.down.doc.fill")
                                .font(.system(size: 42))
                                .foregroundStyle(isDragging ? Color.accentColor : .secondary.opacity(0.7))
                                .padding(.bottom, 4)
                            
                            Text("Drop audio or video file here")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary.opacity(0.8))
                            
                            Text("MP3, WAV, M4A, MP4, MOV")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary.opacity(0.6))
                        }
                    }
                    .frame(height: 200)
                    .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
                        handleDrop(providers)
                    }
                    
                    // Browse button — uses SwiftUI .fileImporter (works in accessory apps)
                    Button {
                        showFilePicker = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                            Text("Browse Files...")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    
                    Spacer().frame(height: 12)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            
            // Error
            if let error = error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.08))
            }
        }
        .frame(minWidth: 380, minHeight: 320)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.audio, .video, .movie, .quickTimeMovie, .mpeg4Movie, .wav, .mp3, .aiff],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    startTranscription(url: url)
                }
            case .failure(let err):
                self.error = err.localizedDescription
            }
        }
    }
    
    // MARK: - Drop handling
    
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
            guard let data = data as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            
            DispatchQueue.main.async {
                startTranscription(url: url)
            }
        }
        return true
    }
    
    // MARK: - Transcription
    
    private func startTranscription(url: URL) {
        guard !isProcessing else { return }
        
        isProcessing = true
        progress = 0
        currentFileName = url.lastPathComponent
        error = nil
        result = nil
        
        let engine = TranscriptionEngineFactory.create(for: appState.settings.engineType, settings: appState.settings)
        
        Task {
            do {
                let text = try await engine.transcribe(
                    audioURL: url,
                    language: appState.settings.language == "auto" ? nil : appState.settings.language
                ) { p, rem in
                    Task { @MainActor in
                        self.progress = p
                        self.remainingTime = rem
                    }
                }
                
                await MainActor.run {
                    self.result = text
                    self.isProcessing = false
                    self.progress = 0
                    self.remainingTime = nil
                }

                // 2. Post-process / Diarize if needed
                var processedText = text
                var usage: UsageLog? = nil
                
                if appState.settings.enableSpeakerDiarization && appState.settings.postProcessingEngine == .openai {
                    do {
                        let processor = PostProcessor(settings: appState.settings)
                        let diarizationResult = try await processor.diarize(text: text)
                        processedText = diarizationResult.text
                        usage = UsageLog(
                            date: Date(),
                            modeName: "File Diarization",
                            engine: "OpenAI",
                            promptTokens: diarizationResult.promptTokens,
                            completionTokens: diarizationResult.completionTokens,
                            totalTokens: diarizationResult.promptTokens + diarizationResult.completionTokens,
                            estimatedCost: UsageLog.estimateCost(prompt: diarizationResult.promptTokens, completion: diarizationResult.completionTokens, engine: .openai)
                        )
                    } catch {
                        print("⚠️ File diarization failed: \(error)")
                    }
                }

                await MainActor.run {
                    self.result = processedText
                    
                    // Save to history
                    let entry = TranscriptionHistoryEntry(
                        rawText: text,
                        processedText: processedText,
                        modeName: appState.settings.enableSpeakerDiarization ? "Diarization" : "File Import",
                        duration: 0,
                        engineUsed: appState.settings.engineType.rawValue + (appState.settings.enableSpeakerDiarization ? " + AI" : ""),
                        usage: usage
                    )
                    Storage.shared.addTranscriptionHistoryEntry(entry)
                    appState.history.insert(entry, at: 0)
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isProcessing = false
                    self.progress = 0
                }
            }
        }
    }
}
