// Render a README illustration from the app's real NSMenu items without Screen Recording access.
// Compile with MenuState.swift and NativeMenu.swift; see scripts/render-menu.sh.
import AppKit

@MainActor
final class MenuPreview: NSView {
    let items: [NSMenuItem]
    let menuFont = NSFont.menuFont(ofSize: 13)
    let rowHeight: CGFloat = 24
    let separatorHeight: CGFloat = 10
    override var isFlipped: Bool { true }

    init(menu: NSMenu) {
        items = menu.items.filter { !$0.isHidden }
        let height = items.reduce(CGFloat(12)) { $0 + ($1.isSeparatorItem ? 10 : 24) }
        super.init(frame: NSRect(x: 0, y: 0, width: 270, height: height))
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        NSColor.windowBackgroundColor.setFill()
        shape.fill()
        NSColor.separatorColor.withAlphaComponent(0.65).setStroke()
        shape.lineWidth = 1
        shape.stroke()
        var y: CGFloat = 6
        for item in items {
            if item.isSeparatorItem {
                NSColor.separatorColor.setFill()
                NSRect(x: 12, y: y + separatorHeight / 2, width: bounds.width - 24, height: 0.5).fill()
                y += separatorHeight
                continue
            }
            let color = item.isEnabled ? NSColor.labelColor : NSColor.secondaryLabelColor
            let attributes: [NSAttributedString.Key: Any] = [.font: menuFont, .foregroundColor: color]
            let title = item.title as NSString
            let textHeight = title.size(withAttributes: attributes).height
            let textY = y + (rowHeight - textHeight) / 2
            title.draw(at: NSPoint(x: 27, y: textY), withAttributes: attributes)
            if item.state == .on {
                ("✓" as NSString).draw(at: NSPoint(x: 10, y: textY), withAttributes: attributes)
            }
            if !item.keyEquivalent.isEmpty {
                let shortcut = ("⌘" + item.keyEquivalent.uppercased()) as NSString
                let width = shortcut.size(withAttributes: attributes).width
                shortcut.draw(at: NSPoint(x: bounds.width - width - 15, y: textY), withAttributes: attributes)
            }
            y += rowHeight
        }
    }
}

@main
struct RenderMenu {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 3, ["light", "dark"].contains(CommandLine.arguments[1]) else {
            fatalError("Usage: render-menu light|dark output.png")
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let mode = CommandLine.arguments[1]
        let appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)!
        app.appearance = appearance
        let native = NativeMenu()
        native.update(
            MenuState(activity: .running(microphone: "Built-in Microphone", cleaning: true), driverInstalled: true))
        let preview = MenuPreview(menu: native.menu)
        preview.appearance = appearance
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(preview.bounds.width * 2),
            pixelsHigh: Int(preview.bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = preview.bounds.size
        appearance.performAsCurrentDrawingAppearance { preview.cacheDisplay(in: preview.bounds, to: bitmap) }
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("Could not encode the menu preview")
        }
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
        print("Rendered \(mode) menu preview (staged state, no microphone access)")
    }
}
