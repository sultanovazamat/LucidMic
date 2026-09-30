import CoreAudio
import Foundation

struct AudioDevice: Equatable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let inputStreams: Int
    let outputStreams: Int
    let transport: UInt32
    var inputChannelCounts: [Int] = [1]

    /// LucidMic's own devices ("LucidMic Microphone", hidden "LucidMic Feed").
    var isLucid: Bool { uid.hasPrefix("LucidMic_") }
    var isAggregate: Bool { transport == kAudioDeviceTransportTypeAggregate }
    var isBuiltIn: Bool { transport == kAudioDeviceTransportTypeBuiltIn }
    /// A real microphone we may read from (never our own devices, never an aggregate).
    var isPhysicalInput: Bool {
        inputStreams > 0 && inputChannelCount > 0 && !isLucid && !isAggregate
            && transport != kAudioDeviceTransportTypeVirtual
    }

    var inputChannelCount: Int { inputChannelCounts.reduce(0, +) }

    /// The stream layout matches the buffer list delivered to the audio callback.
    func inputLocation(channel: Int) -> (buffer: UInt32, channel: UInt32)? {
        guard channel >= 0 else { return nil }
        var remaining = channel
        for (buffer, count) in inputChannelCounts.enumerated() {
            if remaining < count { return (UInt32(buffer), UInt32(remaining)) }
            remaining -= count
        }
        return nil
    }
}

enum LucidDevice {
    static let microphoneUID = "LucidMic_UID"  // visible input that call apps use
    static let feedUID = "LucidMic_2_UID"  // hidden output we write clean audio to
}

/// Thin Core Audio property helpers.
enum AudioSystem {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    static func devices() -> [AudioDevice] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.stride)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap(device(id:))
    }

    static func device(id: AudioObjectID) -> AudioDevice? {
        guard let uid = string(id, kAudioDevicePropertyDeviceUID) else { return nil }
        return AudioDevice(
            id: id, uid: uid, name: string(id, kAudioObjectPropertyName) ?? uid,
            inputStreams: streamCount(id, kAudioObjectPropertyScopeInput),
            outputStreams: streamCount(id, kAudioObjectPropertyScopeOutput),
            transport: scalar(id, kAudioDevicePropertyTransportType) ?? 0,
            inputChannelCounts: channelCounts(id, scope: kAudioObjectPropertyScopeInput))
    }

    /// Looks a device up by UID, including hidden devices that `devices()` does not list.
    static func device(uid: String) -> AudioDevice? {
        var addr = address(kAudioHardwarePropertyTranslateUIDToDevice)
        var qualifier = uid as CFString
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafeMutablePointer(to: &qualifier) {
            AudioObjectGetPropertyData(system, &addr, UInt32(MemoryLayout<CFString>.size), $0, &size, &id)
        }
        guard status == noErr, id != kAudioObjectUnknown else { return nil }
        return device(id: id)
    }

    static var defaultInput: AudioDevice? {
        scalar(system, kAudioHardwarePropertyDefaultInputDevice).flatMap { device(id: $0) }
    }

    static func setDefaultInput(_ device: AudioDevice) async throws {
        try await AudioConfiguration.setAndConfirm(
            "Selecting the system microphone", value: device.id,
            read: { try read(system, kAudioHardwarePropertyDefaultInputDevice) },
            write: { try set(system, kAudioHardwarePropertyDefaultInputDevice, $0) })
    }

    static func set<T: BitwiseCopyable>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: T) throws
    {
        var addr = address(selector)
        var value = value
        let status = AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<T>.size), &value)
        guard status == noErr else { throw RouterError.coreAudio("Changing audio configuration", status) }
    }

    static func read<T: BitwiseCopyable>(
        _ id: AudioObjectID, _ selector: AudioObjectPropertySelector
    ) throws -> T {
        var addr = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, value)
        guard status == noErr else { throw RouterError.coreAudio("Reading audio configuration", status) }
        return value.pointee
    }

    static func channelCounts(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> [Int] {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr,
            size >= MemoryLayout<AudioBufferList>.size
        else { return [] }
        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, storage) == noErr else { return [] }
        let list = UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self))
        return list.map { Int($0.mNumberChannels) }
    }

    static func streams(_ id: AudioObjectID, scope: AudioObjectPropertyScope) throws -> [AudioStreamID] {
        var addr = address(kAudioDevicePropertyStreams, scope)
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size)
        guard status == noErr else { throw RouterError.coreAudio("Reading audio streams", status) }
        guard size > 0 else { return [] }
        var streams = [AudioStreamID](repeating: 0, count: Int(size) / MemoryLayout<AudioStreamID>.stride)
        status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &streams)
        guard status == noErr else { throw RouterError.coreAudio("Reading audio streams", status) }
        return streams
    }

    private static func address(
        _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func scalar<T: BitwiseCopyable>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var addr = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, value) == noErr ? value.pointee : nil
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func streamCount(_ id: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Int {
        var addr = address(kAudioDevicePropertyStreams, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.stride
    }
}
