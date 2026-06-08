import AVFoundation
import Combine
import CoreAudio

final class AudioRecorder: ObservableObject {
    @Published var audioLevels: [Float] = Array(repeating: 0, count: 30)
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var error: String?
    @Published var isTooQuiet = false
    @Published var isTooNoisy = false
    @Published var isMicrophoneDenied = false
    private(set) var lastStopFailureMessage: String?

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var timer: Timer?
    private var startTime: Date?
    private let levelHistoryCount = 30
    private var recentLevels: [Float] = []
    private var smoothedDisplayLevel: Float = 0
    private var estimatedNoiseFloorDb: Float = -55
    private var recordingPeak: Float = 0
    private let minimumCapturedSignalPeak: Float = 0.0001
    
    // Lightweight monitor mode (for Settings live meter)
    private var monitorEngine: AVAudioEngine?
    @Published var isMonitoring = false

    var currentRecordingURL: URL? { recordingURL }

    @discardableResult
    func startRecording(inputDeviceID: String? = nil) -> Bool {
        // Stop monitor mode if active (avoid two engines on same mic)
        stopMonitoring()
        
        error = nil
        lastStopFailureMessage = nil
        isTooQuiet = false
        isTooNoisy = false
        isMicrophoneDenied = false
        recentLevels.removeAll()
        resetLevelTracking()
        
        // 1. Check Microphone Permissions
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            return proceedWithRecording(inputDeviceID: inputDeviceID)
        case .notDetermined:
            error = "Allow microphone access, then start recording again."
            return false
        case .denied, .restricted:
            handlePermissionDenied()
            return false
        @unknown default:
            handlePermissionDenied()
            return false
        }
    }

    private func handlePermissionDenied() {
        self.isMicrophoneDenied = true
        self.error = "Microphone access denied. Please enable it in System Settings → Privacy & Security."
    }

    private func proceedWithRecording(inputDeviceID: String?) -> Bool {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        if !configureInputDevice(inputDeviceID: inputDeviceID, inputNode: inputNode) {
            cleanupFailedStart(engine: engine, inputNode: inputNode, tapInstalled: false)
            return false
        }

        let inputFormat = inputNode.inputFormat(forBus: 0)
        let outputFormat = inputNode.outputFormat(forBus: 0)
        let recordingFormat = inputFormat
        print("whisper_debug: Input Node Format - Input: \(inputFormat), Output: \(outputFormat)")

        if recordingFormat.sampleRate == 0 || recordingFormat.channelCount == 0 {
            print("❌ Error: Input node has invalid hardware format: \(recordingFormat)")
            self.error = Self.inputUnavailableMessage
            cleanupFailedStart(engine: engine, inputNode: inputNode, tapInstalled: false)
            return false
        }

        // Create temp file for recording
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("whisperkiller_\(UUID().uuidString).wav")
        recordingURL = url

        // Processing format: 16kHz mono float32 (for real-time buffer conversion)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            self.error = "Failed to create audio format"
            cleanupFailedStart(engine: engine, inputNode: inputNode, tapInstalled: false)
            return false
        }

        guard let converter = AVAudioConverter(from: recordingFormat, to: targetFormat) else {
            print("❌ Error: Failed to create converter from \(recordingFormat) to \(targetFormat)")
            self.error = "Audio format mismatch: \(Int(recordingFormat.sampleRate))Hz to 16kHz"
            cleanupFailedStart(engine: engine, inputNode: inputNode, tapInstalled: false)
            return false
        }

        // File format: 16kHz mono 16-bit integer PCM (required by whisper-cli)
        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        do {
            audioFile = try AVAudioFile(forWriting: url, settings: fileSettings)
            print("whisper_debug: Audio file created at \(url.path)")
        } catch {
            self.error = "Failed to create audio file: \(error.localizedDescription)"
            cleanupFailedStart(engine: engine, inputNode: inputNode, tapInstalled: false)
            return false
        }

        var framesCaptured: Int64 = 0
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            framesCaptured += Int64(buffer.frameLength)
            if framesCaptured % 100 == 0 {
                print("whisper_debug: Captured \(framesCaptured) frames so far...")
            }

            // Calculate level for visualization
            let level = self.calculateLevel(buffer: buffer)
            
            // Deep diagnostics: Peak detection
            let channelData = buffer.floatChannelData?[0]
            let frames = Int(buffer.frameLength)
            var maxPeak: Float = 0
            for i in 0..<frames {
                maxPeak = max(maxPeak, abs(channelData?[i] ?? 0))
            }
            self.recordingPeak = max(self.recordingPeak, maxPeak)

            if framesCaptured % 100 == 0 {
                print("whisper_debug: Frames: \(framesCaptured), Peak: \(maxPeak), Level: \(level)")
                if maxPeak > 0.0001 {
                    print("whisper_debug: 🔊 SIGNAL DETECTED (via Peak)")
                }
            }
            
            DispatchQueue.main.async {
                self.audioLevels.append(level)
                if self.audioLevels.count > self.levelHistoryCount {
                    self.audioLevels.removeFirst()
                }
                
                // Quality alerts logic (sliding window)
                self.recentLevels.append(level)
                if self.recentLevels.count > 20 { self.recentLevels.removeFirst() }
                
                if self.recentLevels.count >= 10 {
                    let avg = self.recentLevels.reduce(0, +) / Float(self.recentLevels.count)
                    self.isTooQuiet = avg < 0.02
                    self.isTooNoisy = avg > 0.99
                }
            }

            // Convert and write to file
            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * targetFormat.sampleRate / recordingFormat.sampleRate
            )
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: frameCount
            ) else { return }

            var conversionError: NSError?
            let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if status == .haveData, let file = self.audioFile {
                do {
                    try file.write(from: convertedBuffer)
                } catch {
                    print("❌ Error writing to audio file: \(error)")
                }
            } else if status == .error {
                print("❌ Conversion error: \(conversionError?.localizedDescription ?? "Unknown")")
            }
        }

        do {
            engine.prepare()
            try engine.start()
            audioEngine = engine
            startTime = Date()
            isRecording = true
            print("whisper_debug: Audio engine started successfully. Input device enabled.")

            // Update duration timer
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self, let start = self.startTime else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
            return true
        } catch {
            print("whisper_debug: Failed to start audio engine: \(error)")
            self.error = "Failed to start recording: \(error.localizedDescription)"
            cleanupFailedStart(engine: engine, inputNode: inputNode, tapInstalled: true)
            return false
        }
    }

    private func configureInputDevice(inputDeviceID: String?, inputNode: AVAudioInputNode) -> Bool {
        let requestedDeviceID = inputDeviceID.flatMap { findDeviceID(uniqueID: $0) }
        if inputDeviceID != nil && requestedDeviceID == nil {
            print("whisper_debug: Selected input device is no longer available; falling back to system default")
        }

        guard let defaultDeviceID = Self.defaultInputDeviceID() else {
            error = "No system input microphone found. Check Sound Settings -> Input."
            return false
        }

        let primaryDeviceID = requestedDeviceID ?? defaultDeviceID
        if setInputDevice(primaryDeviceID, inputNode: inputNode) {
            return true
        }

        guard primaryDeviceID != defaultDeviceID else {
            error = Self.inputUnavailableMessage
            return false
        }

        print("whisper_debug: Falling back to system default input device after selected device failed")
        if setInputDevice(defaultDeviceID, inputNode: inputNode) {
            return true
        }

        error = Self.inputUnavailableMessage
        return false
    }

    private func setInputDevice(_ deviceID: AudioDeviceID, inputNode: AVAudioInputNode) -> Bool {
        guard Self.deviceHasInputChannels(deviceID) else {
            print("whisper_debug: CoreAudio device \(deviceID) has no input channels")
            return false
        }

        guard let audioUnit = inputNode.audioUnit else {
            print("whisper_debug: Input node has no audio unit")
            return false
        }

        var mutableDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status != noErr {
            print("whisper_debug: Failed to bind input device \(deviceID): \(status)")
            return false
        }

        print("whisper_debug: Bound input device \(deviceID) \(Self.deviceDebugDescription(deviceID))")
        return true
    }

    private func cleanupFailedStart(engine: AVAudioEngine, inputNode: AVAudioInputNode, tapInstalled: Bool) {
        if engine.isRunning {
            engine.stop()
        }
        if tapInstalled {
            inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        audioFile = nil
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        isRecording = false
        recordingDuration = 0
        audioLevels = Array(repeating: 0, count: levelHistoryCount)
        recentLevels.removeAll()
        resetLevelTracking()
    }

    func stopRecording() -> (URL?, TimeInterval) {
        lastStopFailureMessage = nil
        timer?.invalidate()
        timer = nil
        
        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
            engine.inputNode.removeTap(onBus: 0)
        }
        
        audioEngine = nil
        audioFile = nil
        isRecording = false

        let duration = recordingDuration
        let peak = recordingPeak
        recordingDuration = 0
        audioLevels = Array(repeating: 0, count: levelHistoryCount)
        isTooQuiet = false
        isTooNoisy = false
        recentLevels.removeAll()
        resetLevelTracking()

        // Return nil if recording was too short (< 0.3s)
        guard duration >= 0.3 else {
            print("whisper_debug: Recording too short (\(duration)s)")
            if let url = recordingURL {
                try? FileManager.default.removeItem(at: url)
            }
            return (nil, 0)
        }

        if let url = recordingURL {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = attributes?[.size] as? Int64 ?? 0
            print("whisper_debug: Recording stopped. File size: \(size) bytes, duration: \(duration)s")

            guard Self.hasReadableAudioFrames(at: url) else {
                print("whisper_debug: Recording file contains no readable audio frames")
                lastStopFailureMessage = Self.noMicrophoneInputMessage
                try? FileManager.default.removeItem(at: url)
                return (nil, 0)
            }

            guard peak >= minimumCapturedSignalPeak else {
                print("whisper_debug: Recording captured no input signal (peak: \(peak))")
                lastStopFailureMessage = Self.noMicrophoneInputMessage
                try? FileManager.default.removeItem(at: url)
                return (nil, 0)
            }
        }

        return (recordingURL, duration)
    }

    private static func hasReadableAudioFrames(at url: URL) -> Bool {
        guard let file = try? AVAudioFile(forReading: url) else { return false }
        return file.length > 0
    }

    private static let noMicrophoneInputMessage = "No microphone input detected. Check the selected microphone, microphone permission, or whether another app is using the input."

    // MARK: - Monitor Mode (lightweight, no file writing)
    
    func startMonitoring() {
        guard !isMonitoring && !isRecording else { return }
        
        // Ensure clean state
        stopMonitoring()
        
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        guard status == .authorized else {
            print("whisper_debug: Cannot monitor - mic not authorized (status: \(status.rawValue))")
            return
        }
        
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        guard format.sampleRate > 0 else {
            print("whisper_debug: Cannot monitor - invalid sample rate")
            return
        }
        
        print("whisper_debug: Starting monitor mode. Format: \(format)")
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            let level = self.calculateLevel(buffer: buffer)
            
            DispatchQueue.main.async {
                self.audioLevels.append(level)
                if self.audioLevels.count > self.levelHistoryCount {
                    self.audioLevels.removeFirst()
                }
                
                self.recentLevels.append(level)
                if self.recentLevels.count > 20 { self.recentLevels.removeFirst() }
                
                if self.recentLevels.count >= 10 {
                    let avg = self.recentLevels.reduce(0, +) / Float(self.recentLevels.count)
                    self.isTooQuiet = avg < 0.02
                    self.isTooNoisy = avg > 0.95
                }
            }
        }
        
        do {
            engine.prepare()
            try engine.start()
            
            DispatchQueue.main.async {
                self.monitorEngine = engine
                self.isMonitoring = true
                self.audioLevels = Array(repeating: 0, count: self.levelHistoryCount)
                self.recentLevels.removeAll()
                self.isTooQuiet = false
                self.isTooNoisy = false
                self.resetLevelTracking()
                print("whisper_debug: Monitor mode started successfully")
            }
        } catch {
            print("whisper_debug: Failed to start monitor: \(error)")
            inputNode.removeTap(onBus: 0)
        }
    }
    
    func stopMonitoring() {
        if let engine = monitorEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            monitorEngine = nil
        }
        
        if isMonitoring {
            DispatchQueue.main.async {
                self.isMonitoring = false
                self.audioLevels = Array(repeating: 0, count: self.levelHistoryCount)
                self.recentLevels.removeAll()
                self.isTooQuiet = false
                self.isTooNoisy = false
                self.resetLevelTracking()
                print("whisper_debug: Monitor mode stopped")
            }
        }
    }

    func cleanup() {
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
    }

    private func calculateLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        
        var sumSquares: Float = 0
        for i in 0..<frames {
            let sample = channelData[i]
            sumSquares += sample * sample
        }
        
        let rms = sqrt(sumSquares / Float(frames))
        let safeRms = max(rms, 1e-7)
        let levelDb = 20 * log10(safeRms)

        // Update the estimated noise floor only near the quiet end so speech does not
        // drag the baseline upward and compress the meter into saturation.
        let noiseTrackingThreshold = estimatedNoiseFloorDb + 8
        if levelDb < noiseTrackingThreshold {
            estimatedNoiseFloorDb = min(max((estimatedNoiseFloorDb * 0.92) + (levelDb * 0.08), -70), -38)
        }

        let gateDb = estimatedNoiseFloorDb + 6
        let speechCeilingDb: Float = -12
        let normalized = max(0, min((levelDb - gateDb) / (speechCeilingDb - gateDb), 1))
        let shapedLevel = sqrt(normalized)

        let smoothing: Float = shapedLevel > smoothedDisplayLevel ? 0.35 : 0.18
        smoothedDisplayLevel += (shapedLevel - smoothedDisplayLevel) * smoothing

        if smoothedDisplayLevel < 0.015 {
            smoothedDisplayLevel = 0
        }

        return smoothedDisplayLevel
    }

    private func resetLevelTracking() {
        smoothedDisplayLevel = 0
        estimatedNoiseFloorDb = -55
        recordingPeak = 0
    }

    private func findDeviceID(uniqueID: String) -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs)
        
        for id in deviceIDs {
            var namePropertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            var uid: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            AudioObjectGetPropertyData(id, &namePropertyAddress, 0, nil, &uidSize, &uid)
            
            if let uidString = uid?.takeRetainedValue() as String?, uidString == uniqueID {
                return id
            }
        }
        return nil
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        guard status == noErr, deviceID != AudioDeviceID(kAudioObjectUnknown) else {
            print("whisper_debug: Could not resolve system default input device: \(status)")
            return nil
        }

        return deviceID
    }

    private static func deviceHasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard sizeStatus == noErr, dataSize > 0 else { return false }

        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPointer.deallocate() }
        let bufferListPointer = rawPointer.bindMemory(to: AudioBufferList.self, capacity: 1)

        let dataStatus = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, bufferListPointer)
        guard dataStatus == noErr else { return false }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        return bufferList.contains { $0.mNumberChannels > 0 }
    }

    private static func deviceDebugDescription(_ deviceID: AudioDeviceID) -> String {
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var uid: Unmanaged<CFString>?
        var stringSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &stringSize, &name)
        stringSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &stringSize, &uid)

        let deviceName = name?.takeRetainedValue() as String? ?? "unknown"
        let deviceUID = uid?.takeRetainedValue() as String? ?? "unknown"
        return "(\(deviceName), uid: \(deviceUID))"
    }

    private static let inputUnavailableMessage = "Microphone input is unavailable. Check Sound Settings -> Input, microphone permission, or close apps that may be holding the device."
    
    deinit {
        _ = stopRecording()
        stopMonitoring()
    }
}
