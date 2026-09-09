import XCTest
@testable import Dimit

final class ApplierTests: XCTestCase {
    private let gammaA = GammaSpec(multiplier: .init(r: 1, g: 1, b: 1), dim: 1.0)
    private let gammaB = GammaSpec(multiplier: .init(r: 1, g: 0.5, b: 0.5), dim: 0.8)

    private func command(_ id: UInt32, gamma: GammaSpec?, overlayAlpha: Double = 0) -> DisplayCommand {
        DisplayCommand(displayID: id, gamma: gamma, overlayAlpha: overlayAlpha, hardwareBrightness: nil)
    }

    func test_noPrevious_gammaOn_isApplied() {
        let diff = Applier.diff(previous: [], current: [command(1, gamma: gammaA)])
        XCTAssertEqual(diff.toApply.map(\.displayID), [1])
        XCTAssertTrue(diff.toRestore.isEmpty)
    }

    func test_noPrevious_gammaOff_isIgnored() {
        let diff = Applier.diff(previous: [], current: [command(1, gamma: nil)])
        XCTAssertTrue(diff.toApply.isEmpty)
        XCTAssertTrue(diff.toRestore.isEmpty)
    }

    func test_unchangedGamma_producesNoWork() {
        let previous = [command(1, gamma: gammaA)]
        let current = [command(1, gamma: gammaA)]
        XCTAssertEqual(Applier.diff(previous: previous, current: current), Applier.Diff())
    }

    // The case the whole diff exists for: overlayAlpha moves every tick
    // while dragging below the dim floor, but gamma is pinned at the
    // floor and doesn't actually change — must not re-touch the display.
    func test_onlyOverlayAlphaChanges_gammaSame_producesNoWork() {
        let previous = [command(1, gamma: gammaB, overlayAlpha: 0.2)]
        let current = [command(1, gamma: gammaB, overlayAlpha: 0.6)]
        XCTAssertEqual(Applier.diff(previous: previous, current: current), Applier.Diff())
    }

    func test_gammaValueChanges_isApplied() {
        let previous = [command(1, gamma: gammaA)]
        let current = [command(1, gamma: gammaB)]
        let diff = Applier.diff(previous: previous, current: current)
        XCTAssertEqual(diff.toApply.map(\.displayID), [1])
        XCTAssertTrue(diff.toRestore.isEmpty)
    }

    func test_turningOff_isRestored() {
        let previous = [command(1, gamma: gammaA)]
        let current = [command(1, gamma: nil)]
        let diff = Applier.diff(previous: previous, current: current)
        XCTAssertTrue(diff.toApply.isEmpty)
        XCTAssertEqual(diff.toRestore, [1])
    }

    func test_multipleDisplays_mixedTransitions() {
        let previous = [command(1, gamma: gammaA), command(2, gamma: nil), command(3, gamma: gammaA)]
        let current = [command(1, gamma: gammaA), command(2, gamma: gammaA), command(3, gamma: nil)]
        let diff = Applier.diff(previous: previous, current: current)
        XCTAssertEqual(diff.toApply.map(\.displayID), [2])
        XCTAssertEqual(diff.toRestore, [3])
    }

    // A display that vanished from `current` entirely (unplugged) simply
    // isn't iterated — DisplayManager drops it from the list it hands to
    // Renderer, so there's nothing for Applier to report either way; the
    // baseline eviction for a gone display is DisplayCoordinator's job via
    // GammaController.evictBaselines(keepingOnly:), not this pure diff.
    func test_displayGoneFromCurrentList_producesNoEntryForIt() {
        let previous = [command(1, gamma: gammaA), command(2, gamma: gammaA)]
        let current = [command(1, gamma: gammaA)]
        let diff = Applier.diff(previous: previous, current: current)
        XCTAssertTrue(diff.toApply.isEmpty)
        XCTAssertTrue(diff.toRestore.isEmpty)
    }

    func test_diff_isIdempotent_whenCalledTwiceWithSameInputs() {
        let previous = [command(1, gamma: gammaA)]
        let current = [command(1, gamma: gammaB)]
        XCTAssertEqual(Applier.diff(previous: previous, current: current), Applier.diff(previous: previous, current: current))
    }
}
