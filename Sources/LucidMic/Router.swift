import CoreAudio
import Foundation
import LucidEngine

enum RouterError: LocalizedError {
    case coreAudio(String, OSStatus)
    case configuration(String)

    var errorDescription: String? {
        switch self {
        case .coreAudio(let what, let status): "\(what) failed (\(status))"
        case .configuration(let detail): detail
        }
    }
}

@MainActor
protocol AudioRouting: AnyObject {
    var onFailure: ((String) -> Void)? { get set }
    func start(mic: AudioDevice, feed: AudioDevice, channel: Int, modelPath: String) async throws
    func setCleaning(_ cleaning: Bool)
    func stop()
}

/// Streams a selected physical input into LucidMic Feed through a private aggregate.
@MainActor
final class Router: AudioRouting {
    var onFailure: ((String) -> Void)?
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var proc: AudioDeviceIOProcID?
    private var engine: OpaquePointer?
    private var listeners: [AudioPropertyListener] = []
    private var source: AudioDevice?
    private var feed: AudioDevice?
    private var inputLayout: [Int] = []
    private var outputLayout: [Int] = []
    private var generation = 0
    private var reportedFailure = false

    func start(mic: AudioDevice, feed: AudioDevice, channel: Int, modelPath: String) async throws {
        stop()
        let generation = self.generation
        guard mic.isPhysicalInput, let location = mic.inputLocation(channel: channel) else {
            throw RouterError.configuration(
                "The selected microphone channel is unavailable. Choose another input in Settings.")
        }
        do {
            let aggregate = try Self.createAggregate(micUID: mic.uid, feedUID: feed.uid)
            self.aggregate = aggregate
            try await AudioConfiguration.setAndConfirm(
                "The 48 kHz sample rate", value: Float64(48_000),
                read: { try AudioSystem.read(aggregate, kAudioDevicePropertyNominalSampleRate) },
                write: { try AudioSystem.set(aggregate, kAudioDevicePropertyNominalSampleRate, $0) })
            let currentFrames: UInt32 = try AudioSystem.read(aggregate, kAudioDevicePropertyBufferFrameSize)
            if currentFrames == 0 || currentFrames > 512 {
                let range: AudioValueRange = try AudioSystem.read(aggregate, kAudioDevicePropertyBufferFrameSizeRange)
                let target = try Self.bufferSize(
                    current: currentFrames, minimum: range.mMinimum, maximum: range.mMaximum)
                try await AudioConfiguration.setAndConfirm(
                    "The microphone buffer size", value: target,
                    read: { try AudioSystem.read(aggregate, kAudioDevicePropertyBufferFrameSize) },
                    write: { try AudioSystem.set(aggregate, kAudioDevicePropertyBufferFrameSize, $0) })
            }
            try Task.checkCancellation()
            guard self.generation == generation else { throw CancellationError() }
            try validateConfiguration()

            let outputOffset = AudioSystem.channelCounts(mic.id, scope: kAudioObjectPropertyScopeOutput).count
            let feedBuffers = AudioSystem.channelCounts(feed.id, scope: kAudioObjectPropertyScopeOutput).count
            let inputs = AudioSystem.channelCounts(aggregate, scope: kAudioObjectPropertyScopeInput)
            let outputs = AudioSystem.channelCounts(aggregate, scope: kAudioObjectPropertyScopeOutput)
            guard Int(location.buffer) < inputs.count, Int(location.channel) < inputs[Int(location.buffer)],
                feedBuffers > 0, outputOffset + feedBuffers <= outputs.count
            else { throw RouterError.configuration("The microphone's audio channels changed during setup. Try again.") }
            inputLayout = inputs
            outputLayout = outputs
            let routing = LucidRouting(
                inputBuffer: location.buffer, inputChannel: location.channel,
                outputFirstBuffer: UInt32(outputOffset), outputBufferCount: UInt32(feedBuffers))
            guard let engine = lucid_engine_create(routing, modelPath) else {
                throw RouterError.configuration(
                    "The noise-removal model could not be loaded. Reinstall the complete app.")
            }
            self.engine = engine
            var newProc: AudioDeviceIOProcID?
            let status = lucid_engine_start_live(engine, aggregate, &newProc)
            guard status == noErr, let newProc else {
                throw RouterError.coreAudio("Creating the audio callback", status)
            }
            proc = newProc
            let startStatus = AudioDeviceStart(aggregate, newProc)
            guard startStatus == noErr else { throw RouterError.coreAudio("Starting audio", startStatus) }
            source = mic
            self.feed = feed
            try watchDevices(mic: mic, feed: feed)
            try validateHealth()
        } catch {
            if self.generation == generation { stop() }
            throw error
        }
    }

    func setCleaning(_ cleaning: Bool) {
        if let engine { lucid_engine_set_bypass(engine, !cleaning) }
    }

    func stop() {
        generation += 1
        listeners.removeAll()
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
        source = nil
        feed = nil
        inputLayout = []
        outputLayout = []
        reportedFailure = false
    }

    static func validate(rate: Float64, frames: UInt32, maximumFrames: UInt32) throws {
        guard rate == 48_000 else {
            throw RouterError.configuration(
                "This microphone must support 48 kHz. Choose a different input or audio mode.")
        }
        guard frames > 0, max(frames, maximumFrames) <= 512 else {
            throw RouterError.configuration(
                "This microphone needs audio buffers of 512 frames or fewer. Choose another input.")
        }
    }

