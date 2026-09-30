// lucidmic-file: runs any audio file through the same RNNoise engine the app uses.
// Usage: swift run -c release lucidmic-file <input audio> <output.wav>
import AVFoundation
import LucidEngine

let args = CommandLine.arguments
guard args.count == 3 else {
    print("usage: lucidmic-file <input audio> <output.wav>")
    exit(2)
}

let input = try AVAudioFile(forReading: URL(fileURLWithPath: args[1]))
let source = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: AVAudioFrameCount(input.length))!
try input.read(into: source)

// The engine works on 48 kHz mono.
let mono48k = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
let converter = AVAudioConverter(from: input.processingFormat, to: mono48k)!
let capacity = AVAudioFrameCount(Double(source.frameLength) * 48_000 / input.processingFormat.sampleRate) + 4_800
let noisy = AVAudioPCMBuffer(pcmFormat: mono48k, frameCapacity: capacity)!
var consumed = false
var conversionError: NSError?
converter.convert(to: noisy, error: &conversionError) { _, status in
    if consumed {
        status.pointee = .endOfStream
        return nil
    }
    consumed = true
    status.pointee = .haveData
    return source
}
if let conversionError { throw conversionError }

let clean = AVAudioPCMBuffer(pcmFormat: mono48k, frameCapacity: noisy.frameLength)!
clean.frameLength = noisy.frameLength
let engine = lucid_engine_create(LucidRouting(inputBuffer: 0, outputFirstBuffer: 0, outputBufferCount: 1))!
lucid_engine_process(engine, noisy.floatChannelData![0], clean.floatChannelData![0], noisy.frameLength)
lucid_engine_destroy(engine)

/// Scoped so the file is released, and its WAV header finalized, before the process exits.
func writeWAV(_ buffer: AVAudioPCMBuffer, to path: String) throws {
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
    ]
    let file = try AVAudioFile(
        forWriting: URL(fileURLWithPath: path), settings: settings, commonFormat: .pcmFormatFloat32,
        interleaved: false)
    try file.write(from: buffer)
}
try writeWAV(clean, to: args[2])
print("wrote \(args[2]) (\(String(format: "%.1f", Double(clean.frameLength) / 48_000)) s)")
