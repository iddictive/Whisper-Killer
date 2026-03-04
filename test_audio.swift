import Foundation
import AVFoundation

let inputURL = URL(fileURLWithPath: "test.m4a")
// Let's create a dummy m4a first
let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
let file = try! AVAudioFile(forWriting: inputURL, settings: format.settings)
let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100)!
buffer.frameLength = 44100
for i in 0..<Int(buffer.frameLength) { buffer.floatChannelData![0][i] = 0 }
try! file.write(from: buffer)

// Now test the converter loop
let outputURL = URL(fileURLWithPath: "test_out.wav")
let inputFile = try! AVAudioFile(forReading: inputURL)
let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
let converter = AVAudioConverter(from: inputFile.processingFormat, to: targetFormat)!

let outputFile = try! AVAudioFile(forWriting: outputURL, settings: targetFormat.settings)

let bufferSize: AVAudioFrameCount = 4096
while true {
    let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFile.processingFormat, frameCapacity: bufferSize)!
    do {
        try inputFile.read(into: inputBuffer)
    } catch {
        break
    }
    
    if inputBuffer.frameLength == 0 { break }
    
    let ratio = targetFormat.sampleRate / inputFile.processingFormat.sampleRate
    let outputFrameCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 1
    let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity)!
    
    var convError: NSError?
    converter.convert(to: outputBuffer, error: &convError) { _, outStatus in
        outStatus.pointee = .haveData
        return inputBuffer
    }
    print("Converted \(outputBuffer.frameLength) frames")
    if convError != nil { break }
    
    // ExtAudioFileWrite crashes here
    try! outputFile.write(from: outputBuffer)
}
print("Success")
