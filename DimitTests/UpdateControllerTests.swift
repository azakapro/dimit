import XCTest
@testable import Dimit

/// The whole point of `UpdateController` is one invariant: Sparkle checks
/// automatically **only** while the user's persisted opt-in is on, and the
/// controller itself never starts a check that nobody asked for. Pinned
/// against a fake updater; Sparkle is not exercised.
@MainActor
final class UpdateControllerTests: XCTestCase {
    private final class FakeUpdater: UpdaterControlling {
        var automaticallyChecksForUpdates = true // deliberately wrong default: the controller must overwrite it
        var canCheckForUpdates = true
        var manualChecks = 0
        func checkForUpdates() { manualChecks += 1 }
    }

    private func makeState() -> AppState {
        AppState(persistence: Persistence(suiteName: "test.\(UUID().uuidString)"))
    }

    func test_freshInstall_automaticChecksAreOff_beforeInitReturns() {
        let state = makeState()
        XCTAssertFalse(state.updateChecksEnabled, "CLAUDE.md §1.2: opt-in, default off")
        let updater = FakeUpdater()
        let controller = UpdateController(appState: state, updater: updater)
        // No run-loop hop: by the time init returns Sparkle must already
        // have been told "no", before it could schedule anything.
        XCTAssertFalse(updater.automaticallyChecksForUpdates, "the controller must impose the user's choice on the updater, even over Sparkle's own default")
        XCTAssertEqual(updater.manualChecks, 0)
        _ = controller
    }

    func test_optIn_turnsAutomaticChecksOn_andOptOutTurnsThemOffAgain_withoutEverStartingACheck() {
        let state = makeState()
        let updater = FakeUpdater()
        let controller = UpdateController(appState: state, updater: updater)

        state.updateChecksEnabled = true
        XCTAssertTrue(updater.automaticallyChecksForUpdates)

        state.updateChecksEnabled = false
        XCTAssertFalse(updater.automaticallyChecksForUpdates)

        // Sparkle's docs suggest kicking off a check when the user opts in.
        // Not here: the opt-in enables *scheduled* checks; an immediate
        // unasked request is exactly what CLAUDE.md §4.3 forbids.
        XCTAssertEqual(updater.manualChecks, 0, "opting in or out must never start a check by itself")
        _ = controller
    }

    func test_manualCheck_isForwarded_regardlessOfOptIn() {
        let state = makeState()
        let updater = FakeUpdater()
        let controller = UpdateController(appState: state, updater: updater)
        XCTAssertFalse(state.updateChecksEnabled)

        controller.checkForUpdates()
        XCTAssertEqual(updater.manualChecks, 1, "a user-initiated check is not what the opt-in protects against")
        XCTAssertTrue(controller.canCheckForUpdates)
        updater.canCheckForUpdates = false
        XCTAssertFalse(controller.canCheckForUpdates, "menu validation must follow Sparkle's own state")
    }
}
