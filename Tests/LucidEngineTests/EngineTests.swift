import Foundation
import LucidEngine
import Testing

private func process(_ input: [Float], block: Int) -> [Float] {
    let engine = lucid_engine_create(LucidRouting(inputBuffer: 0, outputFirstBuffer: 0, outputBufferCount: 1))!
    defer { lucid_engine_destroy(engine) }
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

    @Test func runsFarFasterThanRealTime() {
        let input = noise(seconds: 10, amplitude: 0.05)
        let started = Date()
        _ = process(input, block: 480)
        #expect(Date().timeIntervalSince(started) < 1.0)  // 10 s of audio in under 1 s
    }

    @Test func latencyIsOneRNNoiseFrame() {
        #expect(lucid_engine_latency_frames() == 480)
    }
}
