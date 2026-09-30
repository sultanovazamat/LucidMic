import AVFoundation
import Foundation
import LucidEngine
import LucidFileProcessing
import Testing

@Suite @MainActor
struct AudioFileProcessorTests {
    private let modelPath = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("build/deps/dpdfnet2_48khz_hr.onnx").path

    @Test(arguments: [0, 1])
    func bothStereoChannelsContributeToMono(activeChannel: Int) throws {
        let signal = (0..<997).map { Float(sin(Double($0) * 0.07)) * 0.5 }
        var channels = [[Float]](repeating: [Float](repeating: 0, count: signal.count), count: 2)
        channels[activeChannel] = signal
        try withAudioFile(channels: channels) { path in
            let mono = try AudioFileProcessor.readMono48k(path)
            #expect(mono.frameLength == signal.count)
            let data = try #require(mono.floatChannelData?[0])
            let error = signal.indices.map { abs(data[$0] - signal[$0] / 2) }.max() ?? 0
            #expect(error < 1e-6)
        }
    }

    @Test func identicalStereoChannelsKeepTheirLevel() throws {
        let signal = [Float](repeating: 0.75, count: 1001)
        try withAudioFile(channels: [signal, signal]) { path in
            let mono = try AudioFileProcessor.readMono48k(path)
            let data = try #require(mono.floatChannelData?[0])
            #expect((0..<Int(mono.frameLength)).allSatisfy { abs(data[$0] - 0.75) < 1e-6 })
        }
    }

    @Test func fileReadIncludesTheFinalPartialBlock() throws {
        let signal = (0..<48_013).map { Float(sin(Double($0) * 0.07)) * 0.5 }
        try withAudioFile(channels: [signal]) { path in
            let mono = try AudioFileProcessor.readMono48k(path)
            #expect(mono.frameLength == signal.count)
            let data = try #require(mono.floatChannelData?[0])
            if mono.frameLength == signal.count {
                #expect(signal.indices.allSatisfy { abs(data[$0] - signal[$0]) < 1e-6 })
            }
        }
    }

    @Test(arguments: [0, 1, 127, 44_101], [16_000.0, 44_100.0, 96_000.0])
    func resamplingPreservesDuration(frameCount: Int, sampleRate: Double) throws {
        try withAudioFile(channels: [[Float](repeating: 0.5, count: frameCount)], sampleRate: sampleRate) { path in
            let mono = try AudioFileProcessor.readMono48k(path)
            #expect(mono.format.sampleRate == 48_000)
            #expect(mono.format.channelCount == 1)
            let durationError = abs(Double(mono.frameLength) / 48_000 - Double(frameCount) / sampleRate)
            #expect(durationError <= 1.0 / 48_000)
        }
    }

    @Test(arguments: [
        0, 1, 127, 479, 481, Int(lucid_engine_latency_frames()) - 1, Int(lucid_engine_latency_frames()) + 1, 48_013,
    ])
    func bypassPreservesEveryFrameIncludingTheEnd(frameCount: Int) throws {
        let signal = (0..<frameCount).map { Float(sin(Double($0) * 0.07)) * 0.5 + 0.1 }
        let source = try makeMono(signal)
        let engine = try makeEngine(bypass: true)
        defer { lucid_engine_destroy(engine) }

        let result = try AudioFileProcessor.process(source, engine: engine)
        #expect(result.frameLength == source.frameLength)
        let data = try #require(result.floatChannelData?[0])
        let maxError = signal.indices.map { abs(data[$0] - signal[$0]) }.max() ?? 0
        #expect(maxError < 1e-6)
    }

    @Test func contentOnlyAtEndSurvivesLatencyTrimming() throws {
        var signal = [Float](repeating: 0, count: 48_013)
        for index in (signal.count - 479)..<signal.count {
            signal[index] = Float(sin(Double(index) * 0.07)) * 0.5 + 0.1
        }
        let source = try makeMono(signal)
        let engine = try makeEngine(bypass: true)
        defer { lucid_engine_destroy(engine) }
        let result = try AudioFileProcessor.process(source, engine: engine)
        let data = try #require(result.floatChannelData?[0])
        #expect(signal.indices.allSatisfy { abs(data[$0] - signal[$0]) < 1e-6 })
    }

    @Test func emptyWAVCanBeReadProcessedAndWritten() throws {
        try withAudioFile(channels: [[]]) { path in
            let source = try AudioFileProcessor.readMono48k(path)
            #expect(source.frameLength == 0)
            let engine = try makeEngine(bypass: false)
            defer { lucid_engine_destroy(engine) }
            let result = try AudioFileProcessor.process(source, engine: engine)
            let output = path + ".wav"
            try AudioFileProcessor.writeWAV(result, to: output)
            #expect(try AVAudioFile(forReading: URL(fileURLWithPath: output)).length == 0)
        }
    }

    private func makeEngine(bypass: Bool) throws -> OpaquePointer {
        var routing = LucidRouting()
        routing.outputBufferCount = 1
        let engine = try #require(lucid_engine_create(routing, modelPath))
        lucid_engine_set_bypass(engine, bypass)
        return engine
    }

    private func makeMono(_ samples: [Float]) throws -> AVAudioPCMBuffer {
        let format = try #require(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false))
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1, samples.count))))
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let data = try #require(buffer.floatChannelData?[0])
        for index in samples.indices { data[index] = samples[index] }
        return buffer
    }

    private func withAudioFile(channels: [[Float]], sampleRate: Double = 48_000, body: (String) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("input.caf")
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                channels: AVAudioChannelCount(channels.count), interleaved: false))
        let frameCount = channels[0].count
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1, frameCount))))
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let data = try #require(buffer.floatChannelData)
        for channel in channels.indices {
            for index in channels[channel].indices { data[channel][index] = channels[channel][index] }
        }
        do {
            var settings = format.settings
            settings[AVLinearPCMIsNonInterleaved] = false
            let file = try AVAudioFile(forWriting: path, settings: settings)
            if frameCount > 0 { try file.write(from: buffer) }
        }
        try body(path.path)
    }
}