    static func bufferSize(current: UInt32, minimum: Float64, maximum: Float64) throws -> UInt32 {
        if current > 0 && current <= 512 { return current }
        guard minimum.isFinite, maximum.isFinite, minimum <= maximum, minimum <= 512, maximum >= 1 else {
            throw RouterError.configuration(
                "This microphone cannot use buffers of 512 frames or fewer. Choose another input.")
        }
        return UInt32(min(512, maximum).rounded(.down))
    }

    private func validateConfiguration() throws {
        let rate: Float64 = try AudioSystem.read(aggregate, kAudioDevicePropertyNominalSampleRate)
        let frames: UInt32 = try AudioSystem.read(aggregate, kAudioDevicePropertyBufferFrameSize)
        let maximum: UInt32 =
            (try? AudioSystem.read(aggregate, kAudioDevicePropertyUsesVariableBufferFrameSizes)) ?? frames
        try Self.validate(rate: rate, frames: frames, maximumFrames: maximum)
        for scope in [kAudioObjectPropertyScopeInput, kAudioObjectPropertyScopeOutput] {
            for stream in try AudioSystem.streams(aggregate, scope: scope) {
                let format: AudioStreamBasicDescription = try AudioSystem.read(
                    stream, kAudioStreamPropertyVirtualFormat)
                guard format.mSampleRate == 48_000, format.mFormatID == kAudioFormatLinearPCM,
                    format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32
                else {
                    throw RouterError.configuration(
                        "The microphone's audio format is unsupported. Choose another input.")
                }
            }
        }
    }

    private func watchDevices(mic: AudioDevice, feed: AudioDevice) throws {
        let generation = self.generation
        let changed: @Sendable () -> Void = { [weak self] in
            Task { @MainActor [weak self] in
                guard self?.generation == generation else { return }
                self?.checkHealth()
            }
        }
        listeners.append(
            try AudioPropertyListener(
                object: AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDevices,
                changed: changed))
        listeners.append(
            try AudioPropertyListener(
                object: AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyServiceRestarted
            ) { [weak self] in
                Task { @MainActor [weak self] in
                    guard self?.generation == generation else { return }
                    self?.reportFailure("The macOS audio service restarted. Turn on Noise Removal to reconnect.")
                }
            })
        for id in [aggregate, mic.id, feed.id] {
            for selector in [kAudioDevicePropertyDeviceIsAlive, kAudioDevicePropertyNominalSampleRate] {
                listeners.append(try AudioPropertyListener(object: id, selector: selector, changed: changed))
            }
        }
        for selector in [kAudioDevicePropertyDeviceIsRunning, kAudioDevicePropertyBufferFrameSize] {
            listeners.append(try AudioPropertyListener(object: aggregate, selector: selector, changed: changed))
        }
        for scope in [kAudioObjectPropertyScopeInput, kAudioObjectPropertyScopeOutput] {
            listeners.append(
                try AudioPropertyListener(
                    object: aggregate, selector: kAudioDevicePropertyStreamConfiguration, scope: scope, changed: changed
                ))
            for stream in try AudioSystem.streams(aggregate, scope: scope) {
                listeners.append(
                    try AudioPropertyListener(
                        object: stream, selector: kAudioStreamPropertyVirtualFormat, changed: changed))
            }
        }
    }

    private func checkHealth() {
        guard source != nil, engine != nil, !reportedFailure else { return }
        do {
            try validateHealth()
        } catch {
            reportFailure(error.localizedDescription)
        }
    }

    private func reportFailure(_ detail: String) {
        guard engine != nil, !reportedFailure else { return }
        reportedFailure = true
        onFailure?(detail)
    }

    private func validateHealth() throws {
        guard let source, let feed,
            let current = AudioSystem.device(uid: source.uid), current.id == source.id,
            current.isPhysicalInput, current.inputChannelCounts == source.inputChannelCounts,
            AudioSystem.device(uid: LucidDevice.feedUID)?.id == feed.id,
            AudioSystem.device(uid: LucidDevice.microphoneUID) != nil,
            AudioSystem.channelCounts(aggregate, scope: kAudioObjectPropertyScopeInput) == inputLayout,
            AudioSystem.channelCounts(aggregate, scope: kAudioObjectPropertyScopeOutput) == outputLayout
        else { throw RouterError.configuration("The active microphone was disconnected or its channels changed.") }
        for id in [source.id, feed.id, aggregate] {
            let alive: UInt32 = try AudioSystem.read(id, kAudioDevicePropertyDeviceIsAlive)
            guard alive != 0 else {
                throw RouterError.configuration(
                    "The audio device disconnected. Reconnect the microphone and try again.")
            }
        }
        let running: UInt32 = try AudioSystem.read(aggregate, kAudioDevicePropertyDeviceIsRunning)
        guard running != 0 else {
            throw RouterError.configuration("The audio device stopped. Try Noise Removal again.")
        }
        try validateConfiguration()
    }

    // Nonisolated avoids a Swift 6.3 compiler issue constructing heterogeneous dictionaries on MainActor.
    nonisolated private static func createAggregate(micUID: String, feedUID: String) throws -> AudioObjectID {
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "LucidMic Engine",
            kAudioAggregateDeviceUIDKey: "com.sultanovazamat.lucidmic.engine.\(UUID().uuidString)",
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
