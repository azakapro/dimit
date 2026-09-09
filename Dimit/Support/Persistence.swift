import Foundation

/// Everything `AppState` persists, as one Codable snapshot — ARCHITECTURE.md
/// §2.8.
///
/// C1's original comment here claimed "adding a new field with a default
/// later is not a breaking change to already-saved JSON" — checked that
/// claim empirically while adding `fallbackMode` for C3 and it was
/// **wrong**: Swift's synthesized `Decodable` throws `keyNotFound` for a
/// missing key regardless of the property's declared default, so loading
/// a C1/C2 user's saved state with this struct's synthesized decoder would
/// have hit `Persistence.load()`'s catch-all and silently reset
/// *everything* — `isOn`, `warmthK`, `brightness`, all of it, not just the
/// new field — to defaults on first launch after upgrading. Fixed with a
/// custom decoder using `decodeIfPresent` for every field, so the original
/// claim is now actually true: add a field with a default here, and it
/// stays true for every field added after this fix too, without another
/// custom-decoder edit.
struct PersistedState: Codable, Equatable {
    var isOn: Bool
    var warmthK: Double
    var brightness: Double
    var pwmSafe: Bool
    var fallbackMode: Bool
    var activePreset: String? // PresetID.rawValue

    static let defaults = PersistedState(
        isOn: false,
        warmthK: Config.maxWarmthK,
        brightness: Config.maxBrightness,
        pwmSafe: false,
        fallbackMode: false,
        activePreset: nil
    )

    init(isOn: Bool, warmthK: Double, brightness: Double, pwmSafe: Bool, fallbackMode: Bool, activePreset: String?) {
        self.isOn = isOn
        self.warmthK = warmthK
        self.brightness = brightness
        self.pwmSafe = pwmSafe
        self.fallbackMode = fallbackMode
        self.activePreset = activePreset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.defaults
        isOn = try container.decodeIfPresent(Bool.self, forKey: .isOn) ?? fallback.isOn
        warmthK = try container.decodeIfPresent(Double.self, forKey: .warmthK) ?? fallback.warmthK
        brightness = try container.decodeIfPresent(Double.self, forKey: .brightness) ?? fallback.brightness
        pwmSafe = try container.decodeIfPresent(Bool.self, forKey: .pwmSafe) ?? fallback.pwmSafe
        fallbackMode = try container.decodeIfPresent(Bool.self, forKey: .fallbackMode) ?? fallback.fallbackMode
        activePreset = try container.decodeIfPresent(String.self, forKey: .activePreset)
    }
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
        guard let data = defaults.data(forKey: key) else {
            return .defaults // first launch — not an error, nothing to log
        }
        do {
            return try JSONDecoder().decode(PersistedState.self, from: data)
        } catch {
            // Code review on C1 caught `try?` swallowing this with no trace:
            // a returning user's whole saved state (isOn, warmthK,
            // brightness, pwmSafe, activePreset) would silently reset to
            // defaults with nothing in the log to explain "why my settings
            // reset themselves." Never log `data` itself — no reason to
            // believe it contains anything sensitive here, but the habit
            // (CLAUDE.md §4.2: "log nothing but key-hash") is to log
            // failures, not payloads.
            Log.app.error("PersistedState decode failed, reverting to defaults: \(error, privacy: .public)")
            return .defaults
        }
    }

    func save(_ state: PersistedState) {
        do {
            let data = try JSONEncoder().encode(state)
            defaults.set(data, forKey: key)
        } catch {
            // See load()'s comment: silent failure here means every future
            // change stops persisting with zero diagnostic trail.
            Log.app.error("PersistedState encode failed, not saved: \(error, privacy: .public)")
        }
    }

    // MARK: - One-time UI flags

    /// CLAUDE.md §3.3: the auto-brightness banner shows once, ever,
    /// "dismissable forever." Kept as its own boolean rather than a field
    /// on `PersistedState` — it's a one-time UI flag, not part of the
    /// render-relevant state `RenderState`/`Renderer` care about.
    private let autoBrightnessBannerShownKey = "autoBrightnessBannerShown.v1"

    var hasShownAutoBrightnessBanner: Bool {
        get { defaults.bool(forKey: autoBrightnessBannerShownKey) }
        set { defaults.set(newValue, forKey: autoBrightnessBannerShownKey) }
    }
}
