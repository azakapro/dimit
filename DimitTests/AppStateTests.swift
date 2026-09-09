import XCTest
@testable import Dimit

@MainActor
final class AppStateTests: XCTestCase {
    private func freshState() -> AppState {
        // A random suite name per test = a clean UserDefaults every time,
        // so tests never see another test's leftover persisted state and
        // never touch the real app.dimit.mac suite.
        AppState(persistence: Persistence(suiteName: "test.\(UUID().uuidString)"))
    }

    func test_defaults_matchPersistedStateDefaults() {
        let state = freshState()
        XCTAssertEqual(state.isOn, PersistedState.defaults.isOn)
        XCTAssertEqual(state.warmthK, PersistedState.defaults.warmthK)
        XCTAssertEqual(state.brightness, PersistedState.defaults.brightness)
        XCTAssertEqual(state.pwmSafe, PersistedState.defaults.pwmSafe)
        XCTAssertNil(state.activePreset)
    }

    func test_applyPreset_setsWarmthBrightnessAndMarker() {
        let state = freshState()
        state.apply(preset: .evening)
        XCTAssertEqual(state.warmthK, PresetID.evening.warmthK)
        XCTAssertEqual(state.brightness, PresetID.evening.brightness)
        XCTAssertEqual(state.activePreset, .evening)
    }

    func test_movingWarmthSlider_afterAPreset_clearsThePresetMarker() {
        let state = freshState()
        state.apply(preset: .night)
        XCTAssertEqual(state.activePreset, .night)
        state.warmthK = 3000 // user drags away from NIGHT's 0K
        XCTAssertNil(state.activePreset, "preset marker should clear once the value no longer matches it")
    }

    func test_movingBrightnessSlider_afterAPreset_clearsThePresetMarker() {
        let state = freshState()
        state.apply(preset: .day)
        state.brightness = 0.5
        XCTAssertNil(state.activePreset)
    }

    func test_renderState_reflectsCurrentFields() {
        let state = freshState()
        state.isOn = true
        state.warmthK = 1900
        state.brightness = 0.7
        state.pwmSafe = true
        let render = state.renderState
        XCTAssertEqual(render, RenderState(isOn: true, warmthK: 1900, brightness: 0.7, pwmSafe: true))
    }

    func test_persistence_roundTrips() {
        let suite = "test.\(UUID().uuidString)"
        let persistence = Persistence(suiteName: suite)
        let state = AppState(persistence: persistence)
        state.apply(preset: .evening)
        state.pwmSafe = true

        // Persistence is debounced 250ms; save directly to test round-trip
        // shape without sleeping the test suite.
        persistence.save(
            PersistedState(
                isOn: state.isOn,
                warmthK: state.warmthK,
                brightness: state.brightness,
                pwmSafe: state.pwmSafe,
                activePreset: state.activePreset?.rawValue
            )
        )

        let reloaded = AppState(persistence: Persistence(suiteName: suite))
        XCTAssertEqual(reloaded.warmthK, PresetID.evening.warmthK)
        XCTAssertEqual(reloaded.brightness, PresetID.evening.brightness)
        XCTAssertEqual(reloaded.activePreset, .evening)
        XCTAssertTrue(reloaded.pwmSafe)
    }
}
