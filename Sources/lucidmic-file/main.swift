// lucidmic-file: runs any audio file through the same DPDFNet engine the app uses.
// Usage: swift run -c release lucidmic-file <input audio> <output.wav> [model.onnx]
import Foundation
import LucidEngine
import LucidFileProcessing

@MainActor
func run() throws -> Int32 {
    let args = CommandLine.arguments
    guard args.count == 3 || args.count == 4 else {
        print("usage: lucidmic-file <input audio> <output.wav> [model.onnx]")
        return 2
    }
    let modelPath =
        args.count == 4 ? args[3] : FileManager.default.currentDirectoryPath + "/build/deps/dpdfnet2_48khz_hr.onnx"
    var routing = LucidRouting()
    routing.outputBufferCount = 1
    guard let engine = lucid_engine_create(routing, modelPath) else {
        print("could not load model at \(modelPath)")
        return 1
    }
    defer { lucid_engine_destroy(engine) }

    let noisy = try AudioFileProcessor.readMono48k(args[1])
    let clean = try AudioFileProcessor.process(noisy, engine: engine)
    try AudioFileProcessor.writeWAV(clean, to: args[2])
    print("wrote \(args[2]) (\(String(format: "%.1f", Double(clean.frameLength) / 48_000)) s)")
    return 0
}

exit(try run())
