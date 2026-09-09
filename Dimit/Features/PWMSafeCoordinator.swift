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
    private var pendingVerifications: Set<String> = [] // uuids with an in-flight asyncAfter, to avoid overlapping attempts

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
            disableAll()
            return
        }

        for display in displays where states[display.uuid] == nil {
            beginPinning(display)
        }

        // Drop state for displays that disconnected while pinned/pinning —
        // nothing left to restore brightness on, and a reconnect (possibly
        // a different physical monitor reusing the slot) should start fresh.
        let currentUUIDs = Set(displays.map(\.uuid))
        states = states.filter { currentUUIDs.contains($0.key) }
        rememberedBrightness = rememberedBrightness.filter { currentUUIDs.contains($0.key) }

        startPollingIfNeeded()
    }

    private func disableAll() {
        for display in currentDisplays {
            guard let remembered = rememberedBrightness[display.uuid],
                  let backend = backend(for: display)
            else { continue }
            _ = backend.set(display, remembered)
        }
        rememberedBrightness.removeAll()
        states.removeAll()
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func backend(for display: DisplayInfo) -> BrightnessBackend? {
        backends.first { $0.canControl(display) }
    }

    private func beginPinning(_ display: DisplayInfo, attemptsRemaining: Int = 3) {
        guard let backend = backend(for: display) else {
            states[display.uuid] = .unsupported
            return
        }

        if rememberedBrightness[display.uuid] == nil {
            rememberedBrightness[display.uuid] = backend.get(display)
        }

        states[display.uuid] = .pinning
        let result = backend.set(display, 1.0)
        guard result == .ok else {
            Log.display.error("PWM-Safe: set(1.0) failed for \(display.uuid, privacy: .public): \(String(describing: result), privacy: .public)")
            retryOrGiveUp(display, backend: backend, attemptsRemaining: attemptsRemaining)
            return
        }

        pendingVerifications.insert(display.uuid)
        DispatchQueue.main.asyncAfter(deadline: .now() + pinVerifyDelay) { [weak self] in
            self?.verifyPin(display, backend: backend, attemptsRemaining: attemptsRemaining)
        }
    }

    private func verifyPin(_ display: DisplayInfo, backend: BrightnessBackend, attemptsRemaining: Int) {
        pendingVerifications.remove(display.uuid)
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
            retryOrGiveUp(display, backend: backend, attemptsRemaining: attemptsRemaining)
        }
    }

    private func retryOrGiveUp(_ display: DisplayInfo, backend: BrightnessBackend, attemptsRemaining: Int) {
        if attemptsRemaining > 1 {
            beginPinning(display, attemptsRemaining: attemptsRemaining - 1)
        } else {
            states[display.uuid] = .wontHold
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
            // key. Re-pin, and surface the toast once per session.
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
