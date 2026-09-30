import AppKit
import Testing

@testable import LucidMic

@Suite @MainActor
struct MenuTests {
    @Test func idleStatusDoesNotImplyMicrophonePassthrough() {
        let state = AppState()
        #expect(state.status == "Not running")
        #expect(!state.isRouting)
        #expect(!state.isCleaning)
    }

    @Test func bypassKeepsTheMicrophoneLiveButUnchecksCleaning() {
        let state = MenuState(activity: .running(microphone: "USB Microphone", cleaning: false), driverInstalled: true)
        let menu = NativeMenu()
        menu.update(state)

        #expect(state.activity.isRouting)
        #expect(!state.activity.isCleaning)
        #expect(menu.noiseRemoval.state == .off)
        #expect(menu.status.title == "Passing original audio")
        #expect(!menu.input.isHidden)
        #expect(menu.input.title == "Input: USB Microphone")
        #expect(menu.status.toolTip?.contains("microphone remains on") == true)
    }

    @Test func cleaningIsCheckedAndUsesTheActualInputName() {
        let menu = NativeMenu()
        menu.update(MenuState(activity: .running(microphone: "Studio Mic", cleaning: true), driverInstalled: true))

        #expect(menu.noiseRemoval.state == .on)
        #expect(menu.noiseRemoval.isEnabled)
        #expect(menu.status.title == "Removing noise")
        #expect(menu.input.title == "Input: Studio Mic")
        #expect(menu.setupHint.isHidden)
    }

    @Test(arguments: [MenuActivity.starting, .installing, .removing])
    func busyOperationsCannotBeStartedTwice(activity: MenuActivity) {
        let menu = NativeMenu()
        menu.update(MenuState(activity: activity, driverInstalled: true))

        #expect(activity.isBusy)
        #expect(!menu.noiseRemoval.isEnabled)
        #expect(menu.input.isHidden)
        #expect(menu.quit.isEnabled)
    }

    @Test func permissionFailureOffersTheRelevantSettingsAction() {
        let menu = NativeMenu()
        menu.update(MenuState(notice: .microphonePermission))

        #expect(!menu.permission.isHidden)
        #expect(menu.permission.representedObject as? String == MenuCommand.microphoneSettings.rawValue)
        #expect(menu.details.isHidden)
        #expect(menu.noiseRemoval.state == .off)

        menu.update(MenuState(activity: .running(microphone: "Mic", cleaning: true), driverInstalled: true))
        #expect(menu.permission.isHidden)
        #expect(menu.notice.isHidden)
    }

    @Test func longDeviceNamesDoNotMakeTheMenuUnbounded() {
        let name = String(repeating: "Studio 🎙️ ", count: 20)
        let menu = NativeMenu()
        menu.update(MenuState(activity: .running(microphone: name, cleaning: true), driverInstalled: true))

        #expect(menu.input.title.count < 65)
        #expect(menu.input.title.hasSuffix("…"))
        #expect(menu.input.toolTip == name)
    }

    @Test func detailedErrorsStayAvailableWithoutExpandingTheMenu() {
        let detail = String(repeating: "A detailed audio error. ", count: 40)
        let menu = NativeMenu()
        menu.update(MenuState(notice: .failure(title: "Couldn't start noise removal", detail: detail)))

        #expect(menu.notice.title == "Couldn't start noise removal")
        #expect(!menu.details.isHidden)
        #expect(menu.details.toolTip == detail)
        #expect(menu.permission.isHidden)
    }

    @Test func menuUsesNativeCommandsAndKeepsMaintenanceInSettings() {
        let menu = NativeMenu()
        menu.update(MenuState())
        let commands = menu.menu.items.compactMap { $0.representedObject as? String }

        #expect(menu.menu.items.first === menu.noiseRemoval)
        #expect(menu.settings.keyEquivalent == ",")
        #expect(menu.settings.keyEquivalentModifierMask == .command)
        #expect(menu.quit.keyEquivalent == "q")
        #expect(menu.menu.items.last === menu.quit)
        #expect(commands.contains(MenuCommand.settings.rawValue))
        #expect(!menu.menu.items.contains { $0.title.contains("Uninstall") || $0.title.contains("Remove Virtual") })
        #expect(!menu.status.isEnabled)
        #expect(menu.status.action == nil)
    }

    @Test func stateUpdatesPreserveTheNativeMenuItems() {
        let menu = NativeMenu()
        let original = menu.menu.items
        menu.update(MenuState(activity: .installing))
        menu.update(MenuState(activity: .running(microphone: "Mic", cleaning: true), driverInstalled: true))
        #expect(zip(original, menu.menu.items).allSatisfy { $0 === $1 })
    }

    @Test func appShortcutsWorkWithoutOpeningTheStatusMenu() throws {
        // XCTest's command-line runner has no NSApplication until explicitly initialized.
        _ = NSApplication.shared
        let recorder = MenuActionRecorder()
        let appMenu = NativeMenu().makeApplicationMenu(target: recorder)
        for (character, command) in [(",", MenuCommand.settings), ("q", .quit)] {
            let event = try #require(
                NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                    windowNumber: 0, context: nil, characters: character, charactersIgnoringModifiers: character,
                    isARepeat: false, keyCode: 0))
            #expect(appMenu.performKeyEquivalent(with: event))
            #expect(recorder.lastCommand == command.rawValue)
        }
        let close = appMenu.items.flatMap { $0.submenu?.items ?? [] }.first { $0.keyEquivalent == "w" }
        #expect(close?.action == #selector(NSWindow.performClose(_:)))
    }
}

@MainActor
private final class MenuActionRecorder: NSObject {
    var lastCommand: String?

    @objc func handleMenuAction(_ item: NSMenuItem) { lastCommand = item.representedObject as? String }
}
