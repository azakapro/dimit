import XCTest
@testable import Dimit

/// CLAUDE.md §3.4: "Never call set-brightness more than 4×/second (some
/// panels wear or lag)." These use the **production** `minWriteInterval`
/// deliberately — the other PWM suites pass 0 so they can exercise the
/// state machine in milliseconds, which is exactly why the rule needs a
/// suite of its own that doesn't opt out.
@MainActor
final class PWMRateLimitTests: XCTestCase {
    private final class TimestampingBackend: BrightnessBackend {
        let name = "Timestamping probe"
        var value: Float = 0.4
        var writes: [(value: Float, at: Date)] = []
        func canControl(_ display: DisplayInfo) -> Bool { true }
        func get(_ display: DisplayInfo) -> Float? { value }
        func set(_ display: DisplayInfo, _ value: Float) -> BrightnessResult {
            writes.append((value, Date()))
            self.value = value
            return .ok
        }
    }

    private func display(_ id: UInt32 = 1) -> DisplayInfo { DisplayInfo(id: id, uuid: "a", name: "A") }

    private func wait(_ seconds: Double) {
        let e = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { e.fulfill() }
        wait(for: [e], timeout: seconds + 2)
    }

    /// The exact scenario the independent review reproduced: three rapid
    /// enable/disable cycles produced six writes inside a millisecond.
    func test_rapidEnableDisableCycles_neverExceedFourWritesPerSecond() {
        let backend = TimestampingBackend()
        let coordinator = PWMSafeCoordinator(backends: [backend], pinVerifyDelay: 0.05, pollInterval: 10)

        for _ in 0..<3 {
            coordinator.sync(pwmSafeRequested: true, displays: [display()])
            coordinator.sync(pwmSafeRequested: false, displays: [display()])
        }
        wait(1.2)

        // §3.4 stated literally: no 1-second window may contain more than
        // four writes.
        let times = backend.writes.map(\.at).sorted()
        for (index, start) in times.enumerated() {
            let inWindow = times[index...].prefix { $0.timeIntervalSince(start) < 1.0 }.count
            XCTAssertLessThanOrEqual(
                inWindow, 4,
                "\(inWindow) writes within one second starting at write \(index) — CLAUDE.md §3.4 allows 4"
            )
        }
        XCTAssertFalse(backend.writes.isEmpty, "the first pin should still have happened")
    }

    /// Restores must not be delayed — `applicationWillTerminate` cannot wait.
    func test_restoreOnQuit_isImmediate_evenRightAfterAPin() {
        let backend = TimestampingBackend()
        backend.value = 0.4
        let coordinator = PWMSafeCoordinator(backends: [backend], pinVerifyDelay: 0.05, pollInterval: 10)

        coordinator.sync(pwmSafeRequested: true, displays: [display()])
        XCTAssertEqual(backend.value, 1.0, "pin should have happened")

        // Immediately, as a Cmd-Q would.
        coordinator.restoreAndDisable()
        XCTAssertEqual(backend.value, 0.4, "the restore must not be deferred by the rate limit")
    }

    /// Finding 6: hardware brightness outlives the cable.
    func test_disconnectAndReconnect_stillRestoresTheOriginalBrightness() {
        let backend = TimestampingBackend()
        backend.value = 0.4
        let coordinator = PWMSafeCoordinator(backends: [backend], pinVerifyDelay: 0.05, pollInterval: 10)

        coordinator.sync(pwmSafeRequested: true, displays: [display()])
        XCTAssertEqual(backend.value, 1.0)

        // Unplugged while pinned: the panel is still physically at 1.0.
        coordinator.sync(pwmSafeRequested: true, displays: [])
        // Plugged back in.
        coordinator.sync(pwmSafeRequested: true, displays: [display()])
        wait(0.4)

        coordinator.restoreAndDisable()
        XCTAssertEqual(backend.value, 0.4, "reconnecting must not overwrite the remembered original with the pin's own 1.0")
    }
}
