import CoreAudio
import Foundation
import LucidEngine
import LucidEngineTestSupport
import Testing

private let recoveryModelPath = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("build/deps/dpdfnet2_48khz_hr.onnx").path

/// Exercises the actual callback and worker with a deterministic scheduling order.
private final class LiveHarness {
    let engine: OpaquePointer
    let frames: Int
    let channels: Int
    private let input: UnsafeMutablePointer<Float>
    private let output: UnsafeMutablePointer<Float>
    private let inputList = AudioBufferList.allocate(maximumBuffers: 1)
    private let outputList = AudioBufferList.allocate(maximumBuffers: 1)
    private var sample = 0
    var sampleCount: Int { sample }

    init(
        frames: Int = 480, channels: Int = 1, inputBuffer: UInt32 = 0, inputChannel: UInt32 = 0,
        bypass: Bool = true
    ) throws {
        self.frames = frames
        self.channels = channels
        let routing = LucidRouting(
            inputBuffer: inputBuffer, inputChannel: inputChannel, outputFirstBuffer: 0, outputBufferCount: 1)
        engine = try #require(lucid_engine_create(routing, recoveryModelPath))
        lucid_engine_set_bypass(engine, bypass)
        input = .allocate(capacity: frames * channels)
        output = .allocate(capacity: frames * 2)
        input.initialize(repeating: 0, count: frames * channels)
        output.initialize(repeating: 0, count: frames * 2)
    }

    deinit {
        lucid_engine_destroy(engine)
        input.deallocate()
        output.deallocate()
        free(inputList.unsafeMutablePointer)
        free(outputList.unsafeMutablePointer)
    }

    static func signal(_ index: Int) -> Float { Float(index + 1) / 1_000_000 }

    func callback(inputEnabled: Bool = true, outputEnabled: Bool = true) -> [Float] {
        for i in 0..<frames {
            for channel in 0..<channels {
                input[i * channels + channel] = channel == channels - 1 ? Self.signal(sample + i) : -0.25
            }
        }
        inputList[0] = AudioBuffer(
            mNumberChannels: UInt32(channels), mDataByteSize: UInt32(frames * channels * 4),
            mData: inputEnabled ? input : nil)
        outputList[0] = AudioBuffer(
            mNumberChannels: 2, mDataByteSize: UInt32(frames * 2 * 4), mData: outputEnabled ? output : nil)
        var time = AudioTimeStamp()
        _ = lucid_engine_ioproc(
            0, &time, inputList.unsafePointer, &time, outputList.unsafeMutablePointer, &time,
            UnsafeMutableRawPointer(engine))
        sample += frames
        return outputEnabled ? (0..<frames).map { output[$0 * 2] } : []
    }

    func runWorker() { lucid_test_worker_cycle(engine) }

    func healthyCycle() -> [Float] {
        let result = callback()
        runWorker()
        return result
    }

    func expectCurrentDelay() {
        let result = healthyCycle()
        let start = sample - frames - Int(lucid_engine_latency_frames())
        let expected = (0..<frames).map { Self.signal(start + $0) }
        let correctDelay = result == expected
        #expect(correctDelay, "Audio must return to the declared latency instead of replaying stale input")
    }
}

@Suite struct LiveRecoveryTests {
    @Test func disabledInputProducesSilenceWithoutCrashing() throws {
        let harness = try LiveHarness()
        for _ in 0..<20 {
            #expect(harness.callback(inputEnabled: false).allSatisfy { $0 == 0 })
            harness.runWorker()
        }
    }

    @Test func disabledOutputDoesNotCrash() throws {
        let harness = try LiveHarness()
        for _ in 0..<20 {
            _ = harness.callback(outputEnabled: false)
            harness.runWorker()
        }
        harness.expectCurrentDelay()
    }

    @Test func disabledInputPreservesTheTimelineWhenReenabled() throws {
        let harness = try LiveHarness()
        for _ in 0..<20 { _ = harness.healthyCycle() }
        let disabledStart = harness.sampleCount
        var actual = [Float]()
        for _ in 0..<3 {
            actual += harness.callback(inputEnabled: false)
            harness.runWorker()
        }
        let disabledEnd = harness.sampleCount
        for _ in 0..<20 { actual += harness.healthyCycle() }
        let expected = (0..<actual.count).map { offset in
            let inputSample = disabledStart + offset - Int(lucid_engine_latency_frames())
            return (disabledStart..<disabledEnd).contains(inputSample) ? 0 : LiveHarness.signal(inputSample)
        }
        let preservesTimeline = actual == expected
        #expect(preservesTimeline, "Disabled input should occupy its original sample positions as silence")
    }

