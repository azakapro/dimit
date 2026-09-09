import Combine
import CoreGraphics

/// The apply pipeline — ARCHITECTURE.md §2.1. Owns nothing about *how* to
/// enumerate displays or touch gamma/brightness/overlay (that's
/// `DisplayManager` / `GammaController` / `PWMSafeCoordinator` /
/// `OverlayDimmer`); this just wires "something changed" to
/// "render, diff, apply."
///
/// Subscribes to `appState.objectWillChange` rather than each individual
/// `@Published` property: `objectWillChange` fires in `willSet`, before the
/// new value is stored, so reading `appState.renderState` *inside* a
/// synchronous sink would see the *old* value. `.receive(on: .main)`
/// defers the read to the next run-loop turn, by which point the
/// synchronous write has long since completed. This also means a single
/// user action that sets several `@Published` fields in a row (e.g.
/// `AppState.apply(preset:)` setting `warmthK`, then `brightness`, then
/// `activePreset`) can trigger this pipeline more than once — Applier's
/// diff makes every call after the first a no-op once state has settled,
/// so this doesn't cost extra `CGSetDisplayTransferByTable` calls, only a
/// few redundant (cheap) `Renderer.render` calls.
@MainActor
final class DisplayCoordinator {
    private let appState: AppState
    private let displayManager: DisplayManager
    private let gammaController: GammaController
    // Private: MenuBarController and PopoverView get their own reference to
    // the same instance directly from AppDelegate, so exposing it here too
    // was dead surface area that invited two different paths to the same
    // object (code review).
    private let pwmSafeCoordinator: PWMSafeCoordinator
    private let overlayDimmer: OverlayDimmer

    private var lastApplied: [DisplayCommand] = []
    private var lastDisplayUUIDs: Set<String> = []
    private var cancellables = Set<AnyCancellable>()

    init(
        appState: AppState,
        displayManager: DisplayManager,
        gammaController: GammaController,
        pwmSafeCoordinator: PWMSafeCoordinator,
        overlayDimmer: OverlayDimmer
    ) {
        self.appState = appState
        self.displayManager = displayManager
        self.gammaController = gammaController
        self.pwmSafeCoordinator = pwmSafeCoordinator
        self.overlayDimmer = overlayDimmer

        appState.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reapply() }
            .store(in: &cancellables)

