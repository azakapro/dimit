import Foundation

/// A point on Earth. `longitude` is signed east-positive/west-negative, as
/// the NOAA formulas below expect.
struct Coordinate: Codable, Equatable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Same `decodeIfPresent`-per-field reasoning as `ScheduleConfig`'s own
    /// decoder (`ScheduleEngine.swift`) — persisted inside it as `location`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude) ?? 0
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude) ?? 0
    }
}

/// Local sunrise/sunset via the NOAA solar position algorithm — CLAUDE.md
/// §3.8: "Compute sunrise/sunset locally with the NOAA solar algorithm
/// (unit tests vs known values for Tashkent on 2026-09-08)." No network:
/// this is the public-domain astronomical formula behind NOAA's own solar
/// calculator spreadsheet (in turn based on Jean Meeus, *Astronomical
/// Algorithms*), not a fetch to any NOAA service.
///
/// Two-pass refinement (see `sunEvent(rise:on:at:)`): the equation of time
/// and solar declination both drift slightly over the course of a day, so
/// the first-pass estimate (using local solar noon as the reference moment)
/// is used to compute a second, more accurate pass at the actual event
/// time. This is part of the standard algorithm, not an addition — it's
/// what keeps the result within the ±3 min tolerance CLAUDE.md specifies
/// away from the reference meridian.
enum SolarCalculator {
    static func sunrise(for day: Date, at location: Coordinate, timeZone: TimeZone) -> Date? {
        sunEvent(rise: true, on: day, at: location, timeZone: timeZone)
    }

    static func sunset(for day: Date, at location: Coordinate, timeZone: TimeZone) -> Date? {
        sunEvent(rise: false, on: day, at: location, timeZone: timeZone)
    }

    // MARK: - Core algorithm

