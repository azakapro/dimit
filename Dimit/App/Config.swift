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

    // MARK: - Not wired up yet, flags reserved so later cycles don't rename things
    static var ddcEnabled = false // C5, experimental, default OFF per CLAUDE.md §3.4
}
