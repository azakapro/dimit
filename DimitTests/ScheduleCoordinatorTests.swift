import XCTest
@testable import Dimit

/// The real production `ScheduleCoordinator` runs off a live `Timer` and
/// `Date()` — these tests inject both so every scenario is evaluated by
/// calling `evaluateNow()` directly at a chosen instant, never by waiting
/// on real wall-clock time. The Timer scheduling itself (interval choice,
/// tolerance, run-loop mode) has no fake to run against and is untested,
/// same disclosed limitation as `HotkeyManager`'s registration layer.
@MainActor
final class ScheduleCoordinatorTests: XCTestCase {
    private var tz: TimeZone { TimeZone(identifier: "Asia/Tashkent")! }
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        return c
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour; c.minute = minute
        c.timeZone = tz
        return calendar.date(from: c)!
    }

    private func freshState() -> AppState {
        AppState(persistence: Persistence(suiteName: "test.\(UUID().uuidString)"))
    }

    private func sunsetToSunriseConfig(rampMinutes: Int = 20) -> ScheduleConfig {
        var c = ScheduleConfig.defaults
        c.mode = .sunsetToSunrise
        c.location = Coordinate(latitude: 41.2995, longitude: 69.2401)
        c.rampMinutes = rampMinutes
        c.bedtime = TimeOfDay(hour: 22, minute: 30)
        return c
    }

    /// A mutable "clock" the test controls, so `now()` inside the
    /// coordinator advances only when the test says so.
    private final class TestClock {
        var current: Date
        init(_ start: Date) { current = start }
        func now() -> Date { current }
    }

    // MARK: - Basic driving

    func test_manualMode_writesNothing_evenWhenEvaluated() {
        let state = freshState()
        state.warmthK = 6500
        let clock = TestClock(date(2026, 9, 8, 20, 0))
        let coordinator = ScheduleCoordinator(appState: state, calendar: { self.calendar }, now: clock.now)
        coordinator.evaluateNow()
        XCTAssertEqual(state.warmthK, 6500, "manual mode must never touch AppState")
    }

    func test_sunsetToSunrise_atBedtimePlusRampDuration_landsExactlyOnNight() {
        let state = freshState()
        state.scheduleConfig = sunsetToSunriseConfig(rampMinutes: 20)
        let clock = TestClock(date(2026, 9, 8, 12, 0)) // noon, before anything interesting
        let coordinator = ScheduleCoordinator(appState: state, calendar: { self.calendar }, now: clock.now)

        clock.current = date(2026, 9, 8, 23, 0) // well past 22:30 + 20 min ramp
        coordinator.evaluateNow()

        XCTAssertEqual(state.warmthK, PresetID.night.defaultValues.warmthK)
        XCTAssertEqual(state.brightness, PresetID.night.defaultValues.brightness)
    }

    func test_sunsetToSunrise_midRamp_writesAnInterpolatedValue() {
        let state = freshState()
        state.scheduleConfig = sunsetToSunriseConfig(rampMinutes: 20)
        let clock = TestClock(date(2026, 9, 8, 12, 0))
        let coordinator = ScheduleCoordinator(appState: state, calendar: { self.calendar }, now: clock.now)

        clock.current = date(2026, 9, 8, 22, 40) // 10 of 20 minutes into the bedtime ramp
        coordinator.evaluateNow()

        let evening = PresetID.evening.defaultValues
        let night = PresetID.night.defaultValues
        XCTAssertEqual(state.warmthK, (evening.warmthK + night.warmthK) / 2, accuracy: 5)
        XCTAssertNotEqual(state.warmthK, night.warmthK, "must not have jumped straight to the target")
    }

    // MARK: - Manual override pauses the schedule (ARCHITECTURE.md §3)

    func test_manualSliderMove_pausesTheSchedule_untilTheNextPhaseBoundary() {
        let state = freshState()
        state.scheduleConfig = sunsetToSunriseConfig(rampMinutes: 20)
        let clock = TestClock(date(2026, 9, 8, 23, 0)) // settled into NIGHT already
        let coordinator = ScheduleCoordinator(appState: state, calendar: { self.calendar }, now: clock.now)
        coordinator.evaluateNow()
        XCTAssertEqual(state.warmthK, PresetID.night.defaultValues.warmthK)

        // The user drags the warmth slider by hand.
        state.warmthK = 3000
        XCTAssertNotNil(coordinator.pausedAtPhaseStart, "a manual change must register as an override")

        // Time passes, still within the same NIGHT phase — the schedule
        // must NOT stomp the user's manual value.
        clock.current = date(2026, 9, 9, 2, 0)
        coordinator.evaluateNow()
        XCTAssertEqual(state.warmthK, 3000, "schedule must stay paused inside the phase the user overrode")
    }

    func test_pausedSchedule_resumesAutomatically_onceANewPhaseBegins() {
        let state = freshState()
        state.scheduleConfig = sunsetToSunriseConfig(rampMinutes: 20)
        let clock = TestClock(date(2026, 9, 8, 23, 0))
        let coordinator = ScheduleCoordinator(appState: state, calendar: { self.calendar }, now: clock.now)
        coordinator.evaluateNow()

        state.warmthK = 3000 // manual override during NIGHT
        XCTAssertNotNil(coordinator.pausedAtPhaseStart)

        // Cross into tomorrow's sunrise phase — a genuinely new boundary.
        clock.current = date(2026, 9, 9, 6, 30)
        coordinator.evaluateNow()

        XCTAssertNil(coordinator.pausedAtPhaseStart, "crossing a phase boundary must resume the schedule")
        XCTAssertEqual(state.warmthK, PresetID.day.defaultValues.warmthK, "and the schedule should be driving again")
    }

    // The coordinator's own writes must never be mistaken for a manual
    // override — otherwise the schedule would immediately pause itself on
    // every single tick it ever performs.
    func test_theCoordinatorsOwnWrites_doNotTriggerAPause() {
        let state = freshState()
        state.scheduleConfig = sunsetToSunriseConfig(rampMinutes: 20)
        let clock = TestClock(date(2026, 9, 8, 23, 0))
        let coordinator = ScheduleCoordinator(appState: state, calendar: { self.calendar }, now: clock.now)

        coordinator.evaluateNow() // the schedule itself writes warmthK/brightness here
        XCTAssertNil(coordinator.pausedAtPhaseStart, "the schedule's own write must not look like a user override")
    }

    // MARK: - Config changes

    func test_changingScheduleConfig_clearsAnExistingPause() {
        let state = freshState()
        state.scheduleConfig = sunsetToSunriseConfig(rampMinutes: 20)
        let clock = TestClock(date(2026, 9, 8, 23, 0))
        let coordinator = ScheduleCoordinator(appState: state, calendar: { self.calendar }, now: clock.now)
        coordinator.evaluateNow()
        state.warmthK = 3000
        XCTAssertNotNil(coordinator.pausedAtPhaseStart)

        state.scheduleConfig.rampMinutes = 30 // any config change

        XCTAssertNil(coordinator.pausedAtPhaseStart, "a deliberate config change should not leave a stale pause behind")
    }

    func test_switchingToManualMode_stopsWritingEvenIfPreviouslyActive() {
        let state = freshState()
        state.scheduleConfig = sunsetToSunriseConfig(rampMinutes: 20)
        let clock = TestClock(date(2026, 9, 8, 23, 0))
        let coordinator = ScheduleCoordinator(appState: state, calendar: { self.calendar }, now: clock.now)
        coordinator.evaluateNow()
        XCTAssertEqual(state.warmthK, PresetID.night.defaultValues.warmthK)

        state.scheduleConfig.mode = .manual
        state.warmthK = 5000 // now a perfectly normal manual change
        clock.current = date(2026, 9, 9, 6, 30) // would have been a new phase, if schedule were active
        coordinator.evaluateNow()

        XCTAssertEqual(state.warmthK, 5000, "manual mode must leave whatever the user set alone")
    }
}
