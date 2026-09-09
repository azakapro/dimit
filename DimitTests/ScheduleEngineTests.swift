import XCTest
@testable import Dimit

final class ScheduleEngineTests: XCTestCase {
    private let tashkent = Coordinate(latitude: 41.2995, longitude: 69.2401)
    private var tz: TimeZone { TimeZone(identifier: "Asia/Tashkent")! }
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        return c
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour; c.minute = minute
        return calendar.date(from: c)!
    }

    private struct HourMinute: Equatable, CustomStringConvertible {
        let hour: Int
        let minute: Int
        var description: String { String(format: "%02d:%02d", hour, minute) }
    }
    private func hm(_ d: Date) -> HourMinute {
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return HourMinute(hour: c.hour!, minute: c.minute!)
    }

    private func values(for preset: PresetID) -> PresetValues { preset.defaultValues }

    private func sunsetToSunriseConfig(rampMinutes: Int = 20) -> ScheduleConfig {
        var c = ScheduleConfig.defaults
        c.mode = .sunsetToSunrise
        c.location = tashkent
        c.rampMinutes = rampMinutes
        c.bedtime = TimeOfDay(hour: 22, minute: 30)
        return c
    }

    // MARK: - phases(for:)

    func test_manualMode_hasNoPhases() {
        let config = ScheduleConfig.defaults // .manual
        let phases = ScheduleEngine.phases(for: date(2026, 9, 8), mode: .manual, config: config, calendar: calendar)
        XCTAssertTrue(phases.isEmpty)
    }

    func test_sunsetToSunrise_withNoLocationConfigured_hasNoPhases() {
        var config = ScheduleConfig.defaults
        config.mode = .sunsetToSunrise
        config.location = nil
        let phases = ScheduleEngine.phases(for: date(2026, 9, 8), mode: .sunsetToSunrise, config: config, calendar: calendar)
        XCTAssertTrue(phases.isEmpty, "no location means nothing to compute — must not crash or guess")
    }

    // CLAUDE.md §3.8: "linear ramp ... from DAY preset to EVENING at sunset
    // and to NIGHT at bedtime." Plus a third, implied by the mode's own name
    // "Sunset->Sunrise": back to DAY at sunrise. Documented here since
    // CLAUDE.md's prose only spells out two of the three transitions.
    func test_sunsetToSunrise_producesThreePhases_atSunrise_sunset_andBedtime() {
        let config = sunsetToSunriseConfig()
        let phases = ScheduleEngine.phases(for: date(2026, 9, 8), mode: .sunsetToSunrise, config: config, calendar: calendar)
        XCTAssertEqual(phases.count, 3)

        let sunrisePhase = phases.first { $0.preset == .day }
        let sunsetPhase = phases.first { $0.preset == .evening }
        let bedtimePhase = phases.first { $0.preset == .night }
        XCTAssertNotNil(sunrisePhase); XCTAssertNotNil(sunsetPhase); XCTAssertNotNil(bedtimePhase)

        // Cross-check against SolarCalculatorTests' own verified Tashkent reference.
        XCTAssertEqual(hm(sunrisePhase!.start).hour, 5)
        XCTAssertEqual(hm(sunsetPhase!.start).hour, 18)
        XCTAssertEqual(hm(bedtimePhase!.start), HourMinute(hour: 22, minute: 30))
        XCTAssertEqual(sunrisePhase!.rampMinutes, 20)
    }

    func test_fixedTimes_usesConfiguredClockTimes_notSolarComputation() {
        var config = ScheduleConfig.defaults
        config.mode = .fixedTimes
        config.fixedDayStart = TimeOfDay(hour: 7, minute: 0)
        config.fixedEveningStart = TimeOfDay(hour: 19, minute: 30)
        config.bedtime = TimeOfDay(hour: 23, minute: 0)

        let phases = ScheduleEngine.phases(for: date(2026, 9, 8), mode: .fixedTimes, config: config, calendar: calendar)
        XCTAssertEqual(phases.count, 3)
        XCTAssertEqual(hm(phases.first { $0.preset == .day }!.start), HourMinute(hour: 7, minute: 0))
        XCTAssertEqual(hm(phases.first { $0.preset == .evening }!.start), HourMinute(hour: 19, minute: 30))
        XCTAssertEqual(hm(phases.first { $0.preset == .night }!.start), HourMinute(hour: 23, minute: 0))
    }

    func test_fixedTimes_ignoresLocation_evenIfSomehowSet() {
        var config = ScheduleConfig.defaults
        config.mode = .fixedTimes
        config.location = tashkent // should simply be irrelevant to this mode
        let phases = ScheduleEngine.phases(for: date(2026, 9, 8), mode: .fixedTimes, config: config, calendar: calendar)
        XCTAssertEqual(phases.count, 3, "fixed mode must not silently fail just because a location happens to be set")
    }

    // MARK: - target(at:phases:values:)

    func test_target_beforeAnyPhaseInTheWindow_returnsNil_soCallerLeavesStateAlone() {
        // No phases at all (manual mode) is the simplest way to hit "no
        // active phase" without constructing a contrived pre-dawn instant.
        let result = ScheduleEngine.target(at: date(2026, 9, 8, 3, 0), phases: [], values: values)
        XCTAssertNil(result)
    }

    func test_target_wellAfterAPhaseStarts_returnsThatPresetsExactValues() {
        let config = sunsetToSunriseConfig(rampMinutes: 20)
        let phases = ScheduleEngine.phases(for: date(2026, 9, 8), mode: .sunsetToSunrise, config: config, calendar: calendar)
        // Bedtime is 22:30; 22:31 is one minute in, well past a 20-min ramp is NOT true yet —
        // use a time well past the ramp's end instead.
        let target = ScheduleEngine.target(at: date(2026, 9, 8, 23, 0), phases: phases, values: values)
        XCTAssertEqual(target, PresetID.night.defaultValues)
    }

    func test_target_duringARamp_interpolatesLinearly() {
        let config = sunsetToSunriseConfig(rampMinutes: 20)
        let phases = ScheduleEngine.phases(for: date(2026, 9, 8), mode: .sunsetToSunrise, config: config, calendar: calendar)
        let bedtimePhase = phases.first { $0.preset == .night }!

        let midRamp = bedtimePhase.start.addingTimeInterval(10 * 60) // 10 of 20 minutes in
        let target = try! XCTUnwrap(ScheduleEngine.target(at: midRamp, phases: phases, values: values))

        let evening = PresetID.evening.defaultValues
        let night = PresetID.night.defaultValues
        XCTAssertEqual(target.warmthK, (evening.warmthK + night.warmthK) / 2, accuracy: 1.0)
        XCTAssertEqual(target.brightness, (evening.brightness + night.brightness) / 2, accuracy: 0.01)
    }

    func test_target_atTheExactStartOfARamp_equalsThePreviousPhasesValues() {
        let config = sunsetToSunriseConfig(rampMinutes: 20)
        let phases = ScheduleEngine.phases(for: date(2026, 9, 8), mode: .sunsetToSunrise, config: config, calendar: calendar)
        let bedtimePhase = phases.first { $0.preset == .night }!
        let target = try! XCTUnwrap(ScheduleEngine.target(at: bedtimePhase.start, phases: phases, values: values))
        XCTAssertEqual(target, PresetID.evening.defaultValues, "at t=0 of the ramp, nothing has changed yet")
    }

    func test_target_zeroRampMinutes_jumpsInstantlyRatherThanDivideByZero() {
        let config = sunsetToSunriseConfig(rampMinutes: 0)
        let phases = ScheduleEngine.phases(for: date(2026, 9, 8), mode: .sunsetToSunrise, config: config, calendar: calendar)
        let bedtimePhase = phases.first { $0.preset == .night }!
        let target = try! XCTUnwrap(ScheduleEngine.target(at: bedtimePhase.start, phases: phases, values: values))
        XCTAssertEqual(target, PresetID.night.defaultValues)
    }

    // The whole reason `target` takes a `values` closure instead of reading
    // `PresetID.defaultValues` itself: a user who has customized EVENING in
    // Settings (C4) must get their own EVENING from the schedule, not the
    // factory default. An earlier review of C4 flagged `PresetID.warmthK`/
    // `.brightness` as exactly this footgun for whichever cycle built
    // scheduling — this test is the guard against reintroducing it.
    func test_target_usesInjectedValues_notHardcodedDefaults() {
        let config = sunsetToSunriseConfig(rampMinutes: 20)
        let phases = ScheduleEngine.phases(for: date(2026, 9, 8), mode: .sunsetToSunrise, config: config, calendar: calendar)
        let customEvening = PresetValues(warmthK: 3300, brightness: 0.65)
        let customValues: (PresetID) -> PresetValues = { preset in
            preset == .evening ? customEvening : preset.defaultValues
        }
        let sunsetPhase = phases.first { $0.preset == .evening }!
        let target = try! XCTUnwrap(ScheduleEngine.target(
            at: sunsetPhase.start.addingTimeInterval(21 * 60), // past the 20-min ramp
            phases: phases, values: customValues
        ))
        XCTAssertEqual(target, customEvening)
    }

    // MARK: - Day-boundary wraparound (the reason phases cover 2 days)

    func test_phasesCoveringDayOf_mergesYesterdayAndToday_soPastMidnightStillFindsLastNightsPhase() {
        let config = sunsetToSunriseConfig(rampMinutes: 20)
        let justAfterMidnight = date(2026, 9, 9, 0, 30) // between yesterday's bedtime and today's sunrise
        let phases = ScheduleEngine.phases(coveringDayOf: justAfterMidnight, mode: .sunsetToSunrise, config: config, calendar: calendar)
        let target = try! XCTUnwrap(ScheduleEngine.target(at: justAfterMidnight, phases: phases, values: values))
        XCTAssertEqual(target, PresetID.night.defaultValues, "00:30 is well after yesterday's 22:30 bedtime and well before today's ~05:56 sunrise")
    }

    func test_phasesCoveringDayOf_atSunrise_returnsToDayPreset() {
        let config = sunsetToSunriseConfig(rampMinutes: 20)
        let phases = ScheduleEngine.phases(coveringDayOf: date(2026, 9, 8, 12, 0), mode: .sunsetToSunrise, config: config, calendar: calendar)
        let midMorning = date(2026, 9, 8, 8, 0) // well after sunrise (~05:56), well before sunset
        let target = try! XCTUnwrap(ScheduleEngine.target(at: midMorning, phases: phases, values: values))
        XCTAssertEqual(target, PresetID.day.defaultValues)
    }
}