    @Test(arguments: [1, 64, 127, 256, 480, 481, 511, 512])
    func supportedLiveBuffersHaveMeasuredDeclaredDelay(frames: Int) throws {
        let harness = try LiveHarness(frames: frames)
        for _ in 0..<max(100, 9_600 / frames) { _ = harness.healthyCycle() }
        harness.expectCurrentDelay()
        #expect(lucid_engine_underruns(harness.engine) == 0)
    }

    @Test(arguments: [64, 127, 480, 512])
    func workerStallRecoversToOriginalLatency(frames: Int) throws {
        let harness = try LiveHarness(frames: frames)
        for _ in 0..<(9_600 / frames) { _ = harness.healthyCycle() }
        for _ in 0..<(4_800 / frames) { _ = harness.callback() }
        for _ in 0..<(14_400 / frames) { _ = harness.healthyCycle() }
        #expect(lucid_engine_underruns(harness.engine) > 0)
        harness.expectCurrentDelay()
    }

    @Test func fullInputQueueRecoversToOriginalLatency() throws {
        let harness = try LiveHarness()
        for _ in 0..<20 { _ = harness.healthyCycle() }
        lucid_test_fill_input(harness.engine)
        for _ in 0..<50 { _ = harness.healthyCycle() }
        harness.expectCurrentDelay()
    }

    @Test func fullOutputQueueRecoversToOriginalLatency() throws {
        let harness = try LiveHarness()
        for _ in 0..<20 { _ = harness.healthyCycle() }
        lucid_test_fill_input(harness.engine)
        lucid_test_fill_output(harness.engine)
        harness.runWorker()
        for _ in 0..<50 { _ = harness.healthyCycle() }
        harness.expectCurrentDelay()
    }

    @Test func oversizedLiveBufferProducesSilence() throws {
        let harness = try LiveHarness(frames: 2048)
        for _ in 0..<15 { #expect(harness.healthyCycle().allSatisfy { $0 == 0 }) }
    }

    @Test func selectedInputChannelIsUsed() throws {
        let harness = try LiveHarness(channels: 2, inputChannel: 1)
        for _ in 0..<20 { _ = harness.healthyCycle() }
        harness.expectCurrentDelay()
    }

    @Test func missingInputChannelProducesSilence() throws {
        let harness = try LiveHarness(channels: 2, inputChannel: 2)
        for _ in 0..<20 { #expect(harness.healthyCycle().allSatisfy { $0 == 0 }) }
    }

    @Test func missingInputBufferProducesSilence() throws {
        let harness = try LiveHarness(inputBuffer: 1)
        for _ in 0..<20 { #expect(harness.healthyCycle().allSatisfy { $0 == 0 }) }
    }

    @Test func zeroChannelInputProducesSilence() throws {
        let harness = try LiveHarness(channels: 0)
        for _ in 0..<20 { #expect(harness.healthyCycle().allSatisfy { $0 == 0 }) }
    }

    @Test func recoveryResetsDenoiserStateAsWellAsQueues() throws {
        let harness = try LiveHarness(bypass: false)
        for _ in 0..<20 { _ = harness.healthyCycle() }
        for _ in 0..<10 { _ = harness.callback() }
        harness.runWorker()  // Complete the reset before the next callback resumes capture.

        let routing = LucidRouting(inputBuffer: 0, inputChannel: 0, outputFirstBuffer: 0, outputBufferCount: 1)
        let fresh = try #require(lucid_engine_create(routing, recoveryModelPath))
        defer { lucid_engine_destroy(fresh) }
        let firstSample = harness.sampleCount
        let input = (0..<9_600).map { LiveHarness.signal(firstSample + $0) }
        var expected = [Float](repeating: 0, count: input.count)
        input.withUnsafeBufferPointer { source in
            expected.withUnsafeMutableBufferPointer { destination in
                lucid_engine_process(fresh, source.baseAddress!, destination.baseAddress!, UInt32(input.count))
            }
        }
        let actual = (0..<20).flatMap { _ in harness.healthyCycle() }
        let matchesFreshModel = actual == expected
        #expect(matchesFreshModel, "Recovery must clear inference state, history, and queued output")
    }
}
