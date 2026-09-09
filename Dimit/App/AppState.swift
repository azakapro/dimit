import Combine
import Foundation

/// The single mutable source of truth — ARCHITECTURE.md §2 "AppState is the
/// only mutable source of truth. UI mutates it; a single apply() pipeline
/// reacts to it. No UI code calls a controller directly."
///
/// Deviation from CLAUDE.md §3.7, disclosed: the spec says `@Observable`
/// (Swift's Observation framework), but that macro requires macOS 14+ and
/// CLAUDE.md §2 fixes the deployment target at macOS 13 (deliberately, to
/// match Tap Zap minus its documented macOS-12 slider bugs). `ObservableObject`
/// + `@Published` gives the same "UI observes state" shape and has worked
/// since macOS 10.15, so it is used here instead. If the minimum target
/// ever moves to 14, this is a mechanical swap.
///
/// Only the fields C1 actually uses are here. `schedule`, `hotkeys`,
/// `launchAtLogin`, `updateChecks`, `locale`, `perDisplayOverrides` from
/// CLAUDE.md §3.7 arrive with the cycles that implement them (C4/C5/C7) —
/// adding a `Codable` field with a default later does not break
/// already-persisted JSON, so there is no reason to stub out types that
/// don't exist yet (`ScheduleConfig` etc.).
@MainActor
final class AppState: ObservableObject {
    @Published var isOn: Bool { didSet { handleIsOnChanged(wasOn: oldValue) } }
    @Published var warmthK: Double { didSet { clearPresetIfDrifted() } }
    @Published var brightness: Double { didSet { clearPresetIfDrifted() } }
    @Published var pwmSafe: Bool
    /// CLAUDE.md §3.3/§3.5: the escape hatch for when gamma itself is
    /// broken (macOS 26-class bugs) — tints via `OverlayDimmer` instead of
    /// gamma tables, and gamma is left untouched while this is on.
    @Published var fallbackMode: Bool
    @Published var activePreset: PresetID?

    /// CLAUDE.md §3.3: "show a one-time banner ... on macOS ≥ 26 the first
    /// time the filter is turned ON, dismissable forever." No reliable
    /// detection key for auto-brightness was found on this macOS 27 beta
    /// (checked directly: `defaults read com.apple.BezelServices dAuto`
    /// returns no such key, and nothing else in `com.apple.CoreBrightness`
    /// tracked it either) — CLAUDE.md's own §3.3 anticipates exactly this
    /// outcome and specifies the unconditional fallback, which is what
    /// this implements.
    @Published private(set) var showAutoBrightnessBanner = false

    private let persistence: Persistence
    private var saveCancellable: AnyCancellable?

    init(persistence: Persistence = .shared) {
        self.persistence = persistence
        let saved = persistence.load()
        self.isOn = saved.isOn
        self.warmthK = saved.warmthK
        self.brightness = saved.brightness
        self.pwmSafe = saved.pwmSafe
        self.fallbackMode = saved.fallbackMode
        self.activePreset = saved.activePreset.flatMap(PresetID.init(rawValue:))

        // Debounced 250ms persistence — CLAUDE.md §3.7. `objectWillChange`
        // fires on every @Published mutation, so this one subscription
        // covers all of them without listing each property twice.
        saveCancellable = objectWillChange
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.persist() }
    }

    /// Sets warmth, brightness and the active-preset marker together.
    /// Moving a slider afterwards clears `activePreset` (see `warmthK`/
    /// `brightness` `didSet` below) so the preset picker stops highlighting
    /// a preset the user has since drifted away from.
    ///
    /// `activePreset = preset` runs last and unconditionally, *after*
    /// `warmthK`/`brightness`'s own `didSet` has already had a chance to
    /// clear it — so it always wins regardless of what came before. An
    /// earlier version guarded this with an `isSettingPreset` flag; code
    /// review pointed out the guard was provably redundant (verified: the
    /// final explicit assignment overwrites the `didSet` chain's effect
    /// either way) and, worse, a stuck-`true` footgun if a future edit ever
    /// added an early return between setting and clearing the flag.
    func apply(preset: PresetID) {
        warmthK = preset.warmthK
        brightness = preset.brightness
        activePreset = preset
    }

    private func clearPresetIfDrifted() {
        guard activePreset != nil else { return }
        activePreset = nil
    }

    private func handleIsOnChanged(wasOn: Bool) {
        guard isOn, !wasOn else { return } // only the OFF -> ON transition
        guard !persistence.hasShownAutoBrightnessBanner else { return }
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 else { return }
        showAutoBrightnessBanner = true
    }

    /// The banner's dismiss button. "Dismissable forever" per CLAUDE.md
    /// §3.3 — persisted immediately (not debounced with the rest of state)
    /// since this is a one-time UI event, not a value `Renderer` reads.
    func dismissAutoBrightnessBanner() {
        showAutoBrightnessBanner = false
        persistence.hasShownAutoBrightnessBanner = true
    }

    /// Writes current state immediately, bypassing the 250 ms debounce.
    ///
    /// Without this, any change made in the last 250 ms before quit was
    /// silently lost: `objectWillChange` had fired, but the debounced sink
    /// never got to run before the process went away. That directly breaks
    /// C1's "state survives relaunch" criterion for the most common case
    /// there is — flip something, immediately quit. Called from
    /// `applicationWillTerminate`.
    func flush() {
        persist()
    }

    private func persist() {
        persistence.save(
            PersistedState(
                isOn: isOn,
                warmthK: warmthK,
                brightness: brightness,
                pwmSafe: pwmSafe,
                fallbackMode: fallbackMode,
                activePreset: activePreset?.rawValue
            )
        )
    }

    var renderState: RenderState {
        RenderState(isOn: isOn, warmthK: warmthK, brightness: brightness, pwmSafe: pwmSafe, fallbackMode: fallbackMode)
    }
}
