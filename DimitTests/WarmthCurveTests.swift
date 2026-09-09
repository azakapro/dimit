import XCTest
@testable import Dimit

final class WarmthCurveTests: XCTestCase {
    // CLAUDE.md §3.2 and §8: "0K yields (1,0,0)" exactly.
    func test_zeroKelvin_isPureRed() {
        let rgb = WarmthCurve.rgb(kelvin: 0)
        XCTAssertEqual(rgb.r, 1.0)
        XCTAssertEqual(rgb.g, 0.0)
        XCTAssertEqual(rgb.b, 0.0)
    }

    func test_6500Kelvin_isNeutralWhite() {
        let rgb = WarmthCurve.rgb(kelvin: 6500)
        XCTAssertEqual(rgb.r, 1.0, accuracy: 0.001)
        XCTAssertEqual(rgb.g, 1.0, accuracy: 0.001)
        XCTAssertEqual(rgb.b, 1.0, accuracy: 0.001)
    }

    // CLAUDE.md §3.2: "2700K≈(1, 0.72–0.78, 0.45–0.55)"
    func test_2700Kelvin_matchesEveningPresetRange() {
        let rgb = WarmthCurve.rgb(kelvin: 2700)
        XCTAssertEqual(rgb.r, 1.0)
        XCTAssertTrue((0.72...0.78).contains(rgb.g), "green \(rgb.g) not in 0.72...0.78")
        XCTAssertTrue((0.45...0.55).contains(rgb.b), "blue \(rgb.b) not in 0.45...0.55")
    }

    // CLAUDE.md §3.2: "1900K≈(1, 0.55–0.62, 0.20–0.30)"
    func test_1900Kelvin_matchesRange() {
        let rgb = WarmthCurve.rgb(kelvin: 1900)
        XCTAssertEqual(rgb.r, 1.0)
        XCTAssertTrue((0.55...0.62).contains(rgb.g), "green \(rgb.g) not in 0.55...0.62")
        XCTAssertTrue((0.20...0.30).contains(rgb.b), "blue \(rgb.b) not in 0.20...0.30")
    }

    func test_redIsAlwaysFullAcrossTheWholeRange() {
        for k in stride(from: 0.0, through: 6500.0, by: 250.0) {
            XCTAssertEqual(WarmthCurve.rgb(kelvin: k).r, 1.0, "red dropped below 1.0 at \(k)K")
        }
    }

    // "Gamma tables monotonic" (CLAUDE.md §8) starts here: the curve itself
    // must not reverse direction as Kelvin falls, or the slider would look
    // like it's warming back up partway through a drag.
    func test_greenAndBlue_areMonotonicallyNonIncreasing_asKelvinFalls() {
        var previousG = Double.infinity
        var previousB = Double.infinity
        for k in stride(from: 6500.0, through: 0.0, by: -50.0) {
            let rgb = WarmthCurve.rgb(kelvin: k)
            XCTAssertLessThanOrEqual(rgb.g, previousG + 1e-9, "green increased at \(k)K")
            XCTAssertLessThanOrEqual(rgb.b, previousB + 1e-9, "blue increased at \(k)K")
            previousG = rgb.g
            previousB = rgb.b
        }
    }

    func test_outOfRangeInput_isClamped() {
        XCTAssertEqual(WarmthCurve.rgb(kelvin: -500), WarmthCurve.rgb(kelvin: 0))
        XCTAssertEqual(WarmthCurve.rgb(kelvin: 9000), WarmthCurve.rgb(kelvin: 6500))
    }

    func test_1000Kelvin_isContinuousAcrossTheLinearBoundary() {
        // The curve is piecewise: linear below 1000K, anchor-interpolated
        // above. The two pieces must agree exactly at the seam.
        let atBoundary = WarmthCurve.rgb(kelvin: 1000)
        let justAbove = WarmthCurve.rgb(kelvin: 1000.001)
        XCTAssertEqual(atBoundary.g, justAbove.g, accuracy: 0.001)
        XCTAssertEqual(atBoundary.b, justAbove.b, accuracy: 0.001)
    }
}
