import AVFoundation
import AppKit
import ServiceManagement
import SwiftUI

@main
struct LucidMicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(state: delegate.state)
        } label: {
            Image(systemName: delegate.state.isCleaning ? "waveform.circle.fill" : "waveform.circle")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor let state = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { state.recoverDefaultInput() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { state.turnOff() }
    }
}

@MainActor
@Observable
final class AppState {
    /// LucidMic Microphone is live and is the default mic.
    private(set) var isRouting = false
    /// Noise removal is on (the switch). Off means the voice passes through unchanged.
    private(set) var isCleaning = false
    private(set) var isBusy = false
    private(set) var status = "Off"
    private(set) var driverInstalled = false
    var launchAtLogin = SMAppService.mainApp.status == .enabled {
        didSet { updateLoginItem() }
    }

    private let router = Router()
    private let restoreKey = "restoreInputUID"

    init() { refresh() }

    func refresh() { driverInstalled = AudioSystem.device(uid: LucidDevice.feedUID) != nil }

    /// The switch. Once routing, it only flips noise removal, so apps keep hearing LucidMic Microphone
    /// and you can turn it on and off mid-recording to demo the difference.
    func toggle() async {
        if isRouting {
            isCleaning.toggle()
            router.setCleaning(isCleaning)
            status = statusText()
            return
        }
        isBusy = true
        defer { isBusy = false }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            status = "Allow microphone access in System Settings › Privacy & Security › Microphone."
            return
        }
        if !driverInstalled {
            status = "Installing the LucidMic microphone…"
            guard runPrivileged("install-driver.sh", driverPath: true), await waitForDriver() else {
                status = "The LucidMic microphone was not installed."
                return
            }
        }
        turnOn()
    }

    private func turnOn() {
        guard let feed = AudioSystem.device(uid: LucidDevice.feedUID),
            let lucidMic = AudioSystem.device(uid: LucidDevice.microphoneUID)
        else {
            status = "The LucidMic microphone is missing. Turn on again to reinstall."
            driverInstalled = false
            return
        }
        if let current = AudioSystem.defaultInput, current.isPhysicalInput {
            UserDefaults.standard.set(current.uid, forKey: restoreKey)
        }
        guard let mic = physicalMic() else {
            status = "No microphone found."
            return
        }
        do {
            guard let model = Bundle.main.path(forResource: "dpdfnet2_48khz_hr", ofType: "onnx") else {
                status = "The noise-removal model is missing from the app."
                return
            }
            try router.start(mic: mic, feed: feed, modelPath: model)
            AudioSystem.setDefaultInput(lucidMic)  // every app on the default mic now hears LucidMic
            micName = mic.name
            isRouting = true
            isCleaning = true
            status = statusText()
        } catch {
            router.stop()
            status = error.localizedDescription
        }
    }

    /// Stops LucidMic Microphone and gives the default back to the real mic (on quit and uninstall).
    func turnOff() {
        router.stop()
        restoreDefaultInput()
        isRouting = false
        isCleaning = false
        status = "Off"
    }

    private var micName = ""

    private func statusText() -> String {
        isCleaning ? "Removing noise from \(micName)" : "Noise removal off — your voice passes through unchanged"
    }

    func uninstall() {
        turnOff()
        if runPrivileged("uninstall-driver.sh", driverPath: false) {
            driverInstalled = false
            status = "Removed. You can now delete LucidMic from Applications."
        }
    }

    /// If we crashed while on, the default mic is still LucidMic: put the real mic back.
    func recoverDefaultInput() {
        if AudioSystem.defaultInput?.isLucid == true { restoreDefaultInput() }
    }

    private func restoreDefaultInput() {
        guard AudioSystem.defaultInput?.isLucid == true, let mic = physicalMic() else { return }
        AudioSystem.setDefaultInput(mic)
    }

    /// The mic the user had before we switched the default, else the built-in mic, else any real mic.
    private func physicalMic() -> AudioDevice? {
        let inputs = AudioSystem.devices().filter(\.isPhysicalInput)
        let saved = UserDefaults.standard.string(forKey: restoreKey)
        return inputs.first { $0.uid == saved } ?? inputs.first(where: \.isBuiltIn) ?? inputs.first
    }

    /// Runs a bundled script as root via the standard macOS password prompt.
    private func runPrivileged(_ script: String, driverPath: Bool) -> Bool {
        guard let resources = Bundle.main.resourceURL else { return false }
        var command = "/bin/sh " + quoted(resources.appendingPathComponent(script).path)
        if driverPath { command += " " + quoted(resources.appendingPathComponent("LucidMic.driver").path) }
        let source = "do shell script \"\(escaped(command))\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error, (error[NSAppleScript.errorNumber] as? Int) != -128 {  // -128: user cancelled
            status = "Failed: \(error[NSAppleScript.errorMessage] ?? error)"
        }
        return error == nil
    }

    /// coreaudiod restarts after install; give it a few seconds to publish the devices.
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

    private func updateLoginItem() {
        do {
            if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            status = "Launch at login: \(error.localizedDescription)"
        }
    }
}

struct MenuView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Noise removal").font(.headline)
                Spacer()
                if state.isBusy { ProgressView().controlSize(.small) }
                Toggle("", isOn: Binding(get: { state.isCleaning }, set: { _ in Task { await state.toggle() } }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(state.isBusy)
            }
            Text(state.status).font(.callout).foregroundStyle(.secondary)
            if state.isRouting {
                Text(
                    "Apps using “LucidMic Microphone” or the default mic hear this. Flip the switch anytime, even mid-call. Quit to go back to your normal mic."
                )
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else if !state.driverInstalled {
                Text("First time: LucidMic installs its microphone and asks for your password once.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Toggle("Launch at login", isOn: $state.launchAtLogin)
            HStack {
                if state.driverInstalled { Button("Uninstall…") { state.uninstall() } }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear { state.refresh() }
    }
}
