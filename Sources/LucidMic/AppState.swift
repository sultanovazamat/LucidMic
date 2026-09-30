import AVFoundation
import AppKit
import CoreAudio
import Observation
import ServiceManagement

@MainActor
@Observable
final class AppState {
    private(set) var activity: MenuActivity = .idle
    private(set) var notice: MenuNotice?
    private(set) var driverInstalled = false
    private(set) var launchAtLogin = false
    private(set) var loginNeedsApproval = false
    private(set) var settingsError: String?
    private(set) var availableInputs: [AudioDevice] = []
    private(set) var selectedInputUID: String
    private(set) var selectedInputChannel = 0

    var isRouting: Bool { activity.isRouting }
    var isCleaning: Bool { activity.isCleaning }
    var isBusy: Bool { activity.isBusy }
    var status: String { activity.title }
    var menuState: MenuState { MenuState(activity: activity, driverInstalled: driverInstalled, notice: notice) }

    private let router: any AudioRouting
    private let environment: AppEnvironment
    private let defaults: UserDefaults
    private let restoreKey = "restoreInputUID"
    private var deviceListeners: [AudioPropertyListener] = []
    private var defaultInputUID: String?
    private var operation = 0
    private var startup: Task<Void, Never>?
    private var startupCanChangeAudio = false
    private var shutdown: Task<Bool, Never>?

