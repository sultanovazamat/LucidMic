@preconcurrency import AVFoundation
import Foundation
import LucidEngine

@MainActor
public enum AudioFileProcessor {
    private static let mono48k = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!

    /// Average all source channels explicitly, then resample the mono signal.
    public static func readMono48k(_ path: String) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(
            forReading: URL(fileURLWithPath: path), commonFormat: .pcmFormatFloat32, interleaved: false)
        guard file.length >= 0, file.length <= Int64(UInt32.max) else { throw Failure.fileTooLarge }
        let source = try buffer(format: file.processingFormat, capacity: AVAudioFrameCount(file.length))
        if file.length > 0 {
            let chunk = try buffer(format: file.processingFormat, capacity: min(4096, AVAudioFrameCount(file.length)))
            while source.frameLength < file.length {
                try file.read(
                    into: chunk,
                    frameCount: min(chunk.frameCapacity, AVAudioFrameCount(file.length) - source.frameLength))
                guard chunk.frameLength > 0 else { throw Failure.conversionFailed }
                for channel in 0..<Int(source.format.channelCount) {
                    source.floatChannelData![channel].advanced(by: Int(source.frameLength)).update(
                        from: chunk.floatChannelData![channel], count: Int(chunk.frameLength))
                }
                source.frameLength += chunk.frameLength
            }
        }
        guard let sourceChannels = source.floatChannelData,
            let monoFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: source.format.sampleRate,
                channels: 1, interleaved: false), source.format.channelCount > 0
        else { throw Failure.invalidFormat }
        let mono = try buffer(format: monoFormat, capacity: source.frameLength)
        mono.frameLength = source.frameLength
        let destination = mono.floatChannelData![0]
        for frame in 0..<Int(source.frameLength) {
            var sample: Float = 0
            for channel in 0..<Int(source.format.channelCount) { sample += sourceChannels[channel][frame] }
            destination[frame] = sample / Float(source.format.channelCount)
        }
        if source.format.sampleRate == 48_000 { return mono }
        let frameCount = ceil(Double(source.frameLength) * 48_000 / source.format.sampleRate)
        guard frameCount.isFinite, frameCount <= Double(UInt32.max) else { throw Failure.fileTooLarge }
        let result = try buffer(format: mono48k, capacity: AVAudioFrameCount(frameCount))
        if source.frameLength == 0 { return result }
        guard let converter = AVAudioConverter(from: monoFormat, to: mono48k) else { throw Failure.invalidFormat }
        // AVAudioConverter invokes this block synchronously; the box tracks the single input buffer.
        final class Once: @unchecked Sendable { var given = false }
        let once = Once()
        var error: NSError?
        let status = converter.convert(to: result, error: &error) { _, status in
            if once.given {
                status.pointee = .endOfStream
                return nil
            }
            once.given = true
            status.pointee = .haveData
            return mono
        }
        if let error { throw error }
        if status == .error { throw Failure.conversionFailed }
        return result
    }

    /// Consume a fresh offline engine, flush its delayed output, and preserve the source duration.
    public static func process(_ noisy: AVAudioPCMBuffer, engine: OpaquePointer) throws -> AVAudioPCMBuffer {
        guard noisy.format == mono48k else { throw Failure.invalidFormat }
        let clean = try buffer(format: mono48k, capacity: noisy.frameLength)
        clean.frameLength = noisy.frameLength
        let count = Int(noisy.frameLength)
        if count == 0 { return clean }
        let source = noisy.floatChannelData![0]
        let destination = clean.floatChannelData![0]
        let delay = Int(lucid_engine_latency_frames())
        let blockSize = 4096
        var input = [Float](repeating: 0, count: blockSize)
        var output = [Float](repeating: 0, count: blockSize)
        for offset in stride(from: 0, to: count + delay, by: blockSize) {
            let frames = min(blockSize, count + delay - offset)
            for index in 0..<frames { input[index] = offset + index < count ? source[offset + index] : 0 }
            lucid_engine_process(engine, &input, &output, UInt32(frames))
            let start = max(offset, delay)
            let end = min(offset + frames, count + delay)
            if start < end {
                for index in start..<end { destination[index - delay] = output[index - offset] }
            }
        }
        return clean
    }

    public static func writeWAV(_ buffer: AVAudioPCMBuffer, to path: String) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ]
        let file = try AVAudioFile(
            forWriting: URL(fileURLWithPath: path), settings: settings, commonFormat: .pcmFormatFloat32,
            interleaved: false)
        if buffer.frameLength > 0 { try file.write(from: buffer) }
    }

    private static func buffer(format: AVAudioFormat, capacity: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(1, capacity)) else {
            throw Failure.allocationFailed
        }
        return buffer
    }

    private enum Failure: LocalizedError {
        case invalidFormat, fileTooLarge, allocationFailed, conversionFailed

        var errorDescription: String? {
            switch self {
            case .invalidFormat: "The audio format cannot be converted to 48 kHz mono."
            case .fileTooLarge: "The audio file is too large to process in memory."
            case .allocationFailed: "There is not enough memory to process the audio file."
            case .conversionFailed: "The audio conversion did not finish successfully."
            }
        }
    }
}
