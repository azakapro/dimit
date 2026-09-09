import AppKit

/// One borderless `NSWindow` per screen for brightness below the gamma
/// dim floor, or the entire visual effect in Fallback mode — CLAUDE.md
/// §3.5 / ARCHITECTURE.md §2.7. Keyed by display UUID, matching
/// `GammaController`'s baseline cache.
@MainActor
final class OverlayDimmer {
    private var windows: [String: NSWindow] = [:]

    /// Called on every `DisplayCoordinator.reapply()`, same cadence as
    /// `GammaController`. Creates/updates/removes windows to match
    /// `commands` exactly; a display with `overlayAlpha == 0` has no
    /// window at all rather than an invisible one sitting around.
    func sync(commands: [DisplayCommand], displays: [DisplayInfo]) {
        let uuidByID = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0.uuid) })
        var neededUUIDs: Set<String> = []

        for command in commands {
            guard command.overlayAlpha > 0 else { continue }
            guard let uuid = uuidByID[command.displayID] else { continue }
            guard let screen = Self.screen(for: command.displayID) else {
                Log.display.error("OverlayDimmer: no NSScreen for display \(command.displayID, privacy: .public)")
                continue
            }
            neededUUIDs.insert(uuid)

            let window = windowForDisplay(uuid: uuid, screen: screen)
            window.backgroundColor = color(for: command.overlayTint)
            window.alphaValue = command.overlayAlpha.clamped(to: 0...1)
            if window.frame != screen.frame {
                window.setFrame(screen.frame, display: true)
            }
            if !window.isVisible {
                window.orderFrontRegardless() // .screenSaver+1 level; regardless of key/main app state
            }
        }

        for uuid in Set(windows.keys).subtracting(neededUUIDs) {
            windows[uuid]?.orderOut(nil)
            windows.removeValue(forKey: uuid)
        }
    }

    /// ARCHITECTURE.md §2.7: "Recreated, not moved, on reconfiguration."
    /// Call when `DisplayManager.displays` changes (not on every routine
    /// `sync()`) — a fresh `NSWindow` avoids any stale backing-store/scale
    /// state a resolution or arrangement change could otherwise leave
    /// behind, at the cost of one extra window alloc on the rare event a
    /// display actually reconfigures.
    func handleDisplaysChanged() {
        for window in windows.values { window.orderOut(nil) }
        windows.removeAll()
    }

    func removeAll() {
        for window in windows.values { window.orderOut(nil) }
        windows.removeAll()
    }

    private func windowForDisplay(uuid: String, screen: NSScreen) -> NSWindow {
        if let existing = windows[uuid] { return existing }

        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.ignoresMouseEvents = true
        // .screenSaver + 1: above everything including the menu bar —
        // CLAUDE.md §3.5, literally.
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // Must be set here, before the window is ever ordered front — CLAUDE.md
        // §3.5: "setting it afterwards is unreliable on some versions."
        window.sharingType = .none
        window.hasShadow = false
        windows[uuid] = window
        return window
    }

    private func color(for tint: OverlayTint) -> NSColor {
        switch tint {
        case .black: return .black
        case .red: return NSColor(red: 1, green: 0, blue: 0, alpha: 1)
        }
    }

    /// Same `NSScreenNumber` matching technique as `DisplayManager` —
    /// verified against a live probe during C2 that this key's value
    /// equals the display's `CGDirectDisplayID`.
    private static func screen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
    }
}
