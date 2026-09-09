import Combine
import Foundation

/// Per-display state — CLAUDE.md §3.6 / ARCHITECTURE.md §2.6:
/// `off → pinning → pinned(verified) | unsupported | wontHold`.
enum PWMState: Equatable {
    case off
    case pinning
    case pinned
    case unsupported
    case wontHold
}

/// The PWM-Safe state machine. Tries `backends` in order (first
/// `canControl` wins) to pin each display's hardware brightness to 100%
/// so its backlight never enters a PWM-dimming range.
///
/// `pinVerifyDelay`/`pollInterval` are injectable so tests can use near-zero
/// delays and finish in milliseconds while still exercising the real async
/// code path (`DispatchQueue.main.asyncAfter`/`Timer`) against a fake
/// backend — not a separately-reimplemented "pure" version of this logic.
@MainActor
final class PWMSafeCoordinator: ObservableObject {
    @Published private(set) var states: [String: PWMState] = [:] // keyed by display UUID

    /// Fires once, the first time a pinned display is found to have
    /// drifted (CLAUDE.md §3.6: brightness-key press detection, "show
    /// ... once per session"). The UI observes this to show the toast.
    let repinnedToastSubject = PassthroughSubject<Void, Never>()

    private let backends: [BrightnessBackend]
    private let pinVerifyDelay: TimeInterval
    private let pollInterval: TimeInterval

    private var rememberedBrightness: [String: Float] = [:] // uuid -> brightness before pinning
    private var currentDisplays: [DisplayInfo] = []
    private var pollTimer: Timer?
    private var hasShownRepinnedToastThisSession = false

    /// Bumped every time a *fresh* pin chain starts for a display. Each
    /// async verification captures the generation it was scheduled under
    /// and drops out if it's since been superseded.
    ///
    /// This replaces an earlier `pendingVerifications: Set<String>` that
    /// three separate code-review angles independently flagged as
    /// write-only: it was inserted and removed but never actually read, so
    /// the "avoid overlapping attempts" its comment promised didn't exist.
    /// A plain set couldn't have delivered it either — after a disable
    /// clears a display's state and a re-enable starts a new chain for the
    /// same UUID, set membership can't distinguish the new chain's
    /// callback from the old chain's stale one. A generation counter can.
    private var pinGeneration: [String: Int] = [:]

    init(
        backends: [BrightnessBackend],
        pinVerifyDelay: TimeInterval = 0.3,
        pollInterval: TimeInterval = 5.0
    ) {
        self.backends = backends
        self.pinVerifyDelay = pinVerifyDelay
        self.pollInterval = pollInterval
    }

    /// Called on every `DisplayCoordinator.reapply()`. Only starts a fresh
    /// pin attempt for displays with no existing state (first enable, or a
    /// newly-connected display while PWM-Safe is already requested) —
    /// already-`.pinned`/`.pinning`/`.wontHold`/`.unsupported` displays are
    /// left alone here. Re-verification of already-pinned displays after
    /// wake/reconfiguration is handled by the periodic poll rather than a
    /// separate immediate hook: ARCHITECTURE.md §2.2 gives gamma a 1.0s
    /// immediate re-apply because a visibly wrong *color* for a second is
    /// jarring, but a backlight that's still at its pre-sleep level for up
    /// to one more poll interval (5s worst case) is a much smaller
    /// practical cost — a disclosed simplification, not an oversight.
    func sync(pwmSafeRequested: Bool, displays: [DisplayInfo]) {
        currentDisplays = displays

        guard pwmSafeRequested else {
            restoreAndDisable()
            return
        }

        for display in displays where states[display.uuid] == nil {
            beginPinning(display)
        }

        // Drop state for displays that disconnected while pinned/pinning —
        // nothing left to restore brightness on, and a reconnect (possibly
        // a different physical monitor reusing the slot) should start fresh.
        //
        // Guarded rather than assigned unconditionally: `states` is
        // `@Published`, and Combine republishes on *every* assignment
        // without diffing. This method runs on every `reapply()`, i.e. on
        // every slider tick, so an unconditional reassignment here made
        // `$states` fire constantly while pinned — which in turn made
        // MenuBarController rebuild the composited menu-bar icon (an
        // NSImage alloc plus a Core Graphics draw) dozens of times per
        // drag for an identical result. Code review caught both the cause
        // and that downstream symptom.
        let currentUUIDs = Set(displays.map(\.uuid))
        if states.keys.contains(where: { !currentUUIDs.contains($0) }) {
            states = states.filter { currentUUIDs.contains($0.key) }
        }
        if rememberedBrightness.keys.contains(where: { !currentUUIDs.contains($0) }) {
            rememberedBrightness = rememberedBrightness.filter { currentUUIDs.contains($0.key) }
        }

        startPollingIfNeeded()
    }

