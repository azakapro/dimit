import Combine
import XCTest
@testable import Dimit

/// A fake `BrightnessBackend` — tests exercise the *real*
/// `PWMSafeCoordinator` (real `DispatchQueue.main.asyncAfter`/`Timer` calls,
/// tiny injected delays) against this double, not a separately
/// reimplemented "pure" version of the state machine.
final class FakeBrightnessBackend: BrightnessBackend {
    let name = "Fake"
    var controllable: Set<String> = []
    var values: [String: Float] = [:]
    /// Per-uuid override for what `set` returns; absent = `.ok`.
    var setResults: [String: BrightnessResult] = [:]
    /// When true, `set` is recorded but does NOT update `values` — models
    /// a backend that claims success but the hardware doesn't actually move
    /// (what CoreDisplayBackend's doc comment flags as a real, if unproven
    /// on this hardware, risk).
    var setIsANoOp = false
    private(set) var setCallCount = 0

    func canControl(_ display: DisplayInfo) -> Bool {
        controllable.contains(display.uuid)
    }

    func get(_ display: DisplayInfo) -> Float? {
        values[display.uuid]
    }

    func set(_ display: DisplayInfo, _ value: Float) -> BrightnessResult {
        setCallCount += 1
        let result = setResults[display.uuid] ?? .ok
        guard result == .ok, !setIsANoOp else { return result }
        values[display.uuid] = value
        return .ok
    }
}

@MainActor
final class PWMSafeCoordinatorTests: XCTestCase {
    private func display(_ n: UInt32 = 1, uuid: String = "uuid-1") -> DisplayInfo {
        DisplayInfo(id: n, uuid: uuid, name: "Test \(n)")
    }

    // Tiny delays so tests finish in well under a second while still
    // exercising the real async code path.
    private func makeCoordinator(_ backend: FakeBrightnessBackend) -> PWMSafeCoordinator {
        PWMSafeCoordinator(backends: [backend], pinVerifyDelay: 0.02, pollInterval: 0.06)
    }

