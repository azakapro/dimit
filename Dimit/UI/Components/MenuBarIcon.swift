import AppKit

/// CLAUDE.md §3.9: "outline when OFF, filled when ON, small dot when PWM
/// pinned." This is a placeholder using SF Symbols — a custom-drawn glyph
/// with the pinned-dot is C3's job (`PWMSafeCoordinator` lands then, so
/// there is no pinned state to show yet). The point of building this now is
/// just to prove the status item updates when `isOn` changes.
enum MenuBarIcon {
    static func image(isOn: Bool) -> NSImage? {
        let symbolName = isOn ? "circle.fill" : "circle"
        let description = isOn ? String(localized: "main.on") : String(localized: "main.off")
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        image?.isTemplate = true // follows menu bar light/dark tint automatically
        return image
    }
}
