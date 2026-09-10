import AppKit

/// CLAUDE.md §3.9: "outline when OFF, filled when ON, small dot when PWM
/// pinned." SF Symbols for the base shape (still a placeholder — a real
/// custom glyph is visual-design polish for a later pass); the pinned dot
/// is drawn by hand and composited on top, since there's no single SF
/// Symbol that reliably means exactly "this, plus a small corner dot"
/// across macOS versions.
enum MenuBarIcon {
    /// `accessibilityDescription` is passed in already resolved rather than
    /// looked up here: `String(localized:)` would resolve against the system
    /// language, so VoiceOver announced the status item as "ON" while the
    /// menu it opens said "ВКЛ" (code review).
    static func image(isOn: Bool, pwmPinned: Bool = false, accessibilityDescription: String) -> NSImage? {
        let symbolName = isOn ? "circle.fill" : "circle"
        guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription) else {
            return nil
        }
        base.isTemplate = true
        guard pwmPinned else { return base }

        // The canvas is the base symbol's own size, not a fixed 18×18 as an
        // earlier version used. `circle`/`circle.fill` come back at 15×15,
        // so that hard-coded size silently scaled the glyph up by 20% and
        // the menu-bar icon visibly *grew* the moment PWM-Safe pinned —
        // reported as "when it is on ... in bottom something appears", and
        // confirmed by rendering both states side by side.
        let size = base.size
        let composed = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)

            // ARCHITECTURE.md §10: "3 pt dot at the lower right" on a 16 pt
            // icon. Kept as that ratio rather than a literal 3, so the dot
            // stays proportional if the base symbol's size ever changes.
            // The earlier literal 6 was over twice this on an 18pt canvas.
            let dotDiameter = (rect.width * 3 / 16).rounded()
            let dotRect = NSRect(x: rect.maxX - dotDiameter, y: rect.minY, width: dotDiameter, height: dotDiameter)

            // Punch a slightly larger hole before filling the dot. Without
            // this the dot merges into `circle.fill` and the pair reads as
            // one lopsided blob instead of a badge — the actual thing that
            // looked wrong on screen. `.destinationOut` erases wherever the
            // path covers; the colour is irrelevant, only its alpha.
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dotRect.insetBy(dx: -1, dy: -1)).fill()

            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill() // template image: shape/alpha is what matters, not the color
            NSBezierPath(ovalIn: dotRect).fill()
            return true
        }
        composed.isTemplate = true
        composed.accessibilityDescription = accessibilityDescription
        return composed
    }
}
