import AppKit
import Observation

@main
enum LucidMicApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    private var controller: MenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = MenuController(state: state)
        Task { await state.recoverDefaultInput() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            let restored = await state.turnOff()
            if !restored {
                let alert = NSAlert()
                alert.messageText = "Couldn't restore your microphone"
                alert.informativeText = state.notice?.detail ?? "Select a physical input in System Settings."
                alert.addButton(withTitle: "Stay Open")
                alert.addButton(withTitle: "Quit Anyway")
                sender.activate(ignoringOtherApps: true)
                sender.reply(toApplicationShouldTerminate: alert.runModal() == .alertSecondButtonReturn)
            } else {
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    func applicationDidBecomeActive(_ notification: Notification) { state.refresh() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.showMenu()
        return true
    }
}

@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    let state: AppState
    let nativeMenu = NativeMenu()
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var settingsWindow: SettingsWindowController?

    init(state: AppState) {
        self.state = state
        super.init()
        for item in nativeMenu.menu.items where item.action != nil { item.target = self }
        nativeMenu.menu.delegate = self
        statusItem.menu = nativeMenu.menu
        NSApp.mainMenu = nativeMenu.makeApplicationMenu(target: self)
        observeState()
    }

    private func observeState() {
        withObservationTracking {
            let presentation = state.menuState
            nativeMenu.update(presentation)
            let image =
                NSImage(systemSymbolName: presentation.activity.symbol, accessibilityDescription: "LucidMic")
                ?? NSImage(systemSymbolName: "waveform", accessibilityDescription: "LucidMic")
            image?.isTemplate = true
            statusItem.button?.image = image
            statusItem.button?.toolTip = presentation.accessibilityLabel
            statusItem.button?.setAccessibilityLabel(presentation.accessibilityLabel)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeState() }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        state.refresh()
        nativeMenu.update(state.menuState)
    }

    func showMenu() { statusItem.button?.performClick(nil) }

    @objc func handleMenuAction(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String, let command = MenuCommand(rawValue: raw) else { return }
        switch command {
        case .toggleNoiseRemoval:
            Task { await state.toggle() }
        case .settings:
            if settingsWindow == nil { settingsWindow = SettingsWindowController(state: state) }
            state.refresh()
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow?.showWindow(nil)
            settingsWindow?.window?.makeKeyAndOrderFront(nil)
        case .microphoneSettings:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        case .details:
            if case .failure(let title, let detail) = state.notice { showMessage(title, detail: detail) }
        case .help:
            showMessage(
                "Using LucidMic",
                detail: """
                    Turn on Noise Removal to clean your microphone. First use asks for microphone access and installs \
                    a virtual microphone with administrator permission. Setup restarts the audio service, so do it before a call.

                    Apps using the system-default input receive cleaned audio. If you selected a microphone manually in \
                    your call app, choose “LucidMic Microphone” there.

                    Unchecking Noise Removal passes your original audio through. Your microphone stays on; this is not a mute button.

                    Quit LucidMic to stop routing and restore your physical microphone. Launch at Login and Remove Virtual \
                    Microphone are in Settings.
                    """
            )
        case .about:
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(options: [
                .applicationName: "LucidMic",
                .credits: NSAttributedString(
                    string:
                        "Your voice. Minus the noise.\nOn-device noise removal for macOS.\n© 2026 Azamat Sultanov · GPL-3.0"
                ),
            ])
        case .quit:
            NSApp.terminate(nil)
        }
    }

    private func showMessage(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