    private static func sunEvent(rise: Bool, on day: Date, at location: Coordinate, timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        guard let year = components.year, let month = components.month, let dayOfMonth = components.day else { return nil }

        // Julian Day at 0h UT for this calendar date (Meeus's formula).
        let jd = julianDay(year: year, month: month, day: Double(dayOfMonth))

        // First pass: estimate using local solar noon as the reference
        // instant for the slowly-varying quantities (equation of time,
        // declination).
        let t0 = julianCentury(jd + 0.5)
        guard let firstPassMinutes = minutesUTC(rise: rise, t: t0, latitude: location.latitude, longitude: location.longitude) else {
            return nil // sun does not rise/set at all on this day at this latitude
        }

        // Second pass: recompute at the actual estimated event time, not
        // just at noon, for the accuracy NOAA's own calculator achieves.
        let t1 = julianCentury(jd + firstPassMinutes / 1440.0)
        guard let refinedMinutes = minutesUTC(rise: rise, t: t1, latitude: location.latitude, longitude: location.longitude) else {
            return nil
        }

        // `refinedMinutes` is minutes past UTC midnight of the calendar date
        // `jd` represents. Build the Date from UTC midnight + that offset,
        // rather than from `day` directly, since `day` carries a local
        // time-of-day component we don't want to inherit.
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        guard let utcMidnight = utcCalendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth)) else { return nil }
        return utcMidnight.addingTimeInterval(refinedMinutes * 60)
    }

    /// Minutes past UTC midnight for the sunrise (`rise: true`) or sunset
    /// (`rise: false`) implied by Julian century `t`, or `nil` if the sun
    /// does not cross the horizon that day at this latitude (polar
    /// day/night) — the `acos` argument falls outside `[-1, 1]` in exactly
    /// that case, and `Foundation.acos` would otherwise return NaN.
    private static func minutesUTC(rise: Bool, t: Double, latitude: Double, longitude: Double) -> Double? {
        let eqTime = equationOfTimeMinutes(t)
        let declination = sunDeclinationDegrees(t)
        guard let hourAngle = hourAngleDegrees(latitude: latitude, solarDeclination: declination) else { return nil }

        // Derived from first principles, not transcribed from memory, after
        // an initial version swapped sunrise and sunset outright (caught by
        // `test_sunrise_isBeforeSunset_onTheSameDay`) and a first "fix" put
        // both events a full 9+ hours off (caught by the Tashkent reference
        // test) — a wrong recollection of a formula can pass a sanity check
        // and still be wrong, so this was re-derived and checked against
        // Tashkent AND a second, independent reference (London winter
        // solstice) before trusting it:
        //
        // Mean solar noon at Greenwich is UTC 12:00 by definition of mean
        // solar time; a point at longitude L (east-positive) reaches solar
        // noon 4 minutes-of-time earlier per degree of L, since the Earth
        // rotates eastward — so mean solar noon there is `720 - 4L` UTC
        // minutes. The equation of time then corrects mean noon to apparent
        // (true) noon: this implementation's sign convention for `eqTime`
        // (see `equationOfTimeMinutes`) is "positive means the true sun
        // transits before the mean sun," so apparent noon is mean noon
        // *minus* eqTime. Sunrise/sunset are symmetric around that apparent
        // noon by the hour angle, converted from degrees to minutes at the
        // same 4 min/degree rate Earth's rotation gives everywhere.
        let solarNoonUTC = 720 - 4 * longitude - eqTime
        return rise ? solarNoonUTC - 4 * hourAngle : solarNoonUTC + 4 * hourAngle
    }

    // MARK: - Julian day / century

    /// Meeus's Julian Day Number formula for a Gregorian calendar date, at
    /// 0h UT. `day` takes a `Double` so callers needing sub-day precision
    /// could add a fractional part, though every caller here passes a
    /// whole day.
    private static func julianDay(year: Int, month: Int, day: Double) -> Double {
        var y = year
        var m = month
        if m <= 2 { y -= 1; m += 12 }
        let a = floor(Double(y) / 100)
        let b = 2 - a + floor(a / 4)
        return floor(365.25 * Double(y + 4716)) + floor(30.6001 * Double(m + 1)) + day + b - 1524.5
    }

    private static func julianCentury(_ jd: Double) -> Double {
        (jd - 2451545.0) / 36525.0
    }

    // MARK: - Solar position (all angles in degrees unless noted)

    private static func geomMeanLongitude(_ t: Double) -> Double {
        var l0 = 280.46646 + t * (36000.76983 + t * 0.0003032)
        l0 = l0.truncatingRemainder(dividingBy: 360)
        return l0 < 0 ? l0 + 360 : l0
    }

    private static func geomMeanAnomaly(_ t: Double) -> Double {
        357.52911 + t * (35999.05029 - 0.0001537 * t)
    }

    private static func eccentricityEarthOrbit(_ t: Double) -> Double {
        0.016708634 - t * (0.000042037 + 0.0000001267 * t)
    }

    private static func sunEqOfCenter(_ t: Double) -> Double {
        let m = geomMeanAnomaly(t)
        let mRad = m * .pi / 180
        return sin(mRad) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2 * mRad) * (0.019993 - 0.000101 * t)
            + sin(3 * mRad) * 0.000289
    }

    private static func sunApparentLongitude(_ t: Double) -> Double {
        let trueLongitude = geomMeanLongitude(t) + sunEqOfCenter(t)
        let omega = 125.04 - 1934.136 * t
        return trueLongitude - 0.00569 - 0.00478 * sin(omega * .pi / 180)
    }

    private static func meanObliquityOfEcliptic(_ t: Double) -> Double {
        let seconds = 21.448 - t * (46.8150 + t * (0.00059 - t * 0.001813))
        return 23 + (26 + seconds / 60) / 60
    }

    private static func obliquityCorrection(_ t: Double) -> Double {
        let e0 = meanObliquityOfEcliptic(t)
        let omega = 125.04 - 1934.136 * t
        return e0 + 0.00256 * cos(omega * .pi / 180)
    }

    private static func sunDeclinationDegrees(_ t: Double) -> Double {
        let epsilon = obliquityCorrection(t) * .pi / 180
        let lambda = sunApparentLongitude(t) * .pi / 180
        let sinDeclination = sin(epsilon) * sin(lambda)
        return asin(sinDeclination) * 180 / .pi
    }

    private static func equationOfTimeMinutes(_ t: Double) -> Double {
        let epsilon = obliquityCorrection(t)
        let l0 = geomMeanLongitude(t)
        let e = eccentricityEarthOrbit(t)
        let m = geomMeanAnomaly(t)

        var y = tan((epsilon * .pi / 180) / 2)
        y *= y

        let l0Rad = l0 * .pi / 180
        let mRad = m * .pi / 180

        let etime = y * sin(2 * l0Rad)
            - 2 * e * sin(mRad)
            + 4 * e * y * sin(mRad) * cos(2 * l0Rad)
            - 0.5 * y * y * sin(4 * l0Rad)
            - 1.25 * e * e * sin(2 * mRad)
        return (etime * 180 / .pi) * 4
    }

    /// The half-day arc, in degrees, between solar noon and sunrise/sunset —
    /// symmetric, so sunset uses the negative of this same value. `90.833`
    /// degrees (rather than the geometric 90°) bakes in standard atmospheric
    /// refraction plus the sun's apparent radius, matching NOAA's own
    /// calculator. Returns `nil` when the argument to `acos` falls outside
    /// `[-1, 1]` — the sun never crosses the horizon that day at this
    /// latitude (polar day or polar night).
    private static func hourAngleDegrees(latitude: Double, solarDeclination: Double) -> Double? {
        let latRad = latitude * .pi / 180
        let decRad = solarDeclination * .pi / 180
        let cosH = cos(90.833 * .pi / 180) / (cos(latRad) * cos(decRad)) - tan(latRad) * tan(decRad)
        guard cosH >= -1, cosH <= 1 else { return nil }
        return acos(cosH) * 180 / .pi
    }
}
