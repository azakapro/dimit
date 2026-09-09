import Foundation

/// CLAUDE.md §3.7. Values are user-editable and resettable starting C4;
/// for C1/C2/C3 they were the fixed defaults below. `warmthK`/`brightness`
/// stay as the *default* values (used by `PresetValues.defaults` and as the
/// reset target) — `AppState.values(for:)` is what callers should actually
/// read, since it applies any user override on top of these.
enum PresetID: String, Codable, CaseIterable {
    case day, evening, night

    var warmthK: Double {
        switch self {
        case .day: return 4000
        case .evening: return 2700
        case .night: return 0
        }
    }

    var brightness: Double {
        switch self {
        case .day: return 1.00
        case .evening: return 0.80
        case .night: return 0.40
        }
    }

    var defaultValues: PresetValues {
        PresetValues(warmthK: warmthK, brightness: brightness)
    }

    var titleKey: LocalizedStringResource {
        switch self {
        case .day: return "preset.day"
        case .evening: return "preset.evening"
        case .night: return "preset.night"
        }
    }
}

/// One editable preset's warmth/brightness pair — CLAUDE.md §3.7:
/// "User-editable; 'reset to defaults'." Kept as its own `Codable` type
/// (rather than a bare tuple) so `PersistedState.presetOverrides` can store
/// it directly and so `AppState`'s clamping logic has one shared place to
/// live (`clamped(to:)`, matching `WarmthCurve`/`Renderer`'s own pattern).
struct PresetValues: Codable, Equatable {
    var warmthK: Double
    var brightness: Double

    init(warmthK: Double, brightness: Double) {
        self.warmthK = warmthK.clamped(to: Config.minWarmthK...Config.maxWarmthK)
        self.brightness = brightness.clamped(to: Config.minBrightness...Config.maxBrightness)
    }
}
