import Foundation
import Combine
import AVFoundation

struct LiveTranscriptSegment: Identifiable, Equatable, Sendable {
    let id: UUID
    var originalText: String
    var translatedText: String
}

@MainActor
final class LiveTranslatorManager: ObservableObject, @unchecked Sendable {
    static let shared = LiveTranslatorManager()

    @Published var isRunning: Bool = false
    @Published var originalText: String = ""
    @Published var translatedText: String = ""
    @Published var statusMessage: String?
    @Published var transcriptSegments: [LiveTranscriptSegment] = []
    
    private var translationTask: Task<Void, Never>?
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    
    private let localEngine = LocalTranslationEngine()
    private var rawStreamBuffer: String = ""
    private var lastSentText: String = ""
    
    private var translationDebounceTimer: AnyCancellable?
    private var isStoppingProcess = false
    
    // Silence detection
    @Published var isSilence: Bool = false
    private var silenceTimer: Timer?
    
    // SCK Support
    private var isUsingSCK = false
    private var sckAudioBuffer = Data()
    private let maxBufferSize = 16000 * 2 * 15 // 15 seconds max
    private var isTranscribingSCK = false
    private var transcriptionTask: Task<Void, Never>?
    
    private var settingsSubscription: AnyCancellable?
    
    private init() {
        settingsSubscription = NotificationCenter.default.publisher(for: NSNotification.Name("LiveTranslatorSettingsChanged"))
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.applyCurrentSettings()
                }
            }
    }
    
    private func applyCurrentSettings() {
        guard AppState.liveTranslatorFeatureAvailable else {
            if isRunning {
                stop()
            }
            return
        }

        guard isRunning else { return }
        // For now, we simple restart to pick up new language/model
        stop()
        start()
    }

    private func failToStart(with message: String) {
        statusMessage = message
        isRunning = false
        NotificationCenter.default.post(name: .liveTranslatorDidFailToStart, object: message)
        NotificationCenter.default.post(name: .liveTranslatorDidStop, object: nil)
    }
    
    func start() {
        guard AppState.liveTranslatorFeatureAvailable else {
            statusMessage = nil
            NotificationCenter.default.post(name: .liveTranslatorDidStop, object: nil)
            return
        }

        guard !isRunning else { return }
        isStoppingProcess = false
        
        let currentSettings = Storage.shared.loadSettings()
        let targetLanguage = AppSettings.normalizedLiveTranslatorTargetLanguage(currentSettings.liveTranslatorTargetLanguage)
        let sourceLanguage = AppSettings.normalizedLiveTranslatorSourceLanguageCode(currentSettings.liveTranslatorSourceLanguage)
        let engineChoice = currentSettings.liveTranslatorEngine
        let localModel = currentSettings.liveTranslatorLocalModel
        
        // 1. Validate Model
        let modelSize = currentSettings.localModelSize
        guard let modelURL = AppState.shared.modelManager.findModelPath(for: modelSize) else {
            failToStart(with: "Whisper model '\(modelSize.rawValue)' not found. Please download it in Engine settings.")
            return
        }
        if modelSize.forcesEnglishDecoding && sourceLanguage != "en" {
            failToStart(with: "The selected Whisper model only supports English. Choose a multilingual local model for Live Translator.")
            return
        }
        let modelPath = modelURL.path
        
        // 2. SCK vs Device Index
        if currentSettings.useScreenCaptureKit {
            startSystemAudioCapture()
            return
        }

        let binaryPath = "/opt/homebrew/bin/whisper-stream"
        guard FileManager.default.fileExists(atPath: binaryPath) else {
            failToStart(with: "whisper-stream not found. Please run 'brew install whisper-cpp'.")
            return
        }
        
        // 3. Setup Process
        process = Process()
        process?.executableURL = URL(fileURLWithPath: binaryPath)
        process?.terminationHandler = { [weak self] terminatedProcess in
            Task { @MainActor in
                self?.handleProcessTermination(terminatedProcess)
            }
        }
        
        let deviceID = getCaptureDeviceIndex(for: currentSettings.liveTranslatorInputDeviceID)
        print("whisper_debug: Starting whisper-stream with device index \(deviceID) and model \(modelPath)")
        
        process?.arguments = [
            "-m", modelPath,
            "-t", "\(max(1, ProcessInfo.processInfo.activeProcessorCount - 2))",
            "--step", "3000",
            "--length", "10000",
            "--keep", "200",
            "-vth", "0.6",
            "-l", sourceLanguage,
            "-c", "\(deviceID)"
        ]
        
        outputPipe = Pipe()
        errorPipe = Pipe()
        process?.standardOutput = outputPipe
        process?.standardError = errorPipe
        
        // 4. Read Output
        outputPipe?.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self = self else { return }
            
            if let output = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    self.processOutput(output, targetLanguage: targetLanguage, sourceLanguage: sourceLanguage, engine: engineChoice, localModel: localModel)
                }
            }
        }

        errorPipe?.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
            print("whisper_debug: stream stderr: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        
        do {
            try process?.run()
            isRunning = true
            originalText = ""
            translatedText = ""
            transcriptSegments = []
            rawStreamBuffer = ""
            statusMessage = "Listening..."
            resetSilenceTimer()
            NotificationCenter.default.post(name: .liveTranslatorDidStart, object: nil)
        } catch {
            failToStart(with: "Failed to start stream: \(error.localizedDescription)")
        }
    }

    private func startSystemAudioCapture() {
        statusMessage = "Starting system audio capture..."
        originalText = ""
        translatedText = ""
        transcriptSegments = []
        rawStreamBuffer = ""
        lastSentText = ""
        sckAudioBuffer.removeAll(keepingCapacity: true)
        translationTask?.cancel()
        transcriptionTask?.cancel()

        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await SystemAudioCapturer.shared.startCapture { [weak self] data in
                    self?.handleSCKBuffer(data)
                }

                self.isUsingSCK = true
                self.isRunning = true
                self.isTranscribingSCK = false
                self.statusMessage = "Listening..."
                self.resetSilenceTimer()
                self.startSCKTranscriptionLoop()
                NotificationCenter.default.post(name: .liveTranslatorDidStart, object: nil)
            } catch {
                self.isUsingSCK = false
                self.isTranscribingSCK = false
                self.failToStart(with: "Failed to start system audio capture: \(error.localizedDescription)")
            }
        }
    }
    
    func stop() {
        print("🛑 LiveTranslatorManager: Stopping...")
        
        if isUsingSCK {
            Task {
                await SystemAudioCapturer.shared.stopCapture()
            }
        }
        
        isStoppingProcess = true
        if let process = process, process.isRunning {
            process.terminate()
            process.waitUntilExit() // Ensure it's really gone
            print("✅ whisper-stream process terminated")
        }
        process = nil
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe = nil
        
        transcriptionTask?.cancel()
        transcriptionTask = nil
        
        isRunning = false
        statusMessage = nil
        originalText = ""
        translatedText = ""
        transcriptSegments = []
        rawStreamBuffer = ""
        lastSentText = ""
        translationTask?.cancel()
        translationDebounceTimer?.cancel()
        silenceTimer?.invalidate()
        isUsingSCK = false
        isTranscribingSCK = false
        isStoppingProcess = false
        
        NotificationCenter.default.post(name: .liveTranslatorDidStop, object: nil)
    }
    
    deinit {
        // Can't call async stop() directly in deinit, but we can terminate the process synchronously
        if let process = process, process.isRunning {
            process.terminate()
        }
    }
    
    private func processOutput(_ text: String, targetLanguage: String, sourceLanguage: String, engine: LiveTranslationEngine, localModel: String) {
        rawStreamBuffer += text
        
        // 1. Prevent buffer from growing indefinitely (Memory safety)
        if rawStreamBuffer.count > 10000 {
            rawStreamBuffer = String(rawStreamBuffer.suffix(5000))
        }
        
        let segments = rawStreamBuffer.components(separatedBy: "\n")
        var finalLines: [String] = []
        
        for segment in segments {
            if let lastCR = segment.lastIndex(of: "\r") {
                let afterCR = segment[segment.index(after: lastCR)...]
                finalLines.append(String(afterCR))
            } else {
                finalLines.append(segment)
            }
        }
        
        // Keep only the last 2-3 visible lines to avoid massive text build-up
        let recentLines = Array(finalLines.suffix(3))
        
        let cleanedLines = recentLines.map { cleanLine($0) }.filter { !$0.isEmpty }
        let fullText = canonicalLiveText(from: cleanedLines)
        
        // 2. Artifact/Silence filtering (Whisper often hallucinates during silence)
        guard !fullText.isEmpty else { return }
        if fullText.count < 3 && !fullText.contains(where: { $0.isLetter }) { return } // Filter out things like "." or "!!!"
        
        if fullText == originalText { return }
        
        resetSilenceTimer()
        originalText = mergedWithLatestSegment(fullText) ?? fullText
        
        triggerTranslation(targetLanguage: targetLanguage, sourceLanguage: sourceLanguage, engine: engine, localModel: localModel)
    }

    private func handleProcessTermination(_ terminatedProcess: Process) {
        guard process === terminatedProcess else {
            isStoppingProcess = false
            return
        }

        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe = nil
        process = nil

        if isStoppingProcess || !isRunning {
            isStoppingProcess = false
            return
        }

        isRunning = false
        originalText = ""
        translatedText = ""
        transcriptSegments = []
        rawStreamBuffer = ""
        lastSentText = ""
        translationTask?.cancel()
        translationDebounceTimer?.cancel()
        silenceTimer?.invalidate()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        isUsingSCK = false
        isTranscribingSCK = false
        isStoppingProcess = false

        let terminationStatus = terminatedProcess.terminationStatus
        if terminationStatus == 0 {
            statusMessage = nil
        } else {
            statusMessage = "whisper-stream exited with code \(terminationStatus)."
        }

        NotificationCenter.default.post(name: .liveTranslatorDidStop, object: nil)
    }
    
    /// Helper to convert a CoreMedia uniqueID string into an integer index for `whisper-stream`
    private func getCaptureDeviceIndex(for uniqueID: String?) -> Int {
        guard let uniqueID = uniqueID else { return -1 } // Default
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        // Devices are typically ordered by the system.
        // `whisper-stream` expects an integer ID matching the SDL audio list.
        if let index = session.devices.firstIndex(where: { $0.uniqueID == uniqueID }) {
            return index
        }
        return -1
    }
    
    private func cleanLine(_ text: String) -> String {
        // Strip out ANSI escape codes
        let regex = try! NSRegularExpression(pattern: "\u{001B}\\[[0-9;]*[a-zA-Z]", options: .caseInsensitive)
        let range = NSRange(location: 0, length: text.utf16.count)
        var cleaned = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")

        let metadataPatterns = [
            #"init:[^\n]*"#,
            #"samples\s+per\s+frame:[^\n]*"#,
            #"main:[^\n]*"#,
            #"whisper_print_progress_callback:\s*progress\s*=\s*\d+%"#,
            #"whisper_print_timings:[^\n]*"#,
            #"whisper_full_with_state:[^\n]*"#,
            #"whisper_(?:init|model_load|backend_init)[^\n]*"#,
            #"ggml_[^\n]*"#,
            #"system_info:[^\n]*"#
        ]

        for pattern in metadataPatterns {
            cleaned = cleaned.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }

        let hallucinationPatterns = [
            #"(?i)\bDimaTorzok\b"#,
            #"(?i)\bsubtitles?\s+by[^\n.!?]*[.!?]?"#,
            #"(?i)\btranslated\s+by[^\n.!?]*[.!?]?"#,
            #"(?i)\bedited\s+by[^\n.!?]*[.!?]?"#,
            #"(?i)\bto\s+be\s+continued[^\n.!?]*[.!?]?"#,
            #"(?i)thank\s+you\s+for\s+watching[^\n.!?]*[.!?]?"#,
            #"(?i)субтитры\s+(?:сделал|сделала|сделали|создал|создала|создали|создавал|подготовил|подготовила|подготовили)[^\n.!?]*[.!?]?"#,
            #"(?i)перев[её]л[^\n.!?]*[.!?]?"#,
            #"(?i)отредактировал[^\n.!?]*[.!?]?"#,
            #"(?i)продолжение\s+следует[^\n.!?]*[.!?]?"#,
            #"(?i)подпишитесь\s+на\s+канал[^\n.!?]*[.!?]?"#
        ]

        for pattern in hallucinationPatterns {
            cleaned = cleaned.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }

        let normalizedAfterHallucinationCleanup = cleaned
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        if normalizedAfterHallucinationCleanup == "тревожная музыка" ||
            normalizedAfterHallucinationCleanup == "music" {
            return ""
        }
        
        // Remove timestamps e.g. [00:00:00.000 --> 00:00:02.000]
        let timestampRegex = try! NSRegularExpression(pattern: "\\[[0-9:.]* --> [0-9:.]*\\]", options: .caseInsensitive)
        let tsRange = NSRange(location: 0, length: cleaned.utf16.count)
        cleaned = timestampRegex.stringByReplacingMatches(in: cleaned, options: [], range: tsRange, withTemplate: "")
        
        // Strip [Start speaking], [Silence] etc
        if cleaned.contains("[Start speaking]") || 
           cleaned.contains("[Silence]") || 
           cleaned.contains("[_") ||
           cleaned.contains("(music)") || 
           cleaned.contains("(engine humming)") ||
           cleaned.lowercased().contains("thank you for watching") { // Common hallucinations
            return ""
        }
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func triggerTranslation(targetLanguage: String, sourceLanguage: String, engine: LiveTranslationEngine, localModel: String) {
        translationDebounceTimer?.cancel()
        
        let textToTranslate = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textToTranslate.isEmpty, textToTranslate != lastSentText else { return }
        
        translationDebounceTimer = Just(())
            .delay(for: .milliseconds(500), scheduler: RunLoop.main) // Reduced from 800ms for better responsiveness
            .sink { [weak self] in
                guard let self = self else { return }
                self.performTranslation(text: textToTranslate, targetLanguage: targetLanguage, sourceLanguage: sourceLanguage, engine: engine, localModel: localModel)
            }
    }
    
    private func performTranslation(text: String, targetLanguage: String, sourceLanguage: String, engine: LiveTranslationEngine, localModel: String) {
        lastSentText = text
        statusMessage = "Translating..."
        
        translationTask?.cancel()
        translationTask = Task {
            do {
                let translationResult: String
                
                if AppSettings.liveTranslatorSourceMatchesTarget(sourceLanguageCode: sourceLanguage, targetLanguage: targetLanguage) {
                    translationResult = text
                } else if engine == .local {
                    translationResult = try await self.localEngine.translate(text: text, targetLanguage: targetLanguage, model: localModel)
                } else {
                    let settings = Storage.shared.loadSettings()
                    let processor = PostProcessor(settings: settings)
                    
                    // Temp fake mode to force system prompt
                    let translateMode = TranscriptionMode(
                        name: "Translate", icon: "", description: "", exampleInput: "", exampleOutput: "",
                        systemPrompt: "You are a real-time translator. Translate the given text to \(targetLanguage). Provide ONLY the translation. No quotes, no markdown.",
                        isBuiltIn: false
                    )
                    
                    let result = try await processor.process(text: text, mode: translateMode)
                    translationResult = result.text
                }
                
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    self.translatedText = translationResult
                    self.upsertTranscriptSegment(original: text, translated: translationResult)
                    self.statusMessage = "Listening..."
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.statusMessage = "Translation error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func resetSilenceTimer() {
        isSilence = false
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.isSilence = true
                self?.rawStreamBuffer = ""
                self?.originalText = ""
                self?.translatedText = ""
                self?.lastSentText = ""
            }
        }
    }

    private func upsertTranscriptSegment(original: String, translated: String) {
        let original = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let translated = translated.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !original.isEmpty, !translated.isEmpty else { return }

        if let lastIndex = transcriptSegments.indices.last {
            let lastSegment = transcriptSegments[lastIndex]

            if lastSegment.originalText == original {
                if lastSegment.translatedText != translated {
                    transcriptSegments[lastIndex].translatedText = translated
                }
                return
            }

            if let mergedOriginal = mergeOverlappingText(previous: lastSegment.originalText, incoming: original) {
                let mergedTranslated = mergeOverlappingText(previous: lastSegment.translatedText, incoming: translated) ?? translated
                transcriptSegments[lastIndex].originalText = mergedOriginal
                transcriptSegments[lastIndex].translatedText = mergedTranslated
                return
            }
        }

        transcriptSegments.append(
            LiveTranscriptSegment(
                id: UUID(),
                originalText: original,
                translatedText: translated
            )
        )
    }

    private func canonicalLiveText(from lines: [String]) -> String {
        lines.reduce("") { current, line in
            guard !current.isEmpty else { return line }
            return mergeOverlappingText(previous: current, incoming: line) ?? "\(current) \(line)"
        }
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func mergedWithLatestSegment(_ text: String) -> String? {
        guard let latest = transcriptSegments.last else { return nil }
        return mergeOverlappingText(previous: latest.originalText, incoming: text)
    }

    private func mergeOverlappingText(previous: String, incoming: String) -> String? {
        let previous = previous.trimmingCharacters(in: .whitespacesAndNewlines)
        let incoming = incoming.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !previous.isEmpty, !incoming.isEmpty else { return nil }
        if previous == incoming { return previous }

        let previousNormalized = normalizedSpeechText(previous)
        let incomingNormalized = normalizedSpeechText(incoming)

        guard !previousNormalized.isEmpty, !incomingNormalized.isEmpty else { return nil }
        if previousNormalized == incomingNormalized { return previous.count >= incoming.count ? previous : incoming }
        if incomingNormalized.hasPrefix(previousNormalized) { return incoming }
        if previousNormalized.hasPrefix(incomingNormalized) { return previous }
        if incomingNormalized.contains(previousNormalized) { return incoming }
        if previousNormalized.contains(incomingNormalized) { return previous }

        let previousWords = normalizedSpeechWords(previous)
        let incomingWords = normalizedSpeechWords(incoming)
        let overlap = longestWordOverlap(left: previousWords, right: incomingWords)
        if overlap >= 3 {
            let incomingOriginalWords = incoming.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            let remainder = incomingOriginalWords.dropFirst(overlap).joined(separator: " ")
            guard !remainder.isEmpty else { return previous }

            return "\(previous) \(remainder)"
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let fuzzyMerge = mergeByCommonPhrase(previous: previous, incoming: incoming, previousWords: previousWords, incomingWords: incomingWords) {
            return fuzzyMerge
        }

        return nil
    }

    private func longestWordOverlap(left: [String], right: [String]) -> Int {
        guard !left.isEmpty, !right.isEmpty else { return 0 }

        let maxCandidate = min(left.count, right.count)
        for count in stride(from: maxCandidate, through: 1, by: -1) {
            if Array(left.suffix(count)) == Array(right.prefix(count)) {
                return count
            }
        }

        return 0
    }

    private func normalizedSpeechText(_ text: String) -> String {
        normalizedSpeechWords(text).joined(separator: " ")
    }

    private func mergeByCommonPhrase(previous: String, incoming: String, previousWords: [String], incomingWords: [String]) -> String? {
        guard let match = longestCommonPhrase(left: previousWords, right: incomingWords), match.count >= 3 else {
            return nil
        }

        let previousOriginalWords = previous.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let incomingOriginalWords = incoming.split(whereSeparator: { $0.isWhitespace }).map(String.init)

        if match.rightStart == 0 {
            let remainder = incomingOriginalWords.dropFirst(match.count).joined(separator: " ")
            guard !remainder.isEmpty else { return previous }
            return "\(previous) \(remainder)"
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if match.leftStart == 0 && incomingOriginalWords.count > previousOriginalWords.count {
            return incoming
        }

        let remainder = incomingOriginalWords.dropFirst(match.rightStart + match.count).joined(separator: " ")
        guard !remainder.isEmpty else { return previous }

        return "\(previous) \(remainder)"
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func longestCommonPhrase(left: [String], right: [String]) -> (leftStart: Int, rightStart: Int, count: Int)? {
        guard !left.isEmpty, !right.isEmpty else { return nil }

        var best: (leftStart: Int, rightStart: Int, count: Int)?
        for leftStart in left.indices {
            for rightStart in right.indices {
                var count = 0
                while leftStart + count < left.count,
                      rightStart + count < right.count,
                      left[leftStart + count] == right[rightStart + count] {
                    count += 1
                }

                if count > (best?.count ?? 0) {
                    best = (leftStart, rightStart, count)
                }
            }
        }

        return best
    }

    private func normalizedSpeechWords(_ text: String) -> [String] {
        text
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map { token in
                token.filter { $0.isLetter || $0.isNumber }
            }
            .filter { !$0.isEmpty }
    }

    // MARK: - SCK Audio Logic
    
    private func handleSCKBuffer(_ data: Data) {
        let length = data.count
        
        // Diagnostic: Check if audio is non-silent
        let samples = data.withUnsafeBytes { $0.bindMemory(to: Int16.self) }
        var maxVal: Int16 = 0
        for sample in samples {
            maxVal = max(maxVal, abs(sample))
        }
        
        if Int.random(in: 0...500) == 0 {
            print("🎙️ SCK Diagnostic: Buffer received, length: \(length), max amplitude: \(maxVal)")
            if maxVal > 100 {
                print("🔊 SCK: SOUND DETECTED!")
            } else if maxVal > 0 {
                print("🔈 SCK: Very quiet or silence...")
            } else {
                print("😶 SCK: Absolute zero (check permissions!)")
            }
        }
        
        DispatchQueue.main.async {
            self.sckAudioBuffer.append(data)
            
            // Keep buffer within limits (15s)
            if self.sckAudioBuffer.count > self.maxBufferSize {
                self.sckAudioBuffer.removeFirst(self.sckAudioBuffer.count - self.maxBufferSize)
            }
        }
    }
    
    private func startSCKTranscriptionLoop() {
        transcriptionTask?.cancel()
        transcriptionTask = Task {
            while !Task.isCancelled && isRunning {
                // Wait for some audio to accumulate
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                
                guard !isTranscribingSCK, sckAudioBuffer.count > 16000 * 2 else { continue }
                
                await transcribeCurrentSCKBuffer()
            }
        }
    }
    
    private func transcribeCurrentSCKBuffer() async {
        isTranscribingSCK = true
        
        let audioToProcess = sckAudioBuffer
        sckAudioBuffer.removeAll(keepingCapacity: true)
        // We write to a temp file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("sck_chunk_\(UUID().uuidString).wav")
        
        // Whisper CLI needs a WAV header. We use AVAudioFile to write it correctly.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        do {
            let audioFile = try AVAudioFile(forWriting: tempURL, settings: settings)
            let format = AVAudioFormat(settings: settings)!
            let frameCount = AVAudioFrameCount(audioToProcess.count / 2)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
            buffer.frameLength = frameCount
            
            audioToProcess.withUnsafeBytes { pointer in
                let src = pointer.bindMemory(to: Int16.self).baseAddress!
                let dst = buffer.int16ChannelData![0]
                memcpy(dst, src, audioToProcess.count)
            }
            
            try audioFile.write(from: buffer)
            
            // Now transcribe
            let modelSize = Storage.shared.loadSettings().localModelSize
            let settings = Storage.shared.loadSettings()
            let sourceLanguage = AppSettings.normalizedLiveTranslatorSourceLanguageCode(settings.liveTranslatorSourceLanguage)
            let whisper = LocalWhisper(modelSize: modelSize)
            
            print("🎙️ SCK: Transcribing \(audioToProcess.count) bytes...")
            let text = try await whisper.transcribe(audioURL: tempURL, language: sourceLanguage, timeRange: nil, onProgress: nil)
            
            if !text.isEmpty {
                await MainActor.run {
                    self.originalText = text
                    self.triggerTranslation(
                        targetLanguage: AppSettings.normalizedLiveTranslatorTargetLanguage(settings.liveTranslatorTargetLanguage),
                        sourceLanguage: sourceLanguage,
                        engine: settings.liveTranslatorEngine,
                        localModel: settings.liveTranslatorLocalModel
                    )
                }
            }
            
            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            print("❌ SCK Transcription Error: \(error)")
        }
        
        isTranscribingSCK = false
    }
}