    private func waitBriefly(_ seconds: TimeInterval = 0.1) {
        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 1.0)
    }

    func test_noBackendCanControl_isUnsupported() {
        let backend = FakeBrightnessBackend() // controllable is empty
        let coordinator = makeCoordinator(backend)
        coordinator.sync(pwmSafeRequested: true, displays: [display()])
        XCTAssertEqual(coordinator.states["uuid-1"], .unsupported)
    }

    func test_successfulPin_verifiesAndReachesPinned() {
        let backend = FakeBrightnessBackend()
        backend.controllable = ["uuid-1"]
        backend.values["uuid-1"] = 0.4
        let coordinator = makeCoordinator(backend)

        coordinator.sync(pwmSafeRequested: true, displays: [display()])
        XCTAssertEqual(coordinator.states["uuid-1"], .pinning, "should be pinning immediately after set, before the verify delay")

        waitBriefly()
        XCTAssertEqual(coordinator.states["uuid-1"], .pinned)
        XCTAssertEqual(backend.values["uuid-1"], 1.0)
    }

    func test_rememberedBrightness_isCaptured_beforePinning() {
        let backend = FakeBrightnessBackend()
        backend.controllable = ["uuid-1"]
        backend.values["uuid-1"] = 0.37
        let coordinator = makeCoordinator(backend)

        coordinator.sync(pwmSafeRequested: true, displays: [display()])
        waitBriefly()
        XCTAssertEqual(coordinator.states["uuid-1"], .pinned)

        // Disable and confirm the ORIGINAL value (0.37), not something else, comes back.
        coordinator.sync(pwmSafeRequested: false, displays: [display()])
        XCTAssertEqual(backend.values["uuid-1"], 0.37)
    }

    // CLAUDE.md §3.6: "retry twice then wontHold" — 3 total attempts.
    func test_setAlwaysNoOp_retriesTwiceThenWontHold() {
        let backend = FakeBrightnessBackend()
        backend.controllable = ["uuid-1"]
        backend.values["uuid-1"] = 0.5
        backend.setIsANoOp = true // set() "succeeds" but the value never moves
        let coordinator = makeCoordinator(backend)

        coordinator.sync(pwmSafeRequested: true, displays: [display()])
        waitBriefly(0.3) // long enough for all 3 attempts' verify delays

        XCTAssertEqual(coordinator.states["uuid-1"], .wontHold)
        XCTAssertEqual(backend.setCallCount, 3, "expected exactly 3 attempts: initial + 2 retries")
    }

    func test_setFails_alsoRetriesThenWontHold() {
        let backend = FakeBrightnessBackend()
        backend.controllable = ["uuid-1"]
        backend.values["uuid-1"] = 0.5
        backend.setResults["uuid-1"] = .failed(-1)
        let coordinator = makeCoordinator(backend)

        coordinator.sync(pwmSafeRequested: true, displays: [display()])
        waitBriefly(0.2)

        XCTAssertEqual(coordinator.states["uuid-1"], .wontHold)
    }

    func test_disable_restoresRememberedBrightness_andClearsState() {
        let backend = FakeBrightnessBackend()
        backend.controllable = ["uuid-1"]
        backend.values["uuid-1"] = 0.6
        let coordinator = makeCoordinator(backend)

        coordinator.sync(pwmSafeRequested: true, displays: [display()])
        waitBriefly()
        XCTAssertEqual(coordinator.states["uuid-1"], .pinned)

        coordinator.sync(pwmSafeRequested: false, displays: [display()])
        XCTAssertEqual(backend.values["uuid-1"], 0.6)
        XCTAssertNil(coordinator.states["uuid-1"], "state should be cleared, UI treats a missing entry as .off")
    }

    // CLAUDE.md §3.6: "poll every 5s while pinned... re-pin... show the
    // toast once per session."
    func test_driftWhilePinned_triggersRepinAndToastOnce() {
        let backend = FakeBrightnessBackend()
        backend.controllable = ["uuid-1"]
        backend.values["uuid-1"] = 0.5
        let coordinator = makeCoordinator(backend)

        var toastCount = 0
        var cancellables = Set<AnyCancellable>()
        coordinator.repinnedToastSubject.sink { toastCount += 1 }.store(in: &cancellables)

        coordinator.sync(pwmSafeRequested: true, displays: [display()])
        waitBriefly() // now pinned, polling started

        // Simulate a hardware brightness key press: value drops below the display's back.
        backend.values["uuid-1"] = 0.2
        waitBriefly(0.15) // one poll tick (pollInterval = 0.06s) plus a re-pin verify delay

        XCTAssertEqual(coordinator.states["uuid-1"], .pinned, "should have detected the drift and re-pinned")
        XCTAssertEqual(backend.values["uuid-1"], 1.0)
        XCTAssertEqual(toastCount, 1)

        // Drift again — toast must NOT fire a second time this session.
        backend.values["uuid-1"] = 0.3
        waitBriefly(0.15)
        XCTAssertEqual(toastCount, 1, "toast is once per session, not once per drift")
    }

    func test_newlyConnectedDisplay_whilePWMSafeAlreadyRequested_getsPinned() {
        let backend = FakeBrightnessBackend()
        backend.controllable = ["uuid-1", "uuid-2"]
        backend.values = ["uuid-1": 0.5, "uuid-2": 0.5]
        let coordinator = makeCoordinator(backend)

        coordinator.sync(pwmSafeRequested: true, displays: [display(1, uuid: "uuid-1")])
        waitBriefly()
        XCTAssertEqual(coordinator.states["uuid-1"], .pinned)
        XCTAssertNil(coordinator.states["uuid-2"])

        // A second display connects.
        coordinator.sync(pwmSafeRequested: true, displays: [display(1, uuid: "uuid-1"), display(2, uuid: "uuid-2")])
        waitBriefly()
        XCTAssertEqual(coordinator.states["uuid-2"], .pinned)
    }

    func test_alreadyPinnedDisplay_isNotReAttempted_onRoutineSync() {
        let backend = FakeBrightnessBackend()
        backend.controllable = ["uuid-1"]
        backend.values["uuid-1"] = 0.5
        let coordinator = makeCoordinator(backend)

        coordinator.sync(pwmSafeRequested: true, displays: [display()])
        waitBriefly()
        let callsAfterFirstPin = backend.setCallCount
        XCTAssertEqual(coordinator.states["uuid-1"], .pinned)

        // Routine syncs (e.g. from an unrelated slider drag) should not
        // re-trigger a pin attempt on an already-pinned display.
        coordinator.sync(pwmSafeRequested: true, displays: [display()])
        coordinator.sync(pwmSafeRequested: true, displays: [display()])
        XCTAssertEqual(backend.setCallCount, callsAfterFirstPin, "no extra set() calls for an unchanged, already-pinned display")
    }

    // Code review caught this: `backend.get()` returning nil meant the
    // remembered-brightness dictionary entry was silently never written
    // (assigning nil to a dictionary subscript removes the key), so
    // restoreAndDisable() would skip the display and leave the backlight
    // pinned at 100% forever. Pinning without knowing how to undo it is
    // worse than not pinning, so it must not reach .pinned at all.
    func test_unreadableInitialBrightness_doesNotPin() {
        let backend = FakeBrightnessBackend()
        backend.controllable = ["uuid-1"]
        // No entry in `values` → get() returns nil.
        let coordinator = makeCoordinator(backend)

        coordinator.sync(pwmSafeRequested: true, displays: [display()])
        waitBriefly(0.3)

        XCTAssertEqual(coordinator.states["uuid-1"], .wontHold)
        XCTAssertNotEqual(coordinator.states["uuid-1"], .pinned)
    }

    // CLAUDE.md §3.4: "Never call set-brightness more than 4x/second."
    // Code review caught the synchronous-set-failure path recursing
    // straight back into another set() with no delay at all, firing all
    // three attempts inside one run-loop turn.
    func test_setFailureRetries_areSpacedOut_notFiredInOneRunLoopTurn() {
        let backend = FakeBrightnessBackend()
        backend.controllable = ["uuid-1"]
        backend.values["uuid-1"] = 0.5
        backend.setResults["uuid-1"] = .failed(-1)
        let coordinator = makeCoordinator(backend) // pinVerifyDelay 0.02s

        coordinator.sync(pwmSafeRequested: true, displays: [display()])
        // Synchronously after sync() returns, only the FIRST attempt should
        // have happened — the retries must be scheduled, not immediate.
        XCTAssertEqual(backend.setCallCount, 1, "retries must be delayed, not fired synchronously in one turn")

        waitBriefly(0.2)
        XCTAssertEqual(coordinator.states["uuid-1"], .wontHold)
    }

    // Quitting has to restore the backlight too — it's real hardware state
    // that outlives the process (code review).
    func test_restoreAndDisable_restoresBrightness_forQuitPath() {
        let backend = FakeBrightnessBackend()
        backend.controllable = ["uuid-1"]
        backend.values["uuid-1"] = 0.42
        let coordinator = makeCoordinator(backend)

        coordinator.sync(pwmSafeRequested: true, displays: [display()])
        waitBriefly()
        XCTAssertEqual(coordinator.states["uuid-1"], .pinned)
        XCTAssertEqual(backend.values["uuid-1"], 1.0)

        coordinator.restoreAndDisable()
        XCTAssertEqual(backend.values["uuid-1"], 0.42)
        XCTAssertNil(coordinator.states["uuid-1"])
    }

    // A rapid off→on toggle inside the verify window used to leave the
    // first chain's stale callback able to act on the second chain's
    // state. Generation tracking drops it.
    func test_rapidDisableThenReEnable_doesNotLeaveOverlappingChains() {
        let backend = FakeBrightnessBackend()
        backend.controllable = ["uuid-1"]
        backend.values["uuid-1"] = 0.5
        let coordinator = makeCoordinator(backend)

        coordinator.sync(pwmSafeRequested: true, displays: [display()])
        coordinator.sync(pwmSafeRequested: false, displays: [display()]) // inside the verify window
        coordinator.sync(pwmSafeRequested: true, displays: [display()])
        waitBriefly(0.2)

        // Should settle cleanly on pinned, with the remembered value still
        // the true original (not 1.0 captured from a half-pinned state).
        XCTAssertEqual(coordinator.states["uuid-1"], .pinned)
        coordinator.restoreAndDisable()
        XCTAssertEqual(backend.values["uuid-1"], 0.5, "must restore the true original, not a value captured mid-pin")
    }

    func test_disconnectedDisplay_dropsItsState() {
        let backend = FakeBrightnessBackend()
        backend.controllable = ["uuid-1"]
        backend.values["uuid-1"] = 0.5
        let coordinator = makeCoordinator(backend)

        coordinator.sync(pwmSafeRequested: true, displays: [display()])
        waitBriefly()
        XCTAssertEqual(coordinator.states["uuid-1"], .pinned)

        coordinator.sync(pwmSafeRequested: true, displays: []) // display unplugged
        XCTAssertNil(coordinator.states["uuid-1"])
    }
}
