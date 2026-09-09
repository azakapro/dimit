import Foundation

/// Everything `AppState` persists, as one Codable snapshot — ARCHITECTURE.md
/// §2.8. Adding a new field with a default later is not a breaking change
/// to already-saved JSON, so fields arrive incrementally with the cycle
/// that needs them rather than all being stubbed out now.
struct PersistedState: Codable, Equatable {
    var isOn: Bool
    var warmthK: Double
    var brightness: Double
    var pwmSafe: Bool
    var activePreset: String? // PresetID.rawValue

    static let defaults = PersistedState(
        isOn: false,
        warmthK: Config.maxWarmthK,
        brightness: Config.maxBrightness,
        pwmSafe: false,
        activePreset: nil
    )
}

/// Thin wrapper over `UserDefaults`. Tested at runtime and fixed from CLAUDE.md
/// §3.7's literal instruction ("suite PRODUCT_BUNDLE_ID"): passing an app's
/// *own* bundle ID to `UserDefaults(suiteName:)` is not a real app-group
/// suite, it just re-selects the app's own standard domain, and Foundation
/// logs "does not make sense and will not work" for it at launch. A real
/// shared suite is for splitting data across processes with the same App
/// Group entitlement (e.g. an app + a future helper/extension) — we have no
/// such entitlement (CLAUDE.md §1.5: no special entitlements) and no second
/// process, so `.standard` is the correct, warning-free choice. Kept as a
/// class (not a global) so tests can still pass a distinct suite name to
/// get isolation from the real one.
final class Persistence {
    static let shared = Persistence()

    private let defaults: UserDefaults
    private let key = "state.v1"

    init(suiteName: String? = nil) {
        if let suiteName, suiteName != Config.bundleID {
            self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
        } else {
            self.defaults = .standard
        }
    }

    func load() -> PersistedState {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(PersistedState.self, from: data)
        else {
            return .defaults
        }
        return decoded
    }

    func save(_ state: PersistedState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }
}