    init(
        router: any AudioRouting = Router(), environment: AppEnvironment = AppEnvironment(),
        defaults: UserDefaults = .standard
    ) {
        self.router = router
        self.environment = environment
        self.defaults = defaults
        selectedInputUID = defaults.string(forKey: "selectedInputUID") ?? ""
        refresh()
        loadInputChannel()
        router.onFailure = { [weak self] detail in
            Task { @MainActor [weak self] in await self?.routingFailed(detail) }
        }
        if environment.observesDevices {
            for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
                if let listener = try? AudioPropertyListener(
                    object: AudioObjectID(kAudioObjectSystemObject), selector: selector,
                    changed: { [weak self] in
                        Task { @MainActor [weak self] in self?.refresh() }
                    }
                ) {
                    deviceListeners.append(listener)
                }
            }
        }
    }

    func refresh() {
        availableInputs = environment.devices().filter(\.isPhysicalInput)
        defaultInputUID = environment.defaultInput()?.uid
        driverInstalled =
            environment.device(LucidDevice.feedUID) != nil
            && environment.device(LucidDevice.microphoneUID) != nil
        let loginStatus = SMAppService.mainApp.status
        launchAtLogin = loginStatus == .enabled || loginStatus == .requiresApproval
        loginNeedsApproval = loginStatus == .requiresApproval
        if !isRouting && !isBusy { loadInputChannel() }
    }

    /// Bypassing preserves the live virtual microphone and its latency during a call.
    func toggle() async {
        guard !isBusy else { return }
        notice = nil
        if case .running(let microphone, let cleaning) = activity {
            router.setCleaning(!cleaning)
            activity = .running(microphone: microphone, cleaning: !cleaning)
            return
        }
        operation += 1
        let token = operation
        activity = .starting
        startupCanChangeAudio = false
        let task = Task { await startRouting(token: token) }
        startup = task
        await task.value
        if operation == token { startup = nil }
    }

    private func startRouting(token: Int) async {
        defer { if operation == token && isBusy { activity = .idle } }
        let permitted = await environment.requestMicrophone()
        guard operation == token else { return }
        guard permitted else {
            notice = .microphonePermission
            return
        }
        refresh()
        loadInputChannel()
        if !driverInstalled {
            activity = .installing
            // Let the menu-bar status update before the system's modal administrator prompt.
            await Task.yield()
            guard operation == token else { return }
            switch runPrivileged("install-driver.sh", driverPath: true) {
            case .cancelled:
                notice = .information("Microphone setup cancelled")
                return
            case .failed(let detail):
                notice = .failure(title: "Couldn't set up microphone", detail: detail)
                return
            case .success:
                let appeared = await waitForDriver(token: token)
                guard operation == token else { return }
                guard appeared else {
                    notice = .failure(
                        title: "Microphone isn't available yet",
                        detail: "The virtual microphone did not appear after installation. Try Noise Removal again.")
                    return
                }
            }
        }
        await turnOn(token: token)
    }

    private func turnOn(token: Int) async {
        guard let feed = environment.device(LucidDevice.feedUID),
            let lucidMic = environment.device(LucidDevice.microphoneUID)
        else {
            driverInstalled = false
            notice = .failure(
                title: "Virtual microphone is missing", detail: "Turn on Noise Removal again to reinstall it.")
            return
        }
        if let current = environment.defaultInput(), current.isPhysicalInput {
            defaults.set(current.uid, forKey: restoreKey)
        }
        guard let mic = selectedMicrophone else {
            notice = .failure(
                title: "No microphone found",
                detail: "Connect the selected microphone or choose another input in Settings.")
            return
        }
        do {
            guard let model = environment.modelPath() else {
                notice = .failure(
                    title: "Noise-removal model is missing",
                    detail: "Reinstall LucidMic from the complete DMG download.")
                return
            }
            startupCanChangeAudio = true
            try await router.start(mic: mic, feed: feed, channel: selectedInputChannel, modelPath: model)
            guard operation == token else { return }
            try await environment.setDefaultInput(lucidMic)
            guard operation == token else { return }
            let label = mic.inputChannelCount > 1 ? "\(mic.name) · Channel \(selectedInputChannel + 1)" : mic.name
            activity = .running(microphone: label, cleaning: true)
        } catch {
            guard operation == token else { return }
            router.stop()
            let restored = await restoreDefaultInput()
            let restoration = restored ? "" : "\n" + (notice?.detail ?? "Restore your input in System Settings.")
            notice = .failure(title: "Couldn't start noise removal", detail: error.localizedDescription + restoration)
        }
    }

    /// Quitting and removing the driver restore the physical microphone.
    @discardableResult
    func turnOff(nextActivity: MenuActivity = .idle) async -> Bool {
        operation += 1
        let token = operation
        activity = .stopping
        if let shutdown {
            let restored = await shutdown.value
            if operation == token { activity = nextActivity }
            return restored
        }
        let pending = startupCanChangeAudio ? startup : nil
        let task = Task {
            // A pending default-input write must finish before restoration, or it could take effect after quitting.
            await pending?.value
            router.stop()
            let restored = await restoreDefaultInput()
            return restored
        }
        shutdown = task
        let restored = await task.value
        shutdown = nil
        startup = nil
        startupCanChangeAudio = false
        if operation == token { activity = nextActivity }
        return restored
    }

    /// Called only after the user confirms removal in Settings.
    func removeDriver() async {
        guard driverInstalled, !isBusy else { return }
        notice = nil
        let token = operation + 1
        let restored = await turnOff(nextActivity: .removing)
        guard operation == token else { return }
        guard restored else {
            activity = .idle
            return
        }
        await Task.yield()
        guard operation == token else { return }
        let result = runPrivileged("uninstall-driver.sh", driverPath: false)
        activity = .idle
        refresh()
        switch result {
        case .success:
            driverInstalled = false
            notice = .information("Virtual microphone removed")
        case .cancelled:
            notice = .information("Microphone removal cancelled")
        case .failed(let detail):
            notice = .failure(title: "Couldn't remove microphone", detail: detail)
        }
    }

    func recoverDefaultInput() async {
        guard !isRouting, !isBusy, environment.defaultInput()?.isLucid == true else { return }
        _ = await turnOff()
    }

    private func restoreDefaultInput() async -> Bool {
        guard environment.defaultInput()?.isLucid == true else { return true }
        let inputs = environment.devices().filter(\.isPhysicalInput)
        let saved = defaults.string(forKey: restoreKey)
        do {
            guard let mic = inputs.first(where: { $0.uid == saved }) ?? inputs.first(where: \.isBuiltIn) ?? inputs.first
            else {
                throw RouterError.configuration(
                    "No physical microphone is available. Connect one and select it in System Settings.")
            }
            try await environment.setDefaultInput(mic)
            return true
        } catch {
            notice = .failure(title: "Couldn't restore microphone", detail: error.localizedDescription)
            return false
        }
    }

    var selectedMicrophone: AudioDevice? {
        if !selectedInputUID.isEmpty { return availableInputs.first { $0.uid == selectedInputUID } }
        let saved = defaults.string(forKey: restoreKey)
        return availableInputs.first { $0.uid == defaultInputUID }
            ?? availableInputs.first { $0.uid == saved }
            ?? availableInputs.first(where: \.isBuiltIn) ?? availableInputs.first
    }

    func routingFailed(_ detail: String) async {
        guard isRouting || activity == .starting else { return }
        let restored = await turnOff()
        let restoration = restored ? "" : "\n" + (notice?.detail ?? "Restore your microphone in System Settings.")
        notice = .failure(
            title: "Microphone stopped",
            detail: detail + " Turn on Noise Removal to retry, or choose another input in Settings." + restoration)
        refresh()
    }

    func selectInput(_ uid: String) async {
        guard !isBusy, uid != selectedInputUID,
            uid.isEmpty || availableInputs.contains(where: { $0.uid == uid })
        else { return }
        await changeInput {
            selectedInputUID = uid
            defaults.set(uid, forKey: "selectedInputUID")
            loadInputChannel()
        }
    }

    func selectInputChannel(_ channel: Int) async {
        guard !isBusy, channel != selectedInputChannel, selectedMicrophone?.inputLocation(channel: channel) != nil
        else { return }
        await changeInput {
            selectedInputChannel = channel
            if let uid = selectedMicrophone?.uid { defaults.set(channel, forKey: "inputChannel.\(uid)") }
        }
    }

    private func changeInput(_ update: () -> Void) async {
        let wasRouting = isRouting
        let wasCleaning = isCleaning
        if wasRouting {
            let token = operation + 1
            let restored = await turnOff(nextActivity: .starting)
            guard operation == token else { return }
            guard restored else {
                activity = .idle
                return
            }
        }
        update()
        if wasRouting {
            activity = .idle
            await toggle()
            if isRouting && !wasCleaning { await toggle() }
        }
    }

    private func loadInputChannel() {
        guard let mic = selectedMicrophone else {
            selectedInputChannel = 0
            return
        }
        let saved = defaults.integer(forKey: "inputChannel.\(mic.uid)")
        selectedInputChannel = mic.inputLocation(channel: saved) != nil ? saved : 0
    }

    private enum PrivilegedResult {
        case success, cancelled
        case failed(String)
    }

    private func runPrivileged(_ script: String, driverPath: Bool) -> PrivilegedResult {
        guard let resources = Bundle.main.resourceURL else { return .failed("App resources are unavailable.") }
        var command = "/bin/sh " + quoted(resources.appendingPathComponent(script).path)
        if driverPath { command += " " + quoted(resources.appendingPathComponent("LucidMic.driver").path) }
        let source = "do shell script \"\(escaped(command))\" with administrator privileges"
        guard let appleScript = NSAppleScript(source: source) else {
            return .failed("Couldn't prepare the administrator request.")
        }
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        if let error {
            if (error[NSAppleScript.errorNumber] as? Int) == -128 { return .cancelled }
            return .failed(String(describing: error[NSAppleScript.errorMessage] ?? error))
        }
        return .success
    }

    private func waitForDriver(token: Int) async -> Bool {
        for _ in 0..<40 {
            guard operation == token else { return false }
            refresh()
            if driverInstalled { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    private func quoted(_ path: String) -> String { "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private func escaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        settingsError = nil
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            settingsError = error.localizedDescription
        }
        refresh()
    }
}
