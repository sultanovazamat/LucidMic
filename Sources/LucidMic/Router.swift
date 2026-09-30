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

/// Streams a physical mic through RNNoise into the virtual mic, via a private aggregate device.
@MainActor
final class Router {
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var proc: AudioDeviceIOProcID?
    private var engine: OpaquePointer?

    func start(mic: AudioDevice, virtualMic: AudioDevice) throws {
        stop()
        let aggregate = try Self.createAggregate(micUID: mic.uid, virtualMicUID: virtualMic.uid)
        self.aggregate = aggregate
        AudioSystem.set(aggregate, kAudioDevicePropertyNominalSampleRate, Float64(48_000))  // RNNoise needs 48 kHz
        AudioSystem.set(aggregate, kAudioDevicePropertyBufferFrameSize, UInt32(480))

        // Aggregate buffer lists concatenate subdevice streams in order: mic first, then the virtual mic.
        let routing = LucidRouting(
            inputBuffer: 0, outputFirstBuffer: UInt32(mic.outputStreams),
            outputBufferCount: UInt32(virtualMic.outputStreams))
        engine = lucid_engine_create(routing)

        var newProc: AudioDeviceIOProcID?
        var status = lucid_engine_create_ioproc(aggregate, engine, &newProc)
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

    func stop() {
        if aggregate != kAudioObjectUnknown {
            if let proc {
                AudioDeviceStop(aggregate, proc)
                AudioDeviceDestroyIOProcID(aggregate, proc)
            }
            AudioHardwareDestroyAggregateDevice(aggregate)
        }
        if let engine { lucid_engine_destroy(engine) }
        aggregate = AudioObjectID(kAudioObjectUnknown)
        proc = nil
        engine = nil
    }

    /// Nonisolated on purpose: building a `[String: Any]` inside a @MainActor method crashes Swift 6.3's region analysis.
    nonisolated private static func createAggregate(micUID: String, virtualMicUID: String) throws -> AudioObjectID {
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "LucidMic Engine",
            kAudioAggregateDeviceUIDKey: "com.sultanovazamat.lucidmic.engine",
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceMainSubDeviceKey: micUID,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: micUID],
                [kAudioSubDeviceUIDKey: virtualMicUID, kAudioSubDeviceDriftCompensationKey: 1],
            ],
        ]
        var id = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &id)
        guard status == noErr else { throw RouterError.coreAudio("Creating the audio device", status) }
        return id
    }
}
