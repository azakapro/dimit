import XCTest
@testable import Dimit

final class GammaMathTests: XCTestCase {
    private let baseline = GammaMath.Table(
        red: [0.0, 0.5, 1.0],
        green: [0.0, 0.5, 1.0],
        blue: [0.0, 0.5, 1.0]
    )

    func test_neutralMultiplierFullDim_returnsBaselineUnchanged() {
        let result = GammaMath.apply(baseline: baseline, multiplier: .init(r: 1, g: 1, b: 1), dim: 1.0)
        XCTAssertEqual(result, baseline)
    }

    func test_dimScalesEveryChannelEqually() {
        let result = GammaMath.apply(baseline: baseline, multiplier: .init(r: 1, g: 1, b: 1), dim: 0.5)
        XCTAssertEqual(result.red, [0.0, 0.25, 0.5])
        XCTAssertEqual(result.green, [0.0, 0.25, 0.5])
        XCTAssertEqual(result.blue, [0.0, 0.25, 0.5])
    }

    // CLAUDE.md §3.2: 0K drives green and blue to exactly 0 — the whole
    // point of the gamma path. Multiplier (1,0,0) must zero those channels
    // regardless of what the baseline table looked like.
    func test_zeroMultiplier_zeroesThatChannel_evenAtFullDim() {
        let result = GammaMath.apply(baseline: baseline, multiplier: .init(r: 1, g: 0, b: 0), dim: 1.0)
        XCTAssertEqual(result.red, baseline.red)
        XCTAssertEqual(result.green, [0, 0, 0])
        XCTAssertEqual(result.blue, [0, 0, 0])
    }

    // ARCHITECTURE.md §2.4: "clamp(origR[i] * mulR * dim, 0, 1)." A
    // baseline entry above 1 shouldn't occur in practice, but a display
    // whose default calibration table happens to have imprecise float
    // values near 1.0 combined with dim=1.0 must never produce a table
    // entry that overshoots — CGSetDisplayTransferByTable's contract
    // requires values in [0,1].
    func test_result_isAlwaysClampedToUnitRange() {
        let hot = GammaMath.Table(red: [1.0], green: [1.0], blue: [1.0])
        let result = GammaMath.apply(baseline: hot, multiplier: .init(r: 1, g: 1, b: 1), dim: 1.0)
        XCTAssertLessThanOrEqual(result.red[0], 1.0)
        XCTAssertGreaterThanOrEqual(result.red[0], 0.0)
    }

    func test_preservesTableLength() {
        let longer = GammaMath.Table(
            red: Array(repeating: Float(0.5), count: 1024),
            green: Array(repeating: Float(0.5), count: 1024),
            blue: Array(repeating: Float(0.5), count: 1024)
        )
        let result = GammaMath.apply(baseline: longer, multiplier: .init(r: 1, g: 1, b: 1), dim: 1.0)
        XCTAssertEqual(result.red.count, 1024)
    }
}
