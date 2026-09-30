import AVFoundation
import Foundation

/// System boundaries used by the app state; tests substitute hardware without capturing audio.
@MainActor
struct AppEnvironment {
    var devices: @MainActor () -> [AudioDevice] = { AudioSystem.devices() }
    var device: @MainActor (String) -> AudioDevice? = { AudioSystem.device(uid: $0) }
    var defaultInput: @MainActor () -> AudioDevice? = { AudioSystem.defaultInput }
    var setDefaultInput: @MainActor (AudioDevice) async throws -> Void = { try await AudioSystem.setDefaultInput($0) }
    var requestMicrophone: @MainActor () async -> Bool = { await AVCaptureDevice.requestAccess(for: .audio) }
    var modelPath: @MainActor () -> String? = { Bundle.main.path(forResource: "dpdfnet2_48khz_hr", ofType: "onnx") }
    var observesDevices = true
}
