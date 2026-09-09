import XCTest
@testable import Dimit

final class PersistenceTests: XCTestCase {
    // The whole point of PersistedState's custom decoder (added for C3):
    // a beta tester upgrading from a C1/C2 build has JSON on disk with no
    // "fallbackMode" key at all. Verified empirically before writing the
    // fix that Swift's synthesized Decodable throws keyNotFound for a
    // missing key regardless of the property's declared default — which
    // would have hit Persistence.load()'s catch-all and silently reset
    // *every* field, not just the new one, to defaults. This test decodes
    // exactly that old shape directly (bypassing Persistence entirely) to
    // pin the guarantee at the type level.
    func test_decodingJSONFromBeforeFallbackModeExisted_preservesEveryOtherField() throws {
        let oldShapeJSON = """
        {"isOn":true,"warmthK":2700,"brightness":0.8,"pwmSafe":true,"activePreset":"evening"}
        """
        let decoded = try JSONDecoder().decode(PersistedState.self, from: Data(oldShapeJSON.utf8))

        XCTAssertTrue(decoded.isOn)
        XCTAssertEqual(decoded.warmthK, 2700)
        XCTAssertEqual(decoded.brightness, 0.8)
        XCTAssertTrue(decoded.pwmSafe)
        XCTAssertEqual(decoded.activePreset, "evening")
        XCTAssertFalse(decoded.fallbackMode, "missing key should default, not throw")
    }

    // Same guarantee, pinned again for the three fields C4 adds
    // (presetOverrides, locale, updateChecksEnabled): a tester upgrading
    // from the C3 build (which has fallbackMode but none of these) must
    // not lose isOn/warmthK/brightness/pwmSafe/fallbackMode/activePreset.
    func test_decodingJSONFromBeforeC4Fields_preservesEveryOtherField() throws {
        let c3ShapeJSON = """
        {"isOn":true,"warmthK":0,"brightness":0.4,"pwmSafe":true,"fallbackMode":false,"activePreset":"night"}
        """
        let decoded = try JSONDecoder().decode(PersistedState.self, from: Data(c3ShapeJSON.utf8))

        XCTAssertTrue(decoded.isOn)
        XCTAssertEqual(decoded.warmthK, 0)
        XCTAssertEqual(decoded.brightness, 0.4)
        XCTAssertTrue(decoded.pwmSafe)
        XCTAssertFalse(decoded.fallbackMode)
        XCTAssertEqual(decoded.activePreset, "night")
        XCTAssertTrue(decoded.presetOverrides.isEmpty, "missing key should default, not throw")
        XCTAssertNil(decoded.locale, "missing key should default to following the system language")
        XCTAssertFalse(decoded.updateChecksEnabled, "missing key should default to opted out, never silently opted in")
    }

    func test_presetOverrides_roundTripsThroughJSON() throws {
        let original = PersistedState(
            isOn: false,
            warmthK: Config.maxWarmthK,
            brightness: Config.maxBrightness,
            pwmSafe: false,
            fallbackMode: false,
            activePreset: nil,
            presetOverrides: ["night": PresetValues(warmthK: 500, brightness: 0.25)],
            locale: "ru",
            updateChecksEnabled: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PersistedState.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_decodingCompletelyEmptyJSON_fallsBackToDefaultsForEveryField() throws {
        let decoded = try JSONDecoder().decode(PersistedState.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, PersistedState.defaults)
    }

    func test_normalRoundTrip_stillWorks() throws {
        let original = PersistedState(isOn: true, warmthK: 1900, brightness: 0.6, pwmSafe: true, fallbackMode: true, activePreset: "night")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PersistedState.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_persistence_loadOfMissingKey_returnsDefaults() {
        let suite = "test.\(UUID().uuidString)"
        let persistence = Persistence(suiteName: suite)
        XCTAssertEqual(persistence.load(), .defaults)
    }
}
