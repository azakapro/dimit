import XCTest
@testable import Dimit

@MainActor
final class PWMCallbackTests: XCTestCase {
    private final class Backend: BrightnessBackend {
        let name = "Callback probe"
        var readable = true
        var failSets = false
        var value: Float = 0.4
        var gets: [UInt32] = []
        var sets: [UInt32] = []
        func canControl(_ display: DisplayInfo) -> Bool { true }
        func get(_ display: DisplayInfo) -> Float? {
            gets.append(display.id)
            return readable ? value : nil
        }
        func set(_ display: DisplayInfo, _ value: Float) -> BrightnessResult {
            sets.append(display.id)
            if failSets { return .failed(-1) }
            self.value = value
            return .ok
        }
    }
    private func display(_ id: UInt32 = 1) -> DisplayInfo { DisplayInfo(id: id, uuid: "a", name: "A") }
    private func waitForCallbacks(_ seconds: Double = 0.16) {
        let e = expectation(description: "callbacks")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { e.fulfill() }
        wait(for: [e], timeout: 1)
    }
    func test_reenable_doesNotAcceptOldFailedSetRetry() {
        let b = Backend(); b.failSets = true
        let c = PWMSafeCoordinator(backends: [b], pinVerifyDelay: 0.03, pollInterval: 10, minWriteInterval: 0)
        c.sync(pwmSafeRequested: true, displays: [display()])
        c.restoreAndDisable()
        c.sync(pwmSafeRequested: true, displays: [display()])
        waitForCallbacks()
        // One old (failed) pin, then three attempts in the new session. Old
        // retries must do no work.
        //
        // This asserted 5 when the review wrote it, counting a restore write
        // between the two sessions. That write is now correctly skipped: the
        // pin it would have been undoing *failed*, so the hardware was never
        // driven and there is nothing to put back. Spending a write (and a
        // §3.4 rate-limit slot) to set a value the panel already holds was
        // itself part of why rapid toggling breached the rule.
        XCTAssertEqual(b.sets.count, 4)
        XCTAssertEqual(c.states["a"], .wontHold)
    }
    func test_disconnectedDisplay_doesNotReceivePendingRetry() {
        let b = Backend(); b.failSets = true
        let c = PWMSafeCoordinator(backends: [b], pinVerifyDelay: 0.03, pollInterval: 10, minWriteInterval: 0)
        c.sync(pwmSafeRequested: true, displays: [display()])
        c.sync(pwmSafeRequested: true, displays: [])
        waitForCallbacks()
        XCTAssertEqual(b.sets.count, 1)
        XCTAssertTrue(c.states.isEmpty)
    }
    func test_changedDisplayID_invalidatesOldVerification() {
        let b = Backend()
        let c = PWMSafeCoordinator(backends: [b], pinVerifyDelay: 0.03, pollInterval: 10, minWriteInterval: 0)
        c.sync(pwmSafeRequested: true, displays: [display()])
        b.gets = []
        c.sync(pwmSafeRequested: true, displays: [display(2)])
        waitForCallbacks()
        XCTAssertFalse(b.gets.contains(1), "verification must not call the stale CGDirectDisplayID")
        XCTAssertEqual(c.states["a"], .pinned)
        c.restoreAndDisable()
        XCTAssertEqual(b.value, 0.4)
    }
    func test_unreadableInitialValue_routineSyncDoesNotRestartRetries() {
        let b = Backend(); b.readable = false
        let c = PWMSafeCoordinator(backends: [b], pinVerifyDelay: 0.03, pollInterval: 10, minWriteInterval: 0)
        for _ in 0..<12 { c.sync(pwmSafeRequested: true, displays: [display()]) }
        waitForCallbacks()
        XCTAssertEqual(b.gets.count, 3, "one chain of three reads despite slider fan-out")
        XCTAssertEqual(c.states["a"], .wontHold)
        XCTAssertTrue(b.sets.isEmpty)
    }
}
