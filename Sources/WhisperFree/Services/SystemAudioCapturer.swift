import Foundation
import ScreenCaptureKit
@preconcurrency import AVFoundation

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
        guard sampleBuffer.isValid, let data = Self.makePCM16Mono16kData(from: sampleBuffer) else { return }

        Task { @MainActor in
            audioCallback(data)
        }
    }

    private nonisolated static func makePCM16Mono16kData(from sampleBuffer: CMSampleBuffer) -> Data? {
        guard let description = sampleBuffer.formatDescription?.audioStreamBasicDescription,
              let inputFormat = AVAudioFormat(
                standardFormatWithSampleRate: description.mSampleRate,
                channels: description.mChannelsPerFrame
              ),
              let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
              )
        else {
            return nil
        }

        var convertedData: Data?

        try? sampleBuffer.withAudioBufferList { audioBufferList, _ in
            guard let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: inputFormat,
                bufferListNoCopy: audioBufferList.unsafePointer
            ) else {
                return
            }

            let outputBuffer: AVAudioPCMBuffer?
            if inputBuffer.format == targetFormat {
                outputBuffer = inputBuffer
            } else {
                outputBuffer = convert(buffer: inputBuffer, to: targetFormat)
            }

            guard let outputBuffer,
                  let channelData = outputBuffer.int16ChannelData
            else {
                return
            }

            let frameCount = Int(outputBuffer.frameLength)
            let bytesPerFrame = Int(targetFormat.streamDescription.pointee.mBytesPerFrame)
            convertedData = Data(bytes: channelData[0], count: frameCount * bytesPerFrame)
        }

        return convertedData
    }

    private nonisolated static func convert(buffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else {
            return nil
        }

        let sendableBuffer = SendablePCMBuffer(buffer)

        let frameRatio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputCapacity = max(AVAudioFrameCount((Double(buffer.frameLength) * frameRatio).rounded(.up)), 1)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else {
            return nil
        }

        var conversionError: NSError?
        var providedInput = false
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if providedInput {
                outStatus.pointee = .endOfStream
                return nil
            }

            providedInput = true
            outStatus.pointee = .haveData
            return sendableBuffer.buffer
        }

        guard conversionError == nil else { return nil }

        switch status {
        case .haveData, .inputRanDry, .endOfStream:
            return outputBuffer
        case .error:
            return nil
        @unknown default:
            return nil
        }
    }
}

private final class SendablePCMBuffer: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}
