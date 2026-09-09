import Foundation

/// CLAUDE.md §3.8: "Manual (default), Sunset->Sunrise, Fixed times."
enum ScheduleMode: String, Codable, CaseIterable {
    case manual
    case sunsetToSunrise
    case fixedTimes
}

/// A wall-clock time, timezone-agnostic — interpreted against whatever
/// `Calendar` the caller supplies (always the user's own local calendar in
/// practice, since "bedtime" only makes sense as *their* clock time).
struct TimeOfDay: Codable, Equatable {
    var hour: Int
    var minute: Int

    static let defaultBedtime = TimeOfDay(hour: 22, minute: 30)
}

/// Everything the schedule needs to know, persisted as one unit.
/// `location` is deliberately optional and separate from `selectedCityID`:
/// the coordinate is what the math needs, the city id is only so Settings
/// can show which bundled city (if any) produced it, and "manual lat/lon"
/// (CLAUDE.md §3.8) or a CoreLocation fix both set `location` with no city
/// id at all.
struct ScheduleConfig: Codable, Equatable {
    var mode: ScheduleMode
    var location: Coordinate?
    var selectedCityID: String?
    var bedtime: TimeOfDay
    var fixedDayStart: TimeOfDay
    var fixedEveningStart: TimeOfDay
    /// CLAUDE.md §3.8: "linear ramp over a user-set duration (default 20 min)."
    var rampMinutes: Int

    static let defaults = ScheduleConfig(
        mode: .manual,
        location: nil,
        selectedCityID: nil,
        bedtime: .defaultBedtime,
        fixedDayStart: TimeOfDay(hour: 7, minute: 0),
        fixedEveningStart: TimeOfDay(hour: 18, minute: 0),
        rampMinutes: 20
    )
}

/// One anchor point in a day's schedule: "starting at `start`, ramp toward
/// `preset` over `rampMinutes`." ARCHITECTURE.md §3's sketch.
struct SchedulePhase: Equatable {
    let preset: PresetID
    let start: Date
    let rampMinutes: Int
}

/// A pure function over time, plus the small amount of state
/// (`ScheduleConfig`) that shapes it — ARCHITECTURE.md §3. No I/O, no
/// timers, no CoreLocation: those live in `ScheduleCoordinator`, which
/// calls this and nothing else calls the sun/clock APIs directly.
enum ScheduleEngine {
    /// The day's phases, anchored to `day`'s own date (sunrise/sunset are
    /// computed for that specific calendar day). Empty for `.manual`, and
    /// empty for `.sunsetToSunrise` with no location configured yet or with
    /// a location where the sun doesn't rise/set that day (polar day/night)
    /// — never a guess in either case.
    static func phases(for day: Date, mode: ScheduleMode, config: ScheduleConfig, calendar: Calendar) -> [SchedulePhase] {
        switch mode {
        case .manual:
            return []

        case .sunsetToSunrise:
            guard let location = config.location,
                  let sunrise = SolarCalculator.sunrise(for: day, at: location, timeZone: calendar.timeZone),
                  let sunset = SolarCalculator.sunset(for: day, at: location, timeZone: calendar.timeZone)
            else { return [] }
            // The mode's own name promises a full cycle: warm from sunset,
            // back to neutral at sunrise. CLAUDE.md §3.8's prose spells out
            // only the sunset->EVENING and bedtime->NIGHT transitions
            // explicitly; the sunrise->DAY transition is this cycle's
            // reading of what "Sunset->Sunrise" as a mode name implies,
            // documented here since the source doc doesn't spell it out.
            return [
                SchedulePhase(preset: .day, start: sunrise, rampMinutes: config.rampMinutes),
                SchedulePhase(preset: .evening, start: sunset, rampMinutes: config.rampMinutes),
                SchedulePhase(preset: .night, start: clockTime(config.bedtime, on: day, calendar: calendar), rampMinutes: config.rampMinutes),
            ]

        case .fixedTimes:
            return [
                SchedulePhase(preset: .day, start: clockTime(config.fixedDayStart, on: day, calendar: calendar), rampMinutes: config.rampMinutes),
                SchedulePhase(preset: .evening, start: clockTime(config.fixedEveningStart, on: day, calendar: calendar), rampMinutes: config.rampMinutes),
                SchedulePhase(preset: .night, start: clockTime(config.bedtime, on: day, calendar: calendar), rampMinutes: config.rampMinutes),
            ]
        }
    }

