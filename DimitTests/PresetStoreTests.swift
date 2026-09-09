import XCTest
@testable import Dimit

final class PresetStoreTests: XCTestCase {
    func test_defaultValues_matchThePresetsOwnProperties() {
        for preset in PresetID.allCases {
            let values = preset.defaultValues
            XCTAssertEqual(values.warmthK, preset.warmthK)
            XCTAssertEqual(values.brightness, preset.brightness)
        }
    }

    // Settings' preset editor lets the user drag sliders; PresetValues'
    // own init clamps so a bad caller (or a future stepper button that
    // overshoots) can never persist an out-of-range preset — same
    // defense-in-depth as `WarmthCurve`/`Renderer` per Comparable+Clamped's
    // own doc comment ("drifts when each site hand-rolls its own min/max").
    func test_init_clampsWarmthToConfigRange() {
        XCTAssertEqual(PresetValues(warmthK: -500, brightness: 0.5).warmthK, Config.minWarmthK)
        XCTAssertEqual(PresetValues(warmthK: 99999, brightness: 0.5).warmthK, Config.maxWarmthK)
    }

    func test_init_clampsBrightnessToConfigRange() {
        XCTAssertEqual(PresetValues(warmthK: 2700, brightness: -1).brightness, Config.minBrightness)
        XCTAssertEqual(PresetValues(warmthK: 2700, brightness: 5).brightness, Config.maxBrightness)
    }
}
