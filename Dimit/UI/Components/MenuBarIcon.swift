import AppKit

/// CLAUDE.md §3.9: "outline when OFF, filled when ON, small dot when PWM
/// pinned." SF Symbols for the base shape (still a placeholder — a real
/// custom glyph is visual-design polish for a later pass); the pinned dot
/// is drawn by hand and composited on top, since there's no single SF
/// Symbol that reliably means exactly "this, plus a small corner dot"
/// across macOS versions.
enum MenuBarIcon {
    static func image(isOn: Bool, pwmPinned: Bool = false) -> NSImage? {
        let symbolName = isOn ? "circle.fill" : "circle"
        let description = isOn ? String(localized: "main.on") : String(localized: "main.off")
        guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: description) else {
            return nil
        }
        base.isTemplate = true
        guard pwmPinned else { return base }

        let size = NSSize(width: 18, height: 18)
        let composed = NSImage(size: size, flipped: false) { rect in
            base.draw(in: NSRect(origin: .zero, size: size))
            let dotDiameter: CGFloat = 6
            let dotRect = NSRect(x: rect.maxX - dotDiameter, y: rect.minY, width: dotDiameter, height: dotDiameter)
            NSColor.black.setFill() // template image: shape/alpha is what matters, not the color
            NSBezierPath(ovalIn: dotRect).fill()
            return true
        }
        composed.isTemplate = true
        composed.accessibilityDescription = description
        return composed
    }
}
