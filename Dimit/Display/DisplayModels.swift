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

/// The full set of instructions for one display. `nil` fields mean "leave
/// this alone" so `Applier` can diff against the last-applied command and
/// only touch what changed.
struct DisplayCommand: Equatable {
    var displayID: CGDirectDisplayID
    /// `nil` means "restore to the original table" (OFF). `Applier` then
    /// leaves gamma alone until a non-nil spec arrives.
    var gamma: GammaSpec?
    /// 0 = no overlay window needed. Nonzero only below
    /// `Config.gammaDimFloor`, where a black overlay carries the rest of
    /// the dimming (CLAUDE.md §3.5). The overlay is always black: a
    /// red-tinted "Fallback mode" variant existed from C3 until
    /// 2026-09-10, when the owner removed the mode as too confusing.
    var overlayAlpha: Double
    /// Intent, not a guarantee: the real pin/verify/retry state machine is
    /// `PWMSafeCoordinator`. `nil` = leave hardware brightness alone.
    var hardwareBrightness: Double?
}