    /// `phases(for:)` for one calendar day, merged with the day before it
    /// and sorted — what a caller actually wants for evaluating "now,"
    /// since a query shortly after midnight needs to see last night's
    /// bedtime phase (started before midnight) rather than finding nothing
    /// until today's own first phase begins. Two days is always enough:
    /// every phase's ramp completes within hours, never past a second
    /// midnight.
    static func phases(coveringDayOf now: Date, mode: ScheduleMode, config: ScheduleConfig, calendar: Calendar) -> [SchedulePhase] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        return (phases(for: yesterday, mode: mode, config: config, calendar: calendar)
            + phases(for: today, mode: mode, config: config, calendar: calendar))
            .sorted { $0.start < $1.start }
    }

    /// The phase in effect at `now` — the most recent one whose `start` has
    /// already passed. `nil` only if `now` precedes every phase supplied
    /// (or `phases` is empty), which in practice means "the schedule has
    /// nothing to say yet." Shared by `target(at:phases:values:)` and by
    /// `ScheduleCoordinator`, which needs it on its own to detect when a
    /// manual override has been superseded by a new phase boundary.
    static func activePhase(at now: Date, phases: [SchedulePhase]) -> SchedulePhase? {
        phases.sorted { $0.start < $1.start }.last { $0.start <= now }
    }

    /// The warmth/brightness the schedule wants right now, or `nil` if the
    /// schedule has nothing to say (no phases at all, or `now` precedes
    /// every phase in the supplied list) — the caller's cue to leave
    /// `AppState` exactly as it is rather than snapping to some default.
    ///
    /// `values` looks up the *effective* (possibly user-overridden, C4)
    /// values for a preset, never `PresetID.defaultValues` directly: a
    /// user who customized EVENING must get their own EVENING from the
    /// schedule, not the factory one.
    ///
    /// Deliberately returns only warmth/brightness, not an on/off state —
    /// matching ARCHITECTURE.md §3's function signature exactly. The
    /// schedule steers *what* the filter would show; whether it is showing
    /// anything at all stays the user's own ON/OFF toggle, same as the
    /// popover sliders already behave while OFF. This is also the safer
    /// choice: an automatic mode that could switch itself on unprompted
    /// (mid screen-share, say) is a worse surprise than one that only ever
    /// adjusts values the user has already chosen to display.
    static func target(at now: Date, phases: [SchedulePhase], values: (PresetID) -> PresetValues) -> PresetValues? {
        let sorted = phases.sorted { $0.start < $1.start }
        guard let activeIndex = sorted.lastIndex(where: { $0.start <= now }) else { return nil }

        let active = sorted[activeIndex]
        let target = values(active.preset)
        guard active.rampMinutes > 0 else { return target }

        let rampEnd = active.start.addingTimeInterval(Double(active.rampMinutes) * 60)
        guard now < rampEnd else { return target }

        let previousPreset = activeIndex > 0 ? sorted[activeIndex - 1].preset : PresetID.day
        let previous = values(previousPreset)
        let duration = rampEnd.timeIntervalSince(active.start)
        let fraction = duration > 0 ? (now.timeIntervalSince(active.start) / duration).clamped(to: 0...1) : 1.0

        return PresetValues(
            warmthK: previous.warmthK + (target.warmthK - previous.warmthK) * fraction,
            brightness: previous.brightness + (target.brightness - previous.brightness) * fraction
        )
    }

    private static func clockTime(_ time: TimeOfDay, on day: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day) ?? day
    }
}
