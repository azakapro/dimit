import XCTest
@testable import Dimit

final class RendererTests: XCTestCase {
    private func display(_ id: UInt32 = 1) -> DisplayInfo {
        DisplayInfo(id: id, uuid: "uuid-\(id)", name: "Test Display \(id)")
    }

    // CLAUDE.md §8: "render() idempotent."
    func test_render_isIdempotent() {
        let state = RenderState(isOn: true, warmthK: 2700, brightness: 0.6, pwmSafe: false)
        let displays = [display(1), display(2)]
        XCTAssertEqual(
            Renderer.render(state, displays: displays),
            Renderer.render(state, displays: displays)
        )
    }

    // ARCHITECTURE.md §2.1: "one command per display."
    func test_render_producesOneCommandPerDisplay() {
        let state = RenderState(isOn: true, warmthK: 4000, brightness: 1.0, pwmSafe: false)
        let displays = [display(1), display(2), display(3)]
        let commands = Renderer.render(state, displays: displays)
        XCTAssertEqual(commands.count, 3)
        XCTAssertEqual(Set(commands.map(\.displayID)), Set([1, 2, 3]))
    }

    func test_render_withNoDisplays_producesNoCommands() {
        let state = RenderState(isOn: true, warmthK: 6500, brightness: 1.0, pwmSafe: false)
        XCTAssertEqual(Renderer.render(state, displays: []), [])
    }

    func test_off_restoresGammaAndClearsOverlayAndBrightness() {
        let state = RenderState(isOn: false, warmthK: 0, brightness: 0.1, pwmSafe: true)
        let command = Renderer.render(state, displays: [display()]).first!
        XCTAssertNil(command.gamma, "OFF must mean 'restore', not 'apply neutral gamma'")
        XCTAssertEqual(command.overlayAlpha, 0)
        XCTAssertNil(command.hardwareBrightness)
    }

    func test_on_aboveDimFloor_usesGammaOnly_noOverlay() {
        let state = RenderState(isOn: true, warmthK: 2700, brightness: 0.5, pwmSafe: false)
        let command = Renderer.render(state, displays: [display()]).first!
        XCTAssertEqual(command.gamma?.dim, 0.5)
        XCTAssertEqual(command.overlayAlpha, 0)
    }

    func test_on_belowDimFloor_clampsGammaAndFillsOverlay() {
        // brightness 0.10 (the UI minimum) is below Config.gammaDimFloor (0.30).
        let state = RenderState(isOn: true, warmthK: 6500, brightness: 0.10, pwmSafe: false)
        let command = Renderer.render(state, displays: [display()]).first!
        XCTAssertEqual(command.gamma?.dim, Config.gammaDimFloor)
        // overlayAlpha = 1 - (0.10 / 0.30) = 0.6667
        XCTAssertEqual(command.overlayAlpha, 1 - (0.10 / 0.30), accuracy: 0.0001)
    }

    func test_on_exactlyAtDimFloor_hasNoOverlay() {
        let state = RenderState(isOn: true, warmthK: 6500, brightness: Config.gammaDimFloor, pwmSafe: false)
        let command = Renderer.render(state, displays: [display()]).first!
        XCTAssertEqual(command.overlayAlpha, 0)
    }

    func test_pwmSafe_setsHardwareBrightnessIntentTo1_whenOn() {
        let state = RenderState(isOn: true, warmthK: 6500, brightness: 1.0, pwmSafe: true)
        let command = Renderer.render(state, displays: [display()]).first!
        XCTAssertEqual(command.hardwareBrightness, 1.0)
    }

    func test_pwmSafe_isIgnoredWhileOff() {
        let state = RenderState(isOn: false, warmthK: 6500, brightness: 1.0, pwmSafe: true)
        let command = Renderer.render(state, displays: [display()]).first!
        XCTAssertNil(command.hardwareBrightness)
    }

    func test_gammaMultiplier_matchesWarmthCurve() {
        let state = RenderState(isOn: true, warmthK: 2700, brightness: 1.0, pwmSafe: false)
        let command = Renderer.render(state, displays: [display()]).first!
        XCTAssertEqual(command.gamma?.multiplier, WarmthCurve.rgb(kelvin: 2700))
    }

    // CLAUDE.md §3.6: "While pinned: map the Brightness slider entirely to
    // gamma dim (+ overlay below 30%)." Code review on C1 pointed out this
    // combination — PWM-Safe on AND brightness below the dim floor — had no
    // test, even though it's the one case where both branches of render()
    // are active on the same display at once.
    func test_pwmSafe_and_belowDimFloor_bothApply() {
        let state = RenderState(isOn: true, warmthK: 6500, brightness: 0.15, pwmSafe: true)
        let command = Renderer.render(state, displays: [display()]).first!
        XCTAssertEqual(command.hardwareBrightness, 1.0, "PWM pin intent must not be affected by the overlay branch")
        XCTAssertEqual(command.gamma?.dim, Config.gammaDimFloor, "gamma must clamp to the floor, not fall through to raw brightness")
        XCTAssertEqual(command.overlayAlpha, 1 - (0.15 / Config.gammaDimFloor), accuracy: 0.0001)
    }

    // Code review caught that Renderer trusted state.brightness to already
    // be in range, unlike WarmthCurve which defensively clamps its input —
    // a real gap since RenderState is a plain struct any future caller
    // (persistence migration, a scripted preset import) could hand
    // out-of-range values to.
    func test_outOfRangeBrightness_isClamped() {
        let tooLow = RenderState(isOn: true, warmthK: 6500, brightness: -5, pwmSafe: false)
        let tooHigh = RenderState(isOn: true, warmthK: 6500, brightness: 5, pwmSafe: false)
        XCTAssertEqual(
            Renderer.render(tooLow, displays: [display()]),
            Renderer.render(RenderState(isOn: true, warmthK: 6500, brightness: 0, pwmSafe: false), displays: [display()])
        )
        XCTAssertEqual(
            Renderer.render(tooHigh, displays: [display()]),
            Renderer.render(RenderState(isOn: true, warmthK: 6500, brightness: 1, pwmSafe: false), displays: [display()])
        )
    }
}
