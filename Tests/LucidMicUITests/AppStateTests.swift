import CoreAudio
import Foundation
import Observation
import Testing

@testable import LucidMic

@Suite @MainActor
struct AppStateTests {
    @Test func automaticInputChangeNotifiesSettingsWithUnchangedChannel() async {
        let fixture = AudioFixture()
        let mono = AudioDevice(
            id: 4, uid: "mono", name: "Mono Microphone", inputStreams: 1, outputStreams: 0,
            transport: kAudioDeviceTransportTypeUSB)
        fixture.additionalInputs = [mono]
        let state = fixture.state
        #expect(state.selectedMicrophone?.inputChannelCount == 2)
        await confirmation("Settings observes automatic microphone changes") { changed in
            withObservationTracking {
                _ = state.selectedMicrophone
            } onChange: {
                changed()
            }
            fixture.current = mono
            state.refresh()
        }
        #expect(state.selectedMicrophone == mono)
        #expect(state.selectedInputChannel == 0)
    }

    @Test func failedDefaultSelectionRollsBackRouting() async {
        let fixture = AudioFixture()
        fixture.rejectDefault = true
        await fixture.state.toggle()
        #expect(!fixture.state.isRouting)
        #expect(!fixture.router.running)
        #expect(fixture.state.notice?.detail != nil)
        #expect(fixture.current == fixture.physical)
    }

    @Test func deviceFailureRestoresDefaultAndAllowsRetry() async {
        let fixture = AudioFixture()
        await fixture.state.toggle()
        #expect(fixture.state.isRouting)
        await fixture.state.routingFailed("Microphone disconnected")
        #expect(!fixture.state.isRouting)
        #expect(fixture.current == fixture.physical)
        #expect(fixture.state.notice?.detail?.contains("disconnected") == true)
        await fixture.state.toggle()
        #expect(fixture.state.isRouting)
        #expect(fixture.router.starts == 2)
    }

    @Test func restorationFailureIsVisible() async {
        let fixture = AudioFixture()
        await fixture.state.toggle()
        fixture.rejectDefault = true
        #expect(await fixture.state.turnOff() == false)
        #expect(!fixture.router.running)
        #expect(fixture.state.notice?.detail != nil)
    }

    @Test func virtualDefaultFallsBackToPhysicalInput() async {
        let fixture = AudioFixture()
        fixture.current = AudioDevice(
            id: 7, uid: "Loopback", name: "Other Virtual Mic", inputStreams: 1, outputStreams: 1,
            transport: kAudioDeviceTransportTypeVirtual)
        await fixture.state.toggle()
        #expect(fixture.router.source == fixture.physical)
    }

    @Test func concurrentTogglesCannotStartTwice() async {
        let fixture = AudioFixture()
        var release: CheckedContinuation<Bool, Never>?
        fixture.permission = { await withCheckedContinuation { release = $0 } }
        let first = Task { await fixture.state.toggle() }
        while release == nil { await Task.yield() }
        await fixture.state.toggle()
        #expect(fixture.router.starts == 0)
        release?.resume(returning: true)
        await first.value
        #expect(fixture.router.starts == 1)
        #expect(fixture.state.isCleaning)
    }

    @Test func stopDuringStartupPreventsLateActivation() async {
        let fixture = AudioFixture()
        var release: CheckedContinuation<Bool, Never>?
        fixture.permission = { await withCheckedContinuation { release = $0 } }
        let start = Task { await fixture.state.toggle() }
        while release == nil { await Task.yield() }
        var stopped = false
        let stop = Task {
            let result = await fixture.state.turnOff()
            stopped = true
            return result
        }
        for _ in 0..<100 {
            if stopped { break }
            await Task.yield()
        }
        #expect(stopped, "Quitting must not wait for an unanswered microphone-permission prompt")
        release?.resume(returning: true)
        await start.value
        #expect(await stop.value)
        #expect(!fixture.state.isRouting)
        #expect(fixture.router.starts == 0)
    }

    @Test func secondInputChannelIsPassedToRouterAndBypassSurvivesChange() async {
        let fixture = AudioFixture()
        await fixture.state.toggle()
        await fixture.state.toggle()
        await fixture.state.selectInputChannel(1)
        #expect(fixture.router.channel == 1)
        #expect(fixture.state.isRouting)
        #expect(!fixture.state.isCleaning)
        #expect(!fixture.router.cleaning)
    }

