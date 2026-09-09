import CoreGraphics

/// Static facts about one connected display. Real enumeration
/// (`CGGetActiveDisplayList` etc.) lives in `DisplayManager`
/// (`Dimit/Display/DisplayManager.swift`); this stays a plain, mockable
/// struct so `Renderer` and `Applier` can be tested without touching
/// hardware.
struct DisplayInfo: Equatable, Identifiable {
    var id: CGDirectDisplayID
    var uuid: String
    var name: String
    var isBuiltin: Bool
    var isAppleDisplay: Bool
    var supportsDDC: Bool

    init(
        id: CGDirectDisplayID,
        uuid: String,
        name: String,
        isBuiltin: Bool = false,
        isAppleDisplay: Bool = false,
        supportsDDC: Bool = false
    ) {
        self.id = id
        self.uuid = uuid
        self.name = name
        self.isBuiltin = isBuiltin
        self.isAppleDisplay = isAppleDisplay
        self.supportsDDC = supportsDDC
    }
}

/// What `GammaController` should apply to one display. `dim` is the
/// software-brightness multiplier and is always within
/// `[Config.gammaDimFloor, 1.0]` — the C3 overlay carries brightness below
/// the floor, not gamma.
struct GammaSpec: Equatable {
    var multiplier: WarmthCurve.RGB
    var dim: Double
}

/// CLAUDE.md §3.5: "black with alpha" for extreme dim (gamma still does
/// the color, overlay only darkens below the floor), or "red-tinted
/// overlay" in Fallback mode, where gamma is left alone entirely and the
/// overlay carries the whole effect.
enum OverlayTint: Equatable {
    case black
    /// Fallback mode's red veil. `intensity` is the **red channel of the
    /// window's colour** (0…1), not its opacity — opacity is
    /// `DisplayCommand.overlayAlpha`. The two are separate because a single
    /// window has to stand in for two conceptual veils: a red one for
    /// warmth and a black one for dimming, applied in that order. Colour
    /// carries "how red", alpha carries "how much is hidden."
    case red(intensity: Double)
}

/// The full set of instructions for one display. `nil` fields mean "leave
/// this alone" so `Applier` can diff against the last-applied command and
/// only touch what changed.
struct DisplayCommand: Equatable {
    var displayID: CGDirectDisplayID
    /// `nil` means "restore to the original table" — true both for OFF
    /// and for Fallback mode, which deliberately leaves gamma at baseline
    /// (CLAUDE.md §3.3/ARCHITECTURE.md §2.7) and does all its work through
    /// `overlayTint`/`overlayAlpha` instead. `Applier` doesn't need to
    /// know which reason applies; both want the same "restore, then leave
    /// alone" behavior.
    var gamma: GammaSpec?
    /// 0 = no overlay window needed. Nonzero below `Config.gammaDimFloor`
    /// in normal mode, or whenever Fallback mode is on.
    var overlayAlpha: Double
    var overlayTint: OverlayTint = .black
    /// Intent, not a guarantee: the real pin/verify/retry state machine is
    /// `PWMSafeCoordinator`. `nil` = leave hardware brightness alone.
    var hardwareBrightness: Double?
}
