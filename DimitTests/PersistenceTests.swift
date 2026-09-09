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
