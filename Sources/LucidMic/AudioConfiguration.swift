import CoreAudio
import Foundation

/// A successful property write may only schedule a change. Confirm the applied value before using it.
@MainActor
enum AudioConfiguration {
    static func setAndConfirm<Value: Equatable>(
        _ name: String, value: Value, read: () throws -> Value, write: (Value) throws -> Void,
        pause: () async throws -> Void = { try await Task.sleep(for: .milliseconds(25)) }
    ) async throws {
        if try read() == value { return }
        try write(value)
        for _ in 0..<40 {
            try Task.checkCancellation()
            if try read() == value { return }
            try await pause()
        }
        guard try read() == value else {
            throw RouterError.configuration("\(name) did not take effect. Choose a supported microphone and try again.")
        }
    }
}

/// Owns one HAL subscription; releasing it removes the exact registered callback.
final class AudioPropertyListener {
    private let object: AudioObjectID
    private let address: AudioObjectPropertyAddress
    private let block: AudioObjectPropertyListenerBlock

    init(
        object: AudioObjectID, selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        changed: @escaping @Sendable () -> Void
    ) throws {
        self.object = object
        self.address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        block = { _, _ in changed() }
        var address = self.address
        let status = AudioObjectAddPropertyListenerBlock(object, &address, .main, block)
        guard status == noErr else { throw RouterError.coreAudio("Watching the microphone", status) }
    }

    deinit {
        var address = self.address
        AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
    }
}
