import Foundation
import AVFoundation

func convertTo16kHzWav(inputURL: URL, outputURL: URL) async throws {
    let asset = AVURLAsset(url: inputURL)
    guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return }
    
    let reader = try AVAssetReader(asset: asset)
    let outputSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false
    ]
    let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
    reader.add(trackOutput)
    
    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .wav)
    let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
    writerInput.expectsMediaDataInRealTime = false
    writer.add(writerInput)
    
    reader.startReading()
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    
    let group = DispatchGroup()
    group.enter()
    
    writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "audioConvert")) {
        while writerInput.isReadyForMoreMediaData {
            if let buffer = trackOutput.copyNextSampleBuffer() {
                writerInput.append(buffer)
            } else {
                writerInput.markAsFinished()
                group.leave()
                break
            }
        }
    }
    
    group.wait()
    await writer.finishWriting()
}

Task {
    // Generate 1 second of silence
    let url = URL(fileURLWithPath: "test.m4a")
    let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100)!
    buffer.frameLength = 44100
    for i in 0..<Int(buffer.frameLength) { buffer.floatChannelData![0][i] = 0.0 }
    try file.write(from: buffer)
    
    let outURL = URL(fileURLWithPath: "test_out2.wav")
    try? FileManager.default.removeItem(at: outURL)
    
    try await convertTo16kHzWav(inputURL: url, outputURL: outURL)
    print("Success. Saved to \(outURL.path)")
    exit(0)
}
RunLoop.main.run()
