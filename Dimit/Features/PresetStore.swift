import Foundation

/// CLAUDE.md §3.7. Values are user-editable and resettable starting C4;
/// for C1 they are the fixed defaults.
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

    var titleKey: LocalizedStringResource {
        switch self {
        case .day: return "preset.day"
        case .evening: return "preset.evening"
        case .night: return "preset.night"
        }
    }
}
