import XCTest
@testable import Dimit

final class SolarCalculatorTests: XCTestCase {
    // Tashkent, 41.2995°N 69.2401°E, UTC+5, no DST. CLAUDE.md §3.8 / §8:
    // "unit tests vs known values for Tashkent on 2026-09-08" within ±3 min.
    //
    // Reference cross-checked against three independent public sunrise/sunset
    // calculators for this date (2026-09-09, since this test was written the
    // day after): they agree to within a minute or two of each other at
    // 05:56–05:57 sunrise, 18:43–18:45 sunset, local time (UTC+5). This test
    // uses 05:57 / 18:44 as the midpoint of that spread.
    private let tashkent = Coordinate(latitude: 41.2995, longitude: 69.2401)
    private let tashkentTimeZone = TimeZone(identifier: "Asia/Tashkent")!

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, timeZone: TimeZone) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute
        components.timeZone = timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: components)!
    }

    private func localHourMinute(_ date: Date, timeZone: TimeZone) -> (hour: Int, minute: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour!, c.minute!)
    }

    func test_tashkent_sunrise_matchesKnownReference_within3Minutes() throws {
        let day = date(2026, 9, 8, timeZone: tashkentTimeZone)
        let sunrise = try XCTUnwrap(SolarCalculator.sunrise(for: day, at: tashkent, timeZone: tashkentTimeZone))
        let (h, m) = localHourMinute(sunrise, timeZone: tashkentTimeZone)
        let minutesFromMidnight = h * 60 + m
        let referenceMinutes = 5 * 60 + 57
        XCTAssertLessThanOrEqual(abs(minutesFromMidnight - referenceMinutes), 3, "got \(h):\(String(format: "%02d", m)), expected ~05:57 ±3min")
    }

    func test_tashkent_sunset_matchesKnownReference_within3Minutes() throws {
        let day = date(2026, 9, 8, timeZone: tashkentTimeZone)
        let sunset = try XCTUnwrap(SolarCalculator.sunset(for: day, at: tashkent, timeZone: tashkentTimeZone))
        let (h, m) = localHourMinute(sunset, timeZone: tashkentTimeZone)
        let minutesFromMidnight = h * 60 + m
        let referenceMinutes = 18 * 60 + 44
        XCTAssertLessThanOrEqual(abs(minutesFromMidnight - referenceMinutes), 3, "got \(h):\(String(format: "%02d", m)), expected ~18:44 ±3min")
    }

    // A second, independent reference point, far from Tashkent in both
    // latitude and season. Two wrong formulas were caught while writing
    // this file — one swapped sunrise/sunset outright, one put both events
    // ~9 hours off — and each still "worked" well enough that a single
    // reference could plausibly have been a coincidence. This one is what
    // actually distinguished "the formula is right" from "it happens to
    // work for Tashkent in September."
    func test_london_winterSolstice_matchesKnownReference_within3Minutes() throws {
        let london = Coordinate(latitude: 51.5074, longitude: -0.1278)
        let utc = TimeZone(identifier: "UTC")!
        let day = date(2026, 12, 21, timeZone: utc)
        let sunrise = try XCTUnwrap(SolarCalculator.sunrise(for: day, at: london, timeZone: utc))
        let sunset = try XCTUnwrap(SolarCalculator.sunset(for: day, at: london, timeZone: utc))
        let (rh, rm) = localHourMinute(sunrise, timeZone: utc)
        let (sh, sm) = localHourMinute(sunset, timeZone: utc)
        XCTAssertLessThanOrEqual(abs((rh * 60 + rm) - (8 * 60 + 4)), 3, "sunrise got \(rh):\(String(format: "%02d", rm)), expected ~08:04 UTC")
        XCTAssertLessThanOrEqual(abs((sh * 60 + sm) - (15 * 60 + 53)), 3, "sunset got \(sh):\(String(format: "%02d", sm)), expected ~15:53 UTC")
    }

    func test_sunrise_isBeforeSunset_onTheSameDay() throws {
        let day = date(2026, 9, 8, timeZone: tashkentTimeZone)
        let sunrise = try XCTUnwrap(SolarCalculator.sunrise(for: day, at: tashkent, timeZone: tashkentTimeZone))
        let sunset = try XCTUnwrap(SolarCalculator.sunset(for: day, at: tashkent, timeZone: tashkentTimeZone))
        XCTAssertLessThan(sunrise, sunset)
    }

    // Known seasonal sanity check, not a precision claim: days get longer
    // approaching the June solstice from a March start.
    func test_dayLength_isLongerInJune_thanInMarch_northernHemisphere() throws {
        let march = date(2026, 3, 1, timeZone: tashkentTimeZone)
        let june = date(2026, 6, 21, timeZone: tashkentTimeZone)
        let marchLength = try XCTUnwrap(SolarCalculator.sunset(for: march, at: tashkent, timeZone: tashkentTimeZone))
            .timeIntervalSince(XCTUnwrap(SolarCalculator.sunrise(for: march, at: tashkent, timeZone: tashkentTimeZone)))
        let juneLength = try XCTUnwrap(SolarCalculator.sunset(for: june, at: tashkent, timeZone: tashkentTimeZone))
            .timeIntervalSince(XCTUnwrap(SolarCalculator.sunrise(for: june, at: tashkent, timeZone: tashkentTimeZone)))
        XCTAssertGreaterThan(juneLength, marchLength)
    }

    // Southern hemisphere: seasons invert. Buenos Aires, no known-value
    // oracle here, just checking the sign of the effect is right — a
    // latitude-sign bug would make this fail while every Tashkent test above
    // (northern hemisphere) still passed.
    func test_dayLength_isLongerInDecember_thanInJune_southernHemisphere() throws {
        let buenosAires = Coordinate(latitude: -34.6, longitude: -58.4)
        let tz = TimeZone(identifier: "America/Argentina/Buenos_Aires")!
        let june = date(2026, 6, 21, timeZone: tz)
        let december = date(2026, 12, 21, timeZone: tz)
        let juneLength = try XCTUnwrap(SolarCalculator.sunset(for: june, at: buenosAires, timeZone: tz))
            .timeIntervalSince(XCTUnwrap(SolarCalculator.sunrise(for: june, at: buenosAires, timeZone: tz)))
        let decemberLength = try XCTUnwrap(SolarCalculator.sunset(for: december, at: buenosAires, timeZone: tz))
            .timeIntervalSince(XCTUnwrap(SolarCalculator.sunrise(for: december, at: buenosAires, timeZone: tz)))
        XCTAssertGreaterThan(decemberLength, juneLength)
    }

    // Arctic summer: the sun never sets. Must return nil, never crash or NaN.
    func test_polarSummer_sunNeverSets_returnsNilNotCrash() {
        let tromso = Coordinate(latitude: 69.6, longitude: 18.9) // above the Arctic Circle
        let tz = TimeZone(identifier: "Europe/Oslo")!
        let midsummer = date(2026, 6, 21, timeZone: tz)
        XCTAssertNil(SolarCalculator.sunset(for: midsummer, at: tromso, timeZone: tz))
    }

    func test_polarWinter_sunNeverRises_returnsNilNotCrash() {
        let tromso = Coordinate(latitude: 69.6, longitude: 18.9)
        let tz = TimeZone(identifier: "Europe/Oslo")!
        let midwinter = date(2026, 12, 21, timeZone: tz)
        XCTAssertNil(SolarCalculator.sunrise(for: midwinter, at: tromso, timeZone: tz))
    }
}
