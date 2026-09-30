import CoreAudio
import Foundation
import LucidEngine
import Testing

/// DPDFNet model fetched by scripts/fetch-deps.sh.
private let modelPath = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("build/deps/dpdfnet2_48khz_hr.onnx").path

private func process(_ input: [Float], block: Int, bypass: Bool = false) -> [Float] {
    let routing = LucidRouting(inputBuffer: 0, outputFirstBuffer: 0, outputBufferCount: 1)
    guard let engine = lucid_engine_create(routing, modelPath) else {
        Issue.record("model not found at \(modelPath) — run scripts/fetch-deps.sh")
        return []
    }
    defer { lucid_engine_destroy(engine) }
    lucid_engine_set_bypass(engine, bypass)
    var output = [Float](repeating: 0, count: input.count)
    var start = 0
    while start < input.count {
        let n = min(block, input.count - start)
        input.withUnsafeBufferPointer { inBuf in
            output.withUnsafeMutableBufferPointer { outBuf in
                lucid_engine_process(engine, inBuf.baseAddress! + start, outBuf.baseAddress! + start, UInt32(n))
            }
        }
        start += n
    }
    return output
}

private func rms(_ x: ArraySlice<Float>) -> Float {
    (x.reduce(0) { $0 + $1 * $1 } / Float(max(x.count, 1))).squareRoot()
}

private func noise(seconds: Double, amplitude: Float) -> [Float] {
    var rng = SystemRandomNumberGenerator()
    return (0..<Int(seconds * 48_000)).map { _ in Float.random(in: -amplitude...amplitude, using: &rng) }
}

@Suite struct EngineTests {
    @Test func silenceStaysSilent() {
        let out = process([Float](repeating: 0, count: 48_000), block: 480)
        #expect(rms(out[...]) < 1e-4)
    }

    @Test func steadyNoiseIsSuppressedByAtLeast10dB() {
        let input = noise(seconds: 3, amplitude: 0.05)
        let out = process(input, block: 480)
        let tail = 48_000...  // let the model settle for 1 s
        let reductionDB = 20 * log10(rms(input[tail]) / max(rms(out[tail]), 1e-9))
        #expect(reductionDB > 10, "reduction was \(reductionDB) dB")
    }

    @Test func outputDoesNotDependOnIOBufferSize() {
        let input = noise(seconds: 1, amplitude: 0.05)
        let reference = process(input, block: 480)
        for block in [64, 127, 512, 4096] {
            #expect(process(input, block: block) == reference, "block \(block)")
        }
    }

    @Test func runsAtLeastTwiceAsFastAsRealTime() {
        let input = noise(seconds: 10, amplitude: 0.05)
        let started = Date()
        _ = process(input, block: 480)
        #expect(Date().timeIntervalSince(started) < 5.0)  // measured ≈ 1.8 s on an M3 Pro
    }

    @Test func latencyIsSeventyMilliseconds() {
        #expect(lucid_engine_latency_frames() == 3360)  // 40 ms model + 30 ms hand-off buffer
    }

    @Test func switchedOffPassesAudioThroughUnchangedWithTheSameDelay() {
        let input = noise(seconds: 1, amplitude: 0.05)
        let out = process(input, block: 256, bypass: true)
        let delay = Int(lucid_engine_latency_frames())
        // The first produced chunk ramps from denoised to original; compare after it.
        let maxError = (960..<(input.count - delay)).map { abs(out[$0 + delay] - input[$0]) }.max() ?? 1
        #expect(maxError < 1e-6)
    }

    /// Drives the real IOProc with 10 ms buffers, like Core Audio does, while the worker thread runs the model.
    @Test func liveModeMatchesOfflineOutputWithoutDropouts() throws {
        let input = noise(seconds: 1, amplitude: 0.05)
        let reference = process(input, block: 480)
        let routing = LucidRouting(inputBuffer: 0, outputFirstBuffer: 0, outputBufferCount: 1)
        let engine = try #require(lucid_engine_create(routing, modelPath))
        defer { lucid_engine_destroy(engine) }
        #expect(lucid_engine_start_worker(engine))

        let frames = 480
        let inList = AudioBufferList.allocate(maximumBuffers: 1)
        let outList = AudioBufferList.allocate(maximumBuffers: 1)
        let inData = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        let outData = UnsafeMutablePointer<Float>.allocate(capacity: frames * 2)  // stereo feed
        defer {
            inData.deallocate()
            outData.deallocate()
            free(inList.unsafeMutablePointer)
            free(outList.unsafeMutablePointer)
        }
        inList[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: inData)
        outList[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(frames * 8), mData: outData)

        var live = [Float]()
        var time = AudioTimeStamp()
        for start in stride(from: 0, to: input.count, by: frames) {
            for i in 0..<frames { inData[i] = input[start + i] }
            _ = lucid_engine_ioproc(
                0, &time, inList.unsafePointer, &time, outList.unsafeMutablePointer, &time,
                UnsafeMutableRawPointer(engine))
            live += (0..<frames).map { outData[$0 * 2] }
            #expect(outData[1] == outData[0])  // both feed channels carry the voice
            Thread.sleep(forTimeInterval: 0.01)  // real time: one IO cycle per 10 ms
        }
        #expect(lucid_engine_underruns(engine) == 0)
        #expect(live == reference)
    }
}