    @Test func stopWaitsForPendingDefaultSelectionThenRestoresPhysicalInput() async {
        let fixture = AudioFixture()
        var release: CheckedContinuation<Void, Never>?
        fixture.beforeDefault = { device in
            if device.isLucid { await withCheckedContinuation { release = $0 } }
        }
        let start = Task { await fixture.state.toggle() }
        while release == nil { await Task.yield() }
        let stop = Task { await fixture.state.turnOff() }
        while fixture.state.activity != .stopping { await Task.yield() }
        release?.resume()
        await start.value
        #expect(await stop.value)
        #expect(fixture.current == fixture.physical)
        #expect(!fixture.router.running)
        #expect(!fixture.state.isRouting)
    }

    @Test func permissionDenialNeverStartsRouting() async {
        let fixture = AudioFixture()
        fixture.permission = { false }
        await fixture.state.toggle()
        #expect(fixture.router.starts == 0)
        #expect(fixture.state.notice == .microphonePermission)
        #expect(fixture.state.activity == .idle)
    }

    @Test func routerFailureCallbackIsConnectedToRecovery() async {
        let fixture = AudioFixture()
        await fixture.state.toggle()
        fixture.router.onFailure?("Audio service restarted")
        while fixture.state.isRouting || fixture.state.isBusy || fixture.state.notice?.title != "Microphone stopped" {
            await Task.yield()
        }
        #expect(fixture.current == fixture.physical)
        #expect(!fixture.router.running)
    }

    @Test func quitDuringInputChangeCancelsThePendingRestart() async {
        let fixture = AudioFixture()
        await fixture.state.toggle()
        var release: CheckedContinuation<Void, Never>?
        fixture.beforeDefault = { device in
            if !device.isLucid { await withCheckedContinuation { release = $0 } }
        }
        let change = Task { await fixture.state.selectInputChannel(1) }
        while release == nil { await Task.yield() }
        let quit = Task { await fixture.state.turnOff() }
        await Task.yield()
        release?.resume()
        await change.value
        #expect(await quit.value)
        #expect(fixture.router.starts == 1)
        #expect(!fixture.router.running)
        #expect(fixture.state.activity == .idle)
    }
}

@MainActor
private final class FakeRouter: AudioRouting {
    var onFailure: ((String) -> Void)?
    var starts = 0
    var running = false
    var source: AudioDevice?
    var channel = 0
    var cleaning = true

    func start(mic: AudioDevice, feed: AudioDevice, channel: Int, modelPath: String) async throws {
        starts += 1
        source = mic
        self.channel = channel
        running = true
        cleaning = true
    }

    func setCleaning(_ cleaning: Bool) { self.cleaning = cleaning }
    func stop() { running = false }
}

@MainActor
private final class AudioFixture {
    let physical = AudioDevice(
        id: 1, uid: "physical", name: "USB Microphone", inputStreams: 1, outputStreams: 0,
        transport: kAudioDeviceTransportTypeUSB, inputChannelCounts: [2])
    let virtual = AudioDevice(
        id: 2, uid: LucidDevice.microphoneUID, name: "LucidMic", inputStreams: 1, outputStreams: 0,
        transport: kAudioDeviceTransportTypeVirtual)
    let feed = AudioDevice(
        id: 3, uid: LucidDevice.feedUID, name: "Feed", inputStreams: 0, outputStreams: 1,
        transport: kAudioDeviceTransportTypeVirtual, inputChannelCounts: [])
    let router = FakeRouter()
    let defaults = UserDefaults(suiteName: "LucidMic.tests.\(UUID().uuidString)")!
    var current: AudioDevice?
    var additionalInputs: [AudioDevice] = []
    var rejectDefault = false
    var permission: @MainActor () async -> Bool = { true }
    var beforeDefault: @MainActor (AudioDevice) async -> Void = { _ in }
    lazy var state: AppState = {
        var environment = AppEnvironment()
        environment.devices = { [unowned self] in [physical, virtual, feed] + additionalInputs }
        environment.device = { [unowned self] uid in
            ([physical, virtual, feed] + additionalInputs).first { $0.uid == uid }
        }
        environment.defaultInput = { [unowned self] in current }
        environment.setDefaultInput = { [unowned self] device in
            await beforeDefault(device)
            if rejectDefault { throw RouterError.coreAudio("Selecting default input", -1) }
            current = device
        }
        environment.requestMicrophone = { [unowned self] in await permission() }
        environment.modelPath = { "fixture-model" }
        environment.observesDevices = false
        return AppState(router: router, environment: environment, defaults: defaults)
    }()

    init() { current = physical }
}