        displayManager.$displays
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reapply() }
            .store(in: &cancellables)

        // Apply once for whatever state was already loaded at launch (e.g.
        // isOn restored true from a previous session) rather than waiting
        // for the first change.
        reapply()
    }

    private func reapply() {
        let displays = displayManager.displays
        let currentUUIDs = Set(displays.map(\.uuid))
        gammaController.evictBaselines(keepingOnly: currentUUIDs)

        // ARCHITECTURE.md §2.7: overlay windows are "recreated, not moved,
        // on reconfiguration." Detected here (not inside OverlayDimmer)
        // since this is the one place that already tracks "did the
        // display list change" for baseline eviction — same signal, two
        // consumers.
        if currentUUIDs != lastDisplayUUIDs {
            overlayDimmer.handleDisplaysChanged()
            lastDisplayUUIDs = currentUUIDs
        }

        let uuidByID = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0.uuid) })
        let commands = Renderer.render(appState.renderState, displays: displays)
        let diff = Applier.diff(previous: lastApplied, current: commands)

        // Restore BEFORE apply, not after. `CGDisplayRestoreColorSyncSettings()`
        // is global — it restores every display, not just the ones in
        // `diff.toRestore` (`Applier.swift`'s own doc comment says so).
        // `Renderer`'s single global `isOn` flag can't produce a mixed
        // toApply+toRestore diff *today*, so the order was invisible in
        // testing, but `Applier` is already built and tested for that mix
        // (`ApplierTests.test_multipleDisplays_mixedTransitions`), and
        // AppState's own roadmap (CLAUDE.md §3.7 `perDisplayOverrides`)
        // plans to produce exactly that mix eventually. Restoring first
        // means a future per-display toApply is never silently wiped by a
        // same-pass restore of a different display — caught in code review
        // before it could ever matter, not after.
        if !diff.toRestore.isEmpty {
            gammaController.restoreAll()
        }

        // Record what we actually achieved, not what we attempted — code
        // review caught `lastApplied = commands` unconditionally recording
        // success even for a failed `apply()` (no baseline, or the
        // CoreGraphics call itself failing). That would have made a
        // failure permanent: the next `reapply()` computes the same
        // `GammaSpec`, `Applier.diff` sees "unchanged" against the
        // wrongly-recorded success, and the display never gets retried.
        // Failed displays instead keep their previous `lastApplied` entry,
        // so the *next* state or display-list change (or nothing at all —
        // `objectWillChange` fires often enough on its own) looks like a
        // real change again and retries.
        let previousByID = Dictionary(uniqueKeysWithValues: lastApplied.map { ($0.displayID, $0) })
        var nextApplied: [DisplayCommand] = []
        for command in commands {
            let isBeingApplied = diff.toApply.contains { $0.displayID == command.displayID }
            guard isBeingApplied else {
                nextApplied.append(command)
                continue
            }
            guard let uuid = uuidByID[command.displayID] else {
                Log.display.error("display \(command.displayID, privacy: .public) in render output has no known UUID; skipping apply")
                nextApplied.append(previousByID[command.displayID] ?? command)
                continue
            }
            let succeeded = gammaController.apply(command, uuid: uuid)
            nextApplied.append(succeeded ? command : (previousByID[command.displayID] ?? command))
        }
        lastApplied = nextApplied

        // Overlay and PWM-Safe are independent of the gamma apply/restore
        // above — both run unconditionally off the freshly rendered
        // `commands`/`displays`, not off `diff`, since neither has a
        // "skip if unchanged" optimization as cheap as Applier's (an
        // NSWindow's alphaValue/backgroundColor set is trivial; a
        // brightness-backend set is the one PWMSafeCoordinator itself
        // already guards internally, per-display, against redundant work).
        overlayDimmer.sync(commands: commands, displays: displays)
        pwmSafeCoordinator.sync(pwmSafeRequested: appState.isOn && appState.pwmSafe, displays: displays)
    }

    /// The right-click menu's "Restore colours" — a manual safety valve,
    /// independent of `isOn` (CLAUDE.md's onboarding also gets one "for
    /// safety"). Turns the filter off *and* forces an immediate restore,
    /// rather than only flipping `isOn` and waiting for the async
    /// `objectWillChange` hop: this is explicitly a panic button, so it
    /// shouldn't depend on the normal pipeline's timing to take effect.
    ///
    /// `lastApplied` is updated here too, synchronously — code review
    /// caught that without this, the deferred `reapply()` triggered by
    /// `appState.isOn = false` (it runs on the next run-loop turn, per this
    /// class's own doc comment) leaves a window where `lastApplied` still
    /// says gamma is on. If something turned the filter back on with the
    /// exact same values in that window, `Applier.diff` would see no
    /// change and skip re-applying — the display would silently stay
    /// restored while `AppState.isOn` and the UI both said ON.
    func restoreColours() {
        appState.isOn = false
        gammaController.restoreAll()
        overlayDimmer.removeAll()
        // Un-pin synchronously too. Code review pointed out this function's
        // own rationale — "shouldn't depend on the normal pipeline's timing
        // to take effect" — applied to gamma and the overlay but not to the
        // backlight, which was left to the deferred reapply(). A panic
        // button should put every part of the display back at once.
        pwmSafeCoordinator.restoreAndDisable()
        lastApplied = lastApplied.map { command in
            var restored = command
            restored.gamma = nil
            return restored
        }
    }
}
