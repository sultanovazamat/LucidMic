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
    private(set) var status = "Off"
    private(set) var hasVirtualMic = false
    var launchAtLogin = SMAppService.mainApp.status == .enabled {
        didSet { updateLoginItem() }
    }

    private let router = Router()
    private let restoreKey = "restoreInputUID"

    init() { refresh() }

    func refresh() { hasVirtualMic = virtualMic() != nil }

    func toggle() async {
        if isOn {
            turnOff()
            return
        }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            status = "Allow microphone access in System Settings › Privacy & Security › Microphone."
            return
        }
        turnOn()
    }

    private func turnOn() {
        guard let virtualMic = virtualMic() else {
            status = "Install BlackHole first."
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
            try router.start(mic: mic, virtualMic: virtualMic)
            AudioSystem.setDefaultInput(virtualMic)  // every app on the default mic now hears clean audio
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

    /// If we crashed while on, the system default is still the virtual mic: put the real mic back.
    func recoverDefaultInput() {
        if AudioSystem.defaultInput?.isBlackHole == true { restoreDefaultInput() }
    }

    private func restoreDefaultInput() {
        guard AudioSystem.defaultInput?.isBlackHole == true, let mic = physicalMic() else { return }
        AudioSystem.setDefaultInput(mic)
    }

    private func virtualMic() -> AudioDevice? {
        AudioSystem.devices().first { $0.isBlackHole && $0.inputStreams > 0 && $0.outputStreams > 0 }
    }

    /// The mic the user had before we switched the default, else the built-in mic, else any real mic.
    private func physicalMic() -> AudioDevice? {
        let inputs = AudioSystem.devices().filter(\.isPhysicalInput)
        let saved = UserDefaults.standard.string(forKey: restoreKey)
        return inputs.first { $0.uid == saved } ?? inputs.first(where: \.isBuiltIn) ?? inputs.first
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
                Toggle("", isOn: Binding(get: { state.isOn }, set: { _ in Task { await state.toggle() } }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!state.hasVirtualMic)
            }
            Text(state.status).font(.callout).foregroundStyle(.secondary)
            if state.isOn {
                Text("Apps using the default microphone now get your clean voice.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !state.hasVirtualMic {
                Text("LucidMic needs the free BlackHole 2ch virtual microphone.").font(.caption)
                Button("Get BlackHole…") {
                    NSWorkspace.shared.open(URL(string: "https://existential.audio/blackhole/")!)
                }
                Text("or run: brew install blackhole-2ch").font(.caption.monospaced()).textSelection(.enabled)
            }
            Divider()
            Toggle("Launch at login", isOn: $state.launchAtLogin)
            Button("Quit LucidMic") { NSApp.terminate(nil) }
        }
        .padding()
        .frame(width: 300)
        .onAppear { state.refresh() }
    }
}