    /// Restores every pinned display's remembered brightness and clears all
    /// state. Public because quitting has to do this too, not just
    /// toggling PWM-Safe off: `DisplayServicesSetBrightness` changes the
    /// real hardware backlight, which outlives this process. Code review
    /// caught that `applicationWillTerminate` restored gamma and tore down
    /// overlays but left the backlight pinned at 100% — so quitting with
    /// PWM-Safe on left the user's screen stuck bright until they pressed
    /// a brightness key or relaunched. CLAUDE.md §3.6 ("On disable:
    /// restore remembered hardware brightness") means quit, too.
    func restoreAndDisable() {
        for display in currentDisplays {
            guard let remembered = rememberedBrightness[display.uuid],
                  let backend = backend(for: display)
            else { continue }
            _ = backend.set(display, remembered)
        }
        rememberedBrightness.removeAll()
        pinGeneration.removeAll() // invalidates any in-flight verification
        if !states.isEmpty { states.removeAll() }
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func backend(for display: DisplayInfo) -> BrightnessBackend? {
        backends.first { $0.canControl(display) }
    }

    /// `generation == nil` starts a fresh chain (allocating a new
    /// generation, invalidating any in-flight callback for this display);
    /// a retry passes its existing generation through so it stays part of
    /// the same chain.
    private func beginPinning(_ display: DisplayInfo, attemptsRemaining: Int = 3, generation: Int? = nil) {
        guard let backend = backend(for: display) else {
            states[display.uuid] = .unsupported
            return
        }

        let currentGeneration = generation ?? ((pinGeneration[display.uuid] ?? 0) + 1)
        pinGeneration[display.uuid] = currentGeneration

        // Capture what to restore to *before* pinning. If that read fails
        // we deliberately don't pin at all: code review caught that the
        // old code assigned `backend.get(display)` straight into the
        // dictionary, and assigning `nil` to a dictionary subscript
        // removes the key rather than storing a nil — so a single failed
        // read meant `restoreAndDisable()` would later skip this display
        // entirely, leaving the backlight stuck at 100% forever with no
        // error surfaced. Pinning without knowing how to undo it is worse
        // than not pinning.
        if rememberedBrightness[display.uuid] == nil {
            guard let original = backend.get(display) else {
                Log.display.error("PWM-Safe: could not read current brightness for \(display.uuid, privacy: .public); not pinning (nothing to restore to later)")
                scheduleRetryOrGiveUp(display, backend: backend, attemptsRemaining: attemptsRemaining, generation: currentGeneration)
                return
            }
            rememberedBrightness[display.uuid] = original
        }

        states[display.uuid] = .pinning
        let result = backend.set(display, 1.0)
        guard result == .ok else {
            Log.display.error("PWM-Safe: set(1.0) failed for \(display.uuid, privacy: .public): \(String(describing: result), privacy: .public)")
            scheduleRetryOrGiveUp(display, backend: backend, attemptsRemaining: attemptsRemaining, generation: currentGeneration)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + pinVerifyDelay) { [weak self] in
            self?.verifyPin(display, backend: backend, attemptsRemaining: attemptsRemaining, generation: currentGeneration)
        }
    }

    private func verifyPin(_ display: DisplayInfo, backend: BrightnessBackend, attemptsRemaining: Int, generation: Int) {
        // Drop stale callbacks from a superseded chain (e.g. PWM-Safe was
        // toggled off and back on inside the verify window).
        guard pinGeneration[display.uuid] == generation else { return }
        // The display may have disconnected or PWM-Safe may have been
        // turned off (which removes its entry from `states` entirely —
        // `.off` is never itself a stored value, only the UI-facing
        // default for "no entry") while this verification was in flight.
        guard currentDisplays.contains(where: { $0.uuid == display.uuid }) else { return }
        guard states[display.uuid] != nil else { return }

        let value = backend.get(display) ?? 0
        if value >= 0.99 {
            states[display.uuid] = .pinned
            // Must start here, not only at the end of `sync()`: `sync()`
            // returns long before this verification callback runs (it's
            // still `.pinning` when `sync()` checks), so relying only on
            // `sync()` to notice "something is pinned now" meant the timer
            // never started unless `sync()` happened to be called again
            // afterward — caught by the drift test actually failing.
            startPollingIfNeeded()
        } else {
            scheduleRetryOrGiveUp(display, backend: backend, attemptsRemaining: attemptsRemaining, generation: generation)
        }
    }

    /// Always waits `pinVerifyDelay` before the next attempt.
    ///
    /// Code review caught a real rule violation here: the failure paths
    /// that return *synchronously* (a `set()` that reports failure, or an
    /// unreadable initial brightness) used to recurse straight back into
    /// `beginPinning`, firing all three `backend.set()` calls back-to-back
    /// in one run-loop turn. CLAUDE.md §3.4: "Never call set-brightness
    /// more than 4×/second (some panels wear or lag)." Routing every retry
    /// through the same delay the verify path already used keeps the
    /// worst case at 3 sets over ~0.6s, comfortably inside that.
    private func scheduleRetryOrGiveUp(_ display: DisplayInfo, backend: BrightnessBackend, attemptsRemaining: Int, generation: Int) {
        guard attemptsRemaining > 1 else {
            states[display.uuid] = .wontHold
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + pinVerifyDelay) { [weak self] in
            guard let self, self.pinGeneration[display.uuid] == generation else { return }
            self.beginPinning(display, attemptsRemaining: attemptsRemaining - 1, generation: generation)
        }
    }

    // MARK: - Drift polling (CLAUDE.md §3.6: "poll every 5s while pinned")

    private func startPollingIfNeeded() {
        guard pollTimer == nil else { return }
        guard states.values.contains(.pinned) else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForDrift()
            }
        }
    }

    private func checkForDrift() {
        var stillAnyPinned = false
        for display in currentDisplays {
            guard states[display.uuid] == .pinned, let backend = backend(for: display) else { continue }
            stillAnyPinned = true
            let value = backend.get(display) ?? 0
            guard value < 0.99 else { continue }

            // Drifted — most likely the user pressed a hardware brightness
            // key. Re-pin (as a fresh chain, so any straggler callback
            // from a previous chain is invalidated), and surface the toast
            // once per session.
            if !hasShownRepinnedToastThisSession {
                hasShownRepinnedToastThisSession = true
                repinnedToastSubject.send()
            }
            beginPinning(display)
        }
        if !stillAnyPinned {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }
}

extension PWMSafeCoordinator {
    /// One state to show in a single-summary UI surface (the popover's PWM
    /// row, the menu bar icon's dot) when there may be several displays
    /// each with their own state. Problems surface before successes —
    /// `.wontHold` on any display is worth the user's attention even if
    /// every other display pinned fine; `.pinning` (in progress) comes
    /// next so "waiting" doesn't get masked by a display that already
    /// succeeded; `.unsupported` only shows when nothing at all is pinned
    /// (a mixed Apple-display-plus-unsupported-external setup should still
    /// read as working, not as a warning).
    var summaryState: PWMState? {
        guard !states.isEmpty else { return nil }
        if states.values.contains(.wontHold) { return .wontHold }
        if states.values.contains(.pinning) { return .pinning }
        if states.values.contains(.pinned) { return .pinned }
        if states.values.contains(.unsupported) { return .unsupported }
        return nil
    }
}
