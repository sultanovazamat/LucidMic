import AppKit

/// The app and screenshot tool use the same native menu. Items stay in place while tracking.
@MainActor
final class NativeMenu {
    let menu = NSMenu(title: "LucidMic")
    let noiseRemoval = NSMenuItem(title: "Noise Removal", action: nil, keyEquivalent: "")
    let status = NSMenuItem()
    let input = NSMenuItem()
    let setupHint = NSMenuItem(title: "First use sets up the microphone", action: nil, keyEquivalent: "")
    let notice = NSMenuItem()
    let permission = NSMenuItem(title: "Open Microphone Settings…", action: nil, keyEquivalent: "")
    let details = NSMenuItem(title: "Show Details…", action: nil, keyEquivalent: "")
    let settings = NSMenuItem(title: "Settings…", action: nil, keyEquivalent: ",")
    let help = NSMenuItem(title: "How to Use LucidMic", action: nil, keyEquivalent: "")
    let about = NSMenuItem(title: "About LucidMic", action: nil, keyEquivalent: "")
    let quit = NSMenuItem(title: "Quit LucidMic", action: nil, keyEquivalent: "q")

    init(target: AnyObject? = nil) {
        menu.autoenablesItems = false
        for item in [noiseRemoval, status, input, setupHint, notice, permission, details] { menu.addItem(item) }
        menu.addItem(.separator())
        menu.addItem(settings)
        menu.addItem(help)
        menu.addItem(.separator())
        menu.addItem(about)
        menu.addItem(quit)

        let commands: [(NSMenuItem, MenuCommand)] = [
            (noiseRemoval, .toggleNoiseRemoval), (permission, .microphoneSettings),
            (details, .details), (settings, .settings), (help, .help), (about, .about), (quit, .quit),
        ]
        for (item, command) in commands {
            item.target = target
            item.action = NSSelectorFromString("handleMenuAction:")
            item.representedObject = command.rawValue
            item.keyEquivalentModifierMask = .command
            item.isEnabled = true
        }
        for item in [status, input, setupHint, notice] { item.isEnabled = false }
        update(MenuState())
    }

    /// A status menu alone does not provide shortcuts while Settings is frontmost.
    func makeApplicationMenu(target: AnyObject) -> NSMenu {
        let root = NSMenu()
        let application = NSMenu(title: "LucidMic")
        for item in [about, settings, NSMenuItem.separator(), quit] {
            let copy = item.copy() as! NSMenuItem
            if copy.action != nil { copy.target = target }
            application.addItem(copy)
        }
        let appItem = NSMenuItem(title: "LucidMic", action: nil, keyEquivalent: "")
        appItem.submenu = application
        root.addItem(appItem)

        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [
            ("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
            ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a"),
        ] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        root.addItem(editItem)

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        windowItem.submenu = window
        root.addItem(windowItem)
        return root
    }

    func update(_ state: MenuState) {
        noiseRemoval.state = state.activity.isCleaning ? .on : .off
        noiseRemoval.isEnabled = !state.activity.isBusy
        status.title = state.activity.title
        status.toolTip =
            state.activity.isRouting && !state.activity.isCleaning
            ? "Your microphone remains on. Noise removal is bypassed." : nil
        input.isHidden = state.activity.microphone == nil
        if let name = state.activity.microphone {
            input.title = "Input: " + (name.count > 42 ? String(name.prefix(41)) + "…" : name)
            input.toolTip = name
        }
        setupHint.isHidden =
            state.driverInstalled || state.activity.isBusy || state.activity.isRouting
            || state.notice != nil
        notice.isHidden = state.notice == nil
        notice.title = state.notice?.title ?? ""
        permission.isHidden = state.notice != .microphonePermission
        details.isHidden = state.notice?.detail == nil
        details.toolTip = state.notice?.detail
    }
}
