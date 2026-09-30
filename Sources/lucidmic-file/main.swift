// lucidmic-file: runs any audio file through the same DPDFNet engine the app uses.
// Usage: swift run -c release lucidmic-file <input audio> <output.wav> [model.onnx]
@preconcurrency import AVFoundation
import Foundation
import LucidEngine

let mono48k = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!

/// Reads any audio file and converts it to 48 kHz mono, the engine's format.
@MainActor
func readMono48k(_ path: String) throws -> AVAudioPCMBuffer {
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: source)
    let converter = AVAudioConverter(from: file.processingFormat, to: mono48k)!
    let capacity = AVAudioFrameCount(Double(source.frameLength) * 48_000 / file.processingFormat.sampleRate) + 4_800
    let result = AVAudioPCMBuffer(pcmFormat: mono48k, frameCapacity: capacity)!
    // The converter calls this block synchronously; the box only satisfies the @Sendable signature.
    final class Once: @unchecked Sendable { var given = false }
    let once = Once()
    var error: NSError?
    converter.convert(to: result, error: &error) { _, status in
        if once.given {
            status.pointee = .endOfStream
            return nil
        }
        once.given = true
        status.pointee = .haveData
        return source
    }
    if let error { throw error }
    return result
}

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

@MainActor
func run() throws -> Int32 {
    let args = CommandLine.arguments
    guard args.count == 3 || args.count == 4 else {
        print("usage: lucidmic-file <input audio> <output.wav> [model.onnx]")
        return 2
    }
    let modelPath =
        args.count == 4 ? args[3] : FileManager.default.currentDirectoryPath + "/build/deps/dpdfnet2_48khz_hr.onnx"
    let routing = LucidRouting(inputBuffer: 0, outputFirstBuffer: 0, outputBufferCount: 1)
    guard let engine = lucid_engine_create(routing, modelPath) else {
        print("could not load model at \(modelPath)")
        return 1
    }
    defer { lucid_engine_destroy(engine) }

    let noisy = try readMono48k(args[1])
    let clean = AVAudioPCMBuffer(pcmFormat: mono48k, frameCapacity: noisy.frameLength)!
    clean.frameLength = noisy.frameLength
    lucid_engine_process(engine, noisy.floatChannelData![0], clean.floatChannelData![0], noisy.frameLength)
    try writeWAV(clean, to: args[2])
    print("wrote \(args[2]) (\(String(format: "%.1f", Double(clean.frameLength) / 48_000)) s)")
    return 0
}

exit(try run())
