import Foundation

/// Product-wide constants. CLAUDE.md §2: "product name and bundle ID as
/// constants in Config.swift." Everything else that varies by cycle
/// (pricing, API host, feature flags) is added here as that cycle lands —
/// see the `// C4`, `// C5` etc. markers below for what's still to come.
enum Config {
    static let productName = "Dimit"
    static let bundleID = "app.dimit.mac"

    // MARK: - Warmth (CLAUDE.md §3.2)
    static let minWarmthK: Double = 0
    static let maxWarmthK: Double = 6500

    // MARK: - Brightness (CLAUDE.md §1, §3.3)
    static let minBrightness: Double = 0.10
    static let maxBrightness: Double = 1.0
    /// Below this, gamma dimming bands and loses text; the C3 overlay takes over.
    static let gammaDimFloor: Double = 0.30

    /// The most of the screen Fallback mode's red veil may hide at 0K,
    /// before dimming is applied on top. Strictly below 1: Fallback exists
    /// for displays whose gamma is already broken, so it must never leave
    /// the user staring at an opaque rectangle with no way back to the menu
    /// bar. At this value 0K keeps 30% of the real screen visible, and the
    /// NIGHT preset (0K at 40%) keeps 12%.
    static let fallbackMaxWarmthVeil: Double = 0.70

    // MARK: - Hotkey step sizes (CLAUDE.md §3.9, C4)
    // Named here (not inlined in HotkeyManager) so a future stepper button
    // in the UI can't drift from what the hotkey does for the same action.
    static let warmthHotkeyStepK: Double = 100 // matches the popover slider's own step
    static let brightnessHotkeyStep: Double = 0.05

    // MARK: - Not wired up yet, flags reserved so later cycles don't rename things
    static var ddcEnabled = false // C5, experimental, default OFF per CLAUDE.md §3.4
}
