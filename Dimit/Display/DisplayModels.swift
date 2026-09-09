import CoreGraphics

/// Static facts about one connected display. Real enumeration
/// (`CGGetActiveDisplayList` etc.) arrives in C2's `DisplayManager`; for now
/// this is a plain, mockable struct so `Renderer` can be tested without
/// touching hardware.
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
/// this alone" so `Applier` (C2) can diff against the last-applied command
/// and only touch what changed. `overlayTint` arrives in C3 with Fallback
/// mode; until then every overlay is a plain black dim.
struct DisplayCommand: Equatable {
    var displayID: CGDirectDisplayID
    /// `nil` means "restore to the original table" (OFF).
    var gamma: GammaSpec?
    /// 0 = no overlay window needed. Only nonzero below `Config.gammaDimFloor`.
    var overlayAlpha: Double
    /// Intent, not a guarantee: the real pin/verify/retry state machine is
    /// `PWMSafeCoordinator` in C3. `nil` = leave hardware brightness alone.
    var hardwareBrightness: Double?
}
