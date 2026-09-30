import CoreAudio
import Foundation
import LucidEngine

enum RouterError: LocalizedError {
    case coreAudio(String, OSStatus)
    var errorDescription: String? {
        switch self {
        case .coreAudio(let what, let status): "\(what) failed (\(status))"
        }
    }
}

/// Streams a physical mic through DPDFNet into LucidMic Feed (heard on LucidMic Microphone), via a private aggregate.
@MainActor
final class Router {
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var proc: AudioDeviceIOProcID?
    private var engine: OpaquePointer?

    func start(mic: AudioDevice, feed: AudioDevice, modelPath: String) throws {
        stop()
        let aggregate = try Self.createAggregate(micUID: mic.uid, feedUID: feed.uid)
        self.aggregate = aggregate
        AudioSystem.set(aggregate, kAudioDevicePropertyNominalSampleRate, Float64(48_000))  // the model runs at 48 kHz
        AudioSystem.set(aggregate, kAudioDevicePropertyBufferFrameSize, UInt32(480))

        // Aggregate buffer lists concatenate subdevice streams in order: mic first, then the feed.
        let routing = LucidRouting(
            inputBuffer: 0, outputFirstBuffer: UInt32(mic.outputStreams), outputBufferCount: UInt32(feed.outputStreams))
        guard let engine = lucid_engine_create(routing, modelPath) else {
            stop()
            throw RouterError.coreAudio("Loading the noise-removal model", -1)
        }
        self.engine = engine

        var newProc: AudioDeviceIOProcID?
        var status = lucid_engine_start_live(engine, aggregate, &newProc)
        guard status == noErr, let newProc else {
            stop()
            throw RouterError.coreAudio("Creating the audio callback", status)
        }
        proc = newProc
        status = AudioDeviceStart(aggregate, newProc)
        guard status == noErr else {
            stop()
            throw RouterError.coreAudio("Starting audio", status)
        }
    }

    /// Noise removal on/off while audio keeps flowing (click-free; same latency either way).
    func setCleaning(_ cleaning: Bool) {
        if let engine { lucid_engine_set_bypass(engine, !cleaning) }
    }

    func stop() {
        if aggregate != kAudioObjectUnknown {
            if let proc {
                AudioDeviceStop(aggregate, proc)
                AudioDeviceDestroyIOProcID(aggregate, proc)
            }
            AudioHardwareDestroyAggregateDevice(aggregate)
        }
        if let engine { lucid_engine_destroy(engine) }  // also stops the model's worker thread
        aggregate = AudioObjectID(kAudioObjectUnknown)
        proc = nil
        engine = nil
    }

    /// Nonisolated on purpose: building a `[String: Any]` inside a @MainActor method crashes Swift 6.3's region analysis.
    nonisolated private static func createAggregate(micUID: String, feedUID: String) throws -> AudioObjectID {
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "LucidMic Engine",
            kAudioAggregateDeviceUIDKey: "com.sultanovazamat.lucidmic.engine",
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceMainSubDeviceKey: micUID,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: micUID],
                [kAudioSubDeviceUIDKey: feedUID, kAudioSubDeviceDriftCompensationKey: 1],
            ],
        ]
        var id = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &id)
        guard status == noErr else { throw RouterError.coreAudio("Creating the audio device", status) }
        return id
    }
}
