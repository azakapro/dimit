import XCTest
@testable import Dimit

/// The whole point of `UpdateController` is one invariant: Sparkle checks
/// automatically **only** while the user's persisted opt-in is on. These
/// tests pin that against a fake updater; Sparkle itself is not exercised.
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

    private func drain() {
        // The subscription hops to the main queue; let it deliver.
        let exp = expectation(description: "main queue drained")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1)
    }

    func test_freshInstall_automaticChecksAreOff() {
        let state = makeState()
        XCTAssertFalse(state.updateChecksEnabled, "CLAUDE.md §1.2: opt-in, default off")
        let updater = FakeUpdater()
        let controller = UpdateController(appState: state, updater: updater)
        drain()
        XCTAssertFalse(updater.automaticallyChecksForUpdates, "the controller must impose the user's choice on the updater, even over Sparkle's own default")
        _ = controller
    }

    func test_optIn_turnsAutomaticChecksOn_andOptOutTurnsThemOffAgain() {
        let state = makeState()
        let updater = FakeUpdater()
        let controller = UpdateController(appState: state, updater: updater)
        drain()

        state.updateChecksEnabled = true
        drain()
        XCTAssertTrue(updater.automaticallyChecksForUpdates)

        state.updateChecksEnabled = false
        drain()
        XCTAssertFalse(updater.automaticallyChecksForUpdates)
        _ = controller
    }

    func test_manualCheck_isForwarded_regardlessOfOptIn() {
        let state = makeState()
        let updater = FakeUpdater()
        let controller = UpdateController(appState: state, updater: updater)
        drain()
        XCTAssertFalse(state.updateChecksEnabled)

        controller.checkForUpdates()
        XCTAssertEqual(updater.manualChecks, 1, "a user-initiated check is not what the opt-in protects against")
        XCTAssertTrue(controller.canCheckForUpdates)
    }
}
