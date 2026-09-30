import CoreAudio
import Testing

@testable import LucidMic

@Suite @MainActor
struct AudioConfigurationTests {
    @Test func supportedExistingBufferSizeIsPreserved() throws {
        #expect(try Router.bufferSize(current: 256, minimum: 32, maximum: 256) == 256)
        #expect(try Router.bufferSize(current: 1024, minimum: 32, maximum: 2048) == 512)
        #expect(throws: RouterError.self) { try Router.bufferSize(current: 1024, minimum: 1024, maximum: 2048) }
    }
    @Test func unsupportedHardwareCannotStartTheFixedRateEngine() {
        #expect(throws: RouterError.self) { try Router.validate(rate: 44_100, frames: 512, maximumFrames: 512) }
        #expect(throws: RouterError.self) { try Router.validate(rate: 48_000, frames: 1024, maximumFrames: 1024) }
        #expect(throws: RouterError.self) { try Router.validate(rate: 48_000, frames: 480, maximumFrames: 1024) }
        #expect(throws: RouterError.self) { try Router.validate(rate: 48_000, frames: 0, maximumFrames: 0) }
        #expect(throws: Never.self) { try Router.validate(rate: 48_000, frames: 480, maximumFrames: 512) }
    }
    @Test func virtualDevicesAreNeverAutomaticPhysicalInputs() {
        let device = AudioDevice(
            id: 42, uid: "OtherLoopback", name: "Other Loopback", inputStreams: 1,
            outputStreams: 1, transport: kAudioDeviceTransportTypeVirtual)
        #expect(!device.isPhysicalInput)
    }

    @Test func rateWriteFailureIsPropagatedBeforeWaiting() async {
        var waited = false
        await #expect(throws: RouterError.self) {
            try await AudioConfiguration.setAndConfirm(
                "Sample rate", value: 48_000, read: { 44_100 },
                write: { _ in throw RouterError.coreAudio("Sample rate", -1) },
                pause: { waited = true })
        }
        #expect(!waited)
    }

    @Test func configurationWaitsForTheAppliedValue() async throws {
        var actual = 44_100
        var requested = 0
        var waits = 0
        try await AudioConfiguration.setAndConfirm(
            "Sample rate", value: 48_000, read: { actual }, write: { requested = $0 },
            pause: {
                waits += 1
                if waits == 3 { actual = requested }
            })
        #expect(actual == 48_000)
        #expect(waits == 3)
    }

    @Test func configurationThatNeverAppliesFails() async {
        await #expect(throws: RouterError.self) {
            try await AudioConfiguration.setAndConfirm(
                "Sample rate", value: 48_000, read: { 44_100 }, write: { _ in }, pause: {})
        }
    }

    @Test func channelNumbersMapAcrossInputBuffers() {
        let device = AudioDevice(
            id: 42, uid: "USB", name: "Interface", inputStreams: 2, outputStreams: 1,
            transport: kAudioDeviceTransportTypeUSB, inputChannelCounts: [2, 2])
        #expect(device.inputChannelCount == 4)
        #expect(device.inputLocation(channel: 1)?.buffer == 0)
        #expect(device.inputLocation(channel: 1)?.channel == 1)
        #expect(device.inputLocation(channel: 2)?.buffer == 1)
        #expect(device.inputLocation(channel: 2)?.channel == 0)
        #expect(device.inputLocation(channel: 4) == nil)
        #expect(device.inputLocation(channel: -1) == nil)
    }
}
