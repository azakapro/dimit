import AppKit

/// What `DisplayCoordinator` needs from the overlay. A test seam only —
/// see `DisplayProviding` for why the coordinator's lifecycle needs one.
@MainActor
protocol OverlayDimming {
    func sync(commands: [DisplayCommand], displays: [DisplayInfo])
    func handleDisplaysChanged()
    func removeAll()
}

/// One borderless black `NSWindow` per screen for brightness below the
/// gamma dim floor — CLAUDE.md §3.5 / ARCHITECTURE.md §2.7. Keyed by
/// display UUID, matching `GammaController`'s baseline cache.
@MainActor
final class OverlayDimmer: OverlayDimming {
    private var windows: [String: NSWindow] = [:]
    /// The alpha each window is currently showing. Code review caught
    /// `sync()` writing `alphaValue` unconditionally on every call — and
    /// `sync()` runs on every `reapply()`, i.e. every slider tick — which
    /// pushed a real window-server round trip per tick for an unchanged
    /// value, exactly the per-tick I/O the gamma path uses `Applier`'s
    /// diff to avoid. This is the same idea, one layer down.
    private var appliedAlphaByUUID: [String: Double] = [:]

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
            let wanted = command.overlayAlpha.clamped(to: 0...1)
            if appliedAlphaByUUID[uuid] != wanted {
                window.alphaValue = wanted
                appliedAlphaByUUID[uuid] = wanted
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
            appliedAlphaByUUID.removeValue(forKey: uuid)
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
        appliedAlphaByUUID.removeAll()
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
        // Always black; opacity comes from `alphaValue` (CLAUDE.md §3.5).
        window.backgroundColor = .black
        windows[uuid] = window
        return window
    }
}
