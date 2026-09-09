import AppKit

/// What `DisplayCoordinator` needs from the overlay. A test seam only —
/// see `DisplayProviding` for why the coordinator's lifecycle needs one.
@MainActor
protocol OverlayDimming {
    func sync(commands: [DisplayCommand], displays: [DisplayInfo])
    func handleDisplaysChanged()
    func removeAll()
}

/// One borderless `NSWindow` per screen for brightness below the gamma
/// dim floor, or the entire visual effect in Fallback mode — CLAUDE.md
/// §3.5 / ARCHITECTURE.md §2.7. Keyed by display UUID, matching
/// `GammaController`'s baseline cache.
@MainActor
final class OverlayDimmer: OverlayDimming {
    private struct Applied: Equatable {
        var tint: OverlayTint
        var alpha: Double
    }

    private var windows: [String: NSWindow] = [:]
    /// What each window is currently showing. Code review caught `sync()`
    /// writing `backgroundColor`/`alphaValue` unconditionally on every
    /// call — and `sync()` runs on every `reapply()`, i.e. every slider
    /// tick. With Fallback mode on (where the overlay is always active),
    /// that pushed a real window-server round trip per tick for an
    /// unchanged value, exactly the per-tick I/O the gamma path uses
    /// `Applier`'s diff to avoid. This is the same idea, one layer down.
    private var appliedByUUID: [String: Applied] = [:]

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
            guard let screen = NSScreen.matching(displayID: command.displayID) else {
                Log.display.error("OverlayDimmer: no NSScreen for display \(command.displayID, privacy: .public)")
                continue
            }
            neededUUIDs.insert(uuid)

            let window = windowForDisplay(uuid: uuid, screen: screen)
            let wanted = Applied(tint: command.overlayTint, alpha: command.overlayAlpha.clamped(to: 0...1))
            if appliedByUUID[uuid] != wanted {
                window.backgroundColor = color(for: wanted.tint)
                window.alphaValue = wanted.alpha
                appliedByUUID[uuid] = wanted
            }
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
            appliedByUUID.removeValue(forKey: uuid)
        }
    }

    /// ARCHITECTURE.md §2.7: "Recreated, not moved, on reconfiguration."
    /// Call when `DisplayManager.displays` changes (not on every routine
    /// `sync()`) — a fresh `NSWindow` avoids any stale backing-store/scale
    /// state a resolution or arrangement change could otherwise leave
    /// behind, at the cost of one extra window alloc on the rare event a
    /// display actually reconfigures.
    func handleDisplaysChanged() {
        removeAll()
    }

    func removeAll() {
        for window in windows.values { window.orderOut(nil) }
        windows.removeAll()
        appliedByUUID.removeAll()
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
        // Opacity comes from the window's alphaValue, not from here — this
        // colour is fully opaque and only carries "how red."
        case .red(let intensity): return NSColor(red: intensity, green: 0, blue: 0, alpha: 1)
        }
    }
}
