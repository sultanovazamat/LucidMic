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
            Image(systemName: delegate.state.isOn ? "waveform.circle.fill" : "waveform.circle")
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
    private(set) var isOn = false
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

    func toggle() async {
        if isOn {
            turnOff()
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
            try router.start(mic: mic, feed: feed)
            AudioSystem.setDefaultInput(lucidMic)  // every app on the default mic now hears the clean voice
            isOn = true
            status = "Cleaning \(mic.name)"
        } catch {
            router.stop()
            status = error.localizedDescription
        }
    }

    func turnOff() {
        router.stop()
        restoreDefaultInput()
        isOn = false
        status = "Off"
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
                Text("LucidMic").font(.headline)
                Spacer()
                if state.isBusy { ProgressView().controlSize(.small) }
                Toggle("", isOn: Binding(get: { state.isOn }, set: { _ in Task { await state.toggle() } }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(state.isBusy)
            }
            Text(state.status).font(.callout).foregroundStyle(.secondary)
            if state.isOn {
                Text("Apps using the default microphone now hear your clean voice. In Zoom, pick “Same as System”.")
                    .font(.caption).foregroundStyle(.secondary)
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
