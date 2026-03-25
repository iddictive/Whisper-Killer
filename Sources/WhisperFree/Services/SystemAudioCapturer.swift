import Foundation
import ScreenCaptureKit
import AVFoundation

@MainActor
final class SystemAudioCapturer: NSObject, @unchecked Sendable {
    static let shared = SystemAudioCapturer()
    
    private var stream: SCStream?
    private var isCapturing = false
    
    // Buffer for whisper-stream or other consumers
    private let lock = NSLock()
    nonisolated(unsafe) private var _audioCallback: (@MainActor @Sendable (Data) -> Void)?
    
    nonisolated private var audioCallback: (@MainActor @Sendable (Data) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _audioCallback
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _audioCallback = newValue
        }
    }
    
    private override init() {
        super.init()
    }
    
    func startCapture(callback: @MainActor @Sendable @escaping (Data) -> Void) async throws {
        guard !isCapturing else { return }
        self.audioCallback = callback
        
        // 1. Get Shareable Content
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw NSError(domain: "SystemAudioCapturer", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display found for capture"])
        }
        
        // 2. Create Content Filter (System Audio only)
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        
        // 3. Configure Stream (Audio only)
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 16000 // Whisper likes 16kHz
        config.channelCount = 1
        
        // Minimal visual impact
        config.width = 2
        config.height = 2
        
        // 4. Initialize Stream
        stream = SCStream(filter: filter, configuration: config, delegate: nil)
        
        // 5. Add Audio Output
        try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
        
        // 6. Start
        try await stream?.startCapture()
        isCapturing = true
        print("🎙️ SCK: System Audio capture started")
    }
    
    func stopCapture() async {
        guard isCapturing else { return }
        try? await stream?.stopCapture()
        stream = nil
        isCapturing = false
        audioCallback = nil
        print("🛑 SCK: System Audio capture stopped")
    }
    
}

extension SystemAudioCapturer: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let audioCallback = self.audioCallback else { return }
        
        // Extract PCM data synchronously from the background thread
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        let length = CMBlockBufferGetDataLength(blockBuffer)
        
        var data = Data(count: length)
        data.withUnsafeMutableBytes { (pointer: UnsafeMutableRawBufferPointer) in
            _ = CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: pointer.baseAddress!)
        }
        
        // Now it's safe to pass a copy to the main actor
        Task { @MainActor in
            audioCallback(data)
        }
    }
}
