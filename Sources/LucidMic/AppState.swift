import AVFoundation
import AppKit
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

    var isRouting: Bool { activity.isRouting }
    var isCleaning: Bool { activity.isCleaning }
    var isBusy: Bool { activity.isBusy }
    var status: String { activity.title }
    var menuState: MenuState { MenuState(activity: activity, driverInstalled: driverInstalled, notice: notice) }

    private let router = Router()
    private let restoreKey = "restoreInputUID"

    init() { refresh() }

    func refresh() {
        driverInstalled = AudioSystem.device(uid: LucidDevice.feedUID) != nil
        let loginStatus = SMAppService.mainApp.status
        launchAtLogin = loginStatus == .enabled || loginStatus == .requiresApproval
        loginNeedsApproval = loginStatus == .requiresApproval
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
        activity = .starting
        defer { if isBusy { activity = .idle } }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            notice = .microphonePermission
            return
        }
        refresh()
        if !driverInstalled {
            activity = .installing
            // Let the menu-bar status update before the system's modal administrator prompt.
            await Task.yield()
            switch runPrivileged("install-driver.sh", driverPath: true) {
            case .cancelled:
                notice = .information("Microphone setup cancelled")
                return
            case .failed(let detail):
                notice = .failure(title: "Couldn't set up microphone", detail: detail)
                return
            case .success:
                guard await waitForDriver() else {
                    notice = .failure(
                        title: "Microphone isn't available yet",
                        detail: "The virtual microphone did not appear after installation. Try Noise Removal again.")
                    return
                }
            }
        }
        turnOn()
    }

    private func turnOn() {
        guard let feed = AudioSystem.device(uid: LucidDevice.feedUID),
            let lucidMic = AudioSystem.device(uid: LucidDevice.microphoneUID)
        else {
            driverInstalled = false
            notice = .failure(
                title: "Virtual microphone is missing", detail: "Turn on Noise Removal again to reinstall it.")
            return
        }
        if let current = AudioSystem.defaultInput, current.isPhysicalInput {
            UserDefaults.standard.set(current.uid, forKey: restoreKey)
        }
        guard let mic = physicalMic() else {
            notice = .failure(
                title: "No microphone found", detail: "Connect a microphone, then try Noise Removal again.")
            return
        }
        do {
            guard let model = Bundle.main.path(forResource: "dpdfnet2_48khz_hr", ofType: "onnx") else {
                notice = .failure(
                    title: "Noise-removal model is missing",
                    detail: "Reinstall LucidMic from the complete DMG download.")
                return
            }
            try router.start(mic: mic, feed: feed, modelPath: model)
            AudioSystem.setDefaultInput(lucidMic)
            activity = .running(microphone: mic.name, cleaning: true)
        } catch {
            router.stop()
            notice = .failure(title: "Couldn't start noise removal", detail: error.localizedDescription)
        }
    }

    /// Quitting and removing the driver restore the physical microphone.
    func turnOff() {
        router.stop()
        restoreDefaultInput()
        activity = .idle
    }

    /// Called only after the user confirms removal in Settings.
    func removeDriver() async {
        guard driverInstalled, !isBusy else { return }
        notice = nil
        turnOff()
        activity = .removing
        await Task.yield()
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

    func recoverDefaultInput() {
        if AudioSystem.defaultInput?.isLucid == true { restoreDefaultInput() }
    }

    private func restoreDefaultInput() {
        guard AudioSystem.defaultInput?.isLucid == true, let mic = physicalMic() else { return }
        AudioSystem.setDefaultInput(mic)
    }

    private func physicalMic() -> AudioDevice? {
        let inputs = AudioSystem.devices().filter(\.isPhysicalInput)
        let saved = UserDefaults.standard.string(forKey: restoreKey)
        return inputs.first { $0.uid == saved } ?? inputs.first(where: \.isBuiltIn) ?? inputs.first
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

    private func waitForDriver() async -> Bool {
        for _ in 0..<40 {
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
