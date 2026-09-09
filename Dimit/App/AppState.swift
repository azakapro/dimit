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

    /// C4/CLAUDE.md §3.7: "User-editable; 'reset to defaults'." Only
    /// presets that differ from `PresetID.defaultValues` need an entry —
    /// read through `values(for:)`, never this dictionary directly, so
    /// "no override" and "override that happens to equal the default"
    /// aren't two states callers have to distinguish.
    @Published private(set) var presetOverrides: [PresetID: PresetValues] = [:]

    /// C4/CLAUDE.md §5: "Settings has a language override." `nil` follows
    /// the system language. `PopoverView`/`SettingsView`/`OnboardingView`
    /// all read this via `effectiveLocale` and apply it with
    /// `.environment(\.locale, ...)` at their SwiftUI root — this works
    /// live, without relaunching, because `Text(LocalizedStringResource)`
    /// resolves String Catalog lookups against the environment's locale
    /// when one is set (confirmed against Xcode 15+'s documented
    /// behavior). This is a disclosed deviation from CLAUDE.md §5's literal
    /// "AppleLanguages-free: we store locale and set Bundle on relaunch" —
    /// `PopoverView`'s own C1 comment already anticipated exactly this path
    /// ("how C4's in-app language override will need to work"), so this
    /// cycle follows through on that rather than introducing a relaunch.
    @Published var locale: String?

    /// C4/ARCHITECTURE.md §10: the onboarding opt-in checkbox persists
    /// here. CLAUDE.md §1.2: "Sparkle update check is opt-in and
    /// explained" — Sparkle itself doesn't exist until C7; this cycle only
    /// stores the user's choice for C7 to read, with no network effect of
    /// its own.
    @Published var updateChecksEnabled: Bool

    /// C5/CLAUDE.md §3.8. `ScheduleCoordinator` is the only thing that
    /// reads this to drive anything; AppState itself has no scheduling
    /// logic, same separation as everything else it holds.
    @Published var scheduleConfig: ScheduleConfig

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
        self.presetOverrides = Dictionary(
            uniqueKeysWithValues: saved.presetOverrides.compactMap { key, value in
                PresetID(rawValue: key).map { ($0, value) }
            }
        )
        self.locale = saved.locale
        self.updateChecksEnabled = saved.updateChecksEnabled
        self.scheduleConfig = saved.scheduleConfig

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
        let effective = values(for: preset)
        warmthK = effective.warmthK
        brightness = effective.brightness
        activePreset = preset
    }

    private func clearPresetIfDrifted() {
        guard activePreset != nil else { return }
        activePreset = nil
    }

    // MARK: - Preset editing (C4, CLAUDE.md §3.7 "user-editable; reset to defaults")

    /// The values `apply(preset:)` actually uses: the user's override if
    /// one exists, otherwise `PresetID.defaultValues`. Settings' preset
    /// editor and `apply(preset:)` both go through this so there is one
    /// place that knows "override wins."
    func values(for preset: PresetID) -> PresetValues {
        presetOverrides[preset] ?? preset.defaultValues
    }

    /// Settings' preset editor calls this as the user drags its sliders.
    /// If the result exactly matches the built-in default, the override is
    /// removed rather than stored — keeps `presetOverrides` (and the
    /// persisted JSON) containing only presets that actually differ,
    /// and means dragging back to the default value behaves exactly like
    /// pressing "Reset."
    func setPresetValues(_ values: PresetValues, for preset: PresetID) {
        if values == preset.defaultValues {
            presetOverrides.removeValue(forKey: preset)
        } else {
            presetOverrides[preset] = values
        }
        // If this is the currently-active preset, live-update the sliders
        // too — otherwise Settings and the popover would disagree about
        // what "NIGHT" currently means until the user re-taps the preset.
        // Re-assigns `activePreset` last and unconditionally, same as
        // `apply(preset:)` above and for the same reason: `warmthK`'s and
        // `brightness`'s own `didSet` unconditionally clear it the moment
        // either changes, so without this final assignment editing the
        // active preset's own sliders would immediately un-highlight it.
        if activePreset == preset {
            warmthK = values.warmthK
            brightness = values.brightness
            activePreset = preset
        }
    }

    func resetPreset(_ preset: PresetID) {
        setPresetValues(preset.defaultValues, for: preset)
    }

    func resetAllPresets() {
        for preset in PresetID.allCases { resetPreset(preset) }
    }

    // MARK: - Hotkey adjustments (C4, CLAUDE.md §3.9)

    /// DAY -> EVENING -> NIGHT -> DAY. If no preset is currently active
    /// (the user has drifted the sliders away from all three), starts back
    /// at DAY rather than guessing which preset is "closest" — CLAUDE.md
    /// doesn't specify a nearest-match behavior, and picking DAY is at
    /// least predictable.
    func cycleToNextPreset() {
        let all = PresetID.allCases
        guard let current = activePreset, let index = all.firstIndex(of: current) else {
            apply(preset: all[0])
            return
        }
        apply(preset: all[(index + 1) % all.count])
    }

    /// `Config.warmthHotkeyStep`/`brightnessHotkeyStep` name the step size
    /// in one place so the hotkey and any future stepper UI can't drift
    /// apart. Clamping matches the sliders' own ranges.
    func adjustWarmth(by delta: Double) {
        warmthK = (warmthK + delta).clamped(to: Config.minWarmthK...Config.maxWarmthK)
    }

    func adjustBrightness(by delta: Double) {
        brightness = (brightness + delta).clamped(to: Config.minBrightness...Config.maxBrightness)
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
                activePreset: activePreset?.rawValue,
                presetOverrides: Dictionary(
                    uniqueKeysWithValues: presetOverrides.map { ($0.key.rawValue, $0.value) }
                ),
                locale: locale,
                updateChecksEnabled: updateChecksEnabled,
                scheduleConfig: scheduleConfig
            )
        )
    }

    var renderState: RenderState {
        RenderState(isOn: isOn, warmthK: warmthK, brightness: brightness, pwmSafe: pwmSafe, fallbackMode: fallbackMode)
    }

    /// What to hand `.environment(\.locale, ...)` at each SwiftUI root.
    /// `nil` `locale` means "follow the system" — `Locale.autoupdatingCurrent`
    /// rather than `Locale.current`, so the override also un-does cleanly if
    /// the user picks a language and later switches back to "System"
    /// without needing a relaunch.
    var effectiveLocale: Locale {
        locale.map(Locale.init(identifier:)) ?? .autoupdatingCurrent
    }

    /// For the AppKit surfaces that can't read SwiftUI's environment —
    /// the right-click menu, window titles, the toast. `String(localized:)`
    /// on its own resolves against the *system* language and would ignore
    /// the override; setting the resource's `locale` first makes it honour
    /// the same choice the SwiftUI views do.
    func localized(_ key: LocalizedStringResource) -> String {
        var resource = key
        resource.locale = effectiveLocale
        return String(localized: resource)
    }

    /// Same, for catalog entries with `%@`/`%d` placeholders. Exists so no
    /// call site has to reach for `String(format: String(localized:))`,
    /// which resolves against the *system* language and silently ignores
    /// the override — code review found three sites that had already done
    /// exactly that, inside views the override was otherwise reaching.
    func localized(_ key: LocalizedStringResource, _ arguments: CVarArg...) -> String {
        String(format: localized(key), arguments: arguments)
    }
}
