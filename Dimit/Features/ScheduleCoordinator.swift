import Combine
import Foundation

/// The driver for `ScheduleEngine` — ARCHITECTURE.md §3: "wakes once per
/// minute (tolerance 30s) and during a ramp every 10s, sets
/// AppState.warmthK/brightness ... so a manual slider move pauses the
/// schedule until the next phase boundary."
///
/// `calendar`/`now` are injectable so tests can pin exactly what "today"
/// and "the current instant" are — the same reason `PWMSafeCoordinator`
/// injects its delays, applied here to time itself rather than to a retry
/// interval. The real Timer that drives production ticking is *not*
/// unit-tested (there is nothing to fake it against without a much bigger
/// injection surface than this cycle's scope justifies); `evaluateNow()`
/// is the tested entry point, called both by the timer and directly by
/// `ScheduleCoordinatorTests`.
@MainActor
final class ScheduleCoordinator {
    private let appState: AppState
    private let calendar: () -> Calendar
    private let now: () -> Date

    private var tickTimer: Timer?
    private var cachedPhases: [SchedulePhase] = []
    private var cachedPhasesDay: Date?

    /// Set to the active phase's `start` the moment a manual change is
    /// detected; cleared once `now` has moved into a *later* phase than
    /// that one. While set, `evaluateNow()` writes nothing.
    private(set) var pausedAtPhaseStart: Date?

    /// Guards the one write path that must NOT be mistaken for a manual
    /// override: this coordinator's own writes to `warmthK`/`brightness`.
    private var isApplyingScheduleTick = false

    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState, calendar: @escaping () -> Calendar = { .current }, now: @escaping () -> Date = { Date() }) {
        self.appState = appState
        self.calendar = calendar
        self.now = now

        // Only `warmthK`/`brightness` count as "the user touched a slider" —
        // subscribing to `appState.objectWillChange` instead would also
        // fire for isOn/pwmSafe/fallbackMode/etc. and pause the schedule
        // over changes that have nothing to do with it.
        Publishers.Merge(
            appState.$warmthK.dropFirst().map { _ in () },
            appState.$brightness.dropFirst().map { _ in () }
        )
        .sink { [weak self] in self?.handleExternalValueChange() }
        .store(in: &cancellables)

        appState.$scheduleConfig
            .dropFirst()
            .sink { [weak self] _ in self?.handleConfigChanged() }
            .store(in: &cancellables)

        recomputePhases()
        evaluateNow()
        scheduleNextTick()
    }

    /// Computes the schedule's target for right now and writes it — unless
    /// paused by a manual override that hasn't yet crossed a phase
    /// boundary, or the mode is `.manual`, or there is nothing to write
    /// (before the schedule's first phase, or no location configured yet).
    func evaluateNow() {
        ensurePhasesAreCurrent()
        guard appState.scheduleConfig.mode != .manual else { return }

        guard let active = ScheduleEngine.activePhase(at: now(), phases: cachedPhases) else { return }
        if let pausedAt = pausedAtPhaseStart {
            guard active.start > pausedAt else { return } // still within the overridden phase
            pausedAtPhaseStart = nil // crossed into a new phase since the override — resume
        }

        guard let target = ScheduleEngine.target(at: now(), phases: cachedPhases, values: appState.values(for:)) else { return }

        isApplyingScheduleTick = true
        appState.warmthK = target.warmthK
        appState.brightness = target.brightness
        isApplyingScheduleTick = false
    }

    private func handleExternalValueChange() {
        guard !isApplyingScheduleTick else { return }
        guard appState.scheduleConfig.mode != .manual else { return }
        // Record what phase we were in *at the moment of the override* —
        // not just "paused forever." The next tick that finds we've moved
        // into a later phase than this one resumes automatically.
        pausedAtPhaseStart = ScheduleEngine.activePhase(at: now(), phases: cachedPhases)?.start
    }

    private func handleConfigChanged() {
        cachedPhasesDay = nil // force a recompute even if the calendar day hasn't rolled over
        pausedAtPhaseStart = nil // a new mode/location/bedtime invalidates any prior override
        evaluateNow()
        scheduleNextTick() // ramp status (and manual<->automatic) may have just changed
    }

    private func ensurePhasesAreCurrent() {
        let today = calendar().startOfDay(for: now())
        guard cachedPhasesDay != today else { return }
        cachedPhasesDay = today
        recomputePhases()
    }

    private func recomputePhases() {
        cachedPhases = ScheduleEngine.phases(
            coveringDayOf: now(), mode: appState.scheduleConfig.mode, config: appState.scheduleConfig, calendar: calendar()
        )
    }

    private func isCurrentlyRamping() -> Bool {
        guard let active = ScheduleEngine.activePhase(at: now(), phases: cachedPhases), active.rampMinutes > 0 else { return false }
        let rampEnd = active.start.addingTimeInterval(Double(active.rampMinutes) * 60)
        return now() < rampEnd
    }

    private func scheduleNextTick() {
        tickTimer?.invalidate()
        tickTimer = nil
        // No timer at all in Manual mode — CLAUDE.md §8's idle-CPU budget
        // shouldn't pay for a repeating wakeup nobody asked for, and Manual
        // is the default every fresh install starts in.
        guard appState.scheduleConfig.mode != .manual else { return }

        let interval: TimeInterval = isCurrentlyRamping() ? 10 : 60
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.evaluateNow()
            self.scheduleNextTick()
        }
        // 30s tolerance off a ramp (ARCHITECTURE.md §3: "keeps energy impact
        // nil"); tighter during a ramp, where CLAUDE.md's 20-minute default
        // duration means a lazy timer would visibly stair-step instead of
        // gliding.
        timer.tolerance = interval >= 60 ? 30 : 1
        // `.common`, not `.default`: a `.default`-mode timer stops firing
        // while a menu is open or a window is being dragged — exactly the
        // bug an independent C4 review found in PWMSafeCoordinator's drift
        // poll (still open as of C5, docs/QA.md). Using `.common` here from
        // the start avoids repeating that finding in a second coordinator.
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }
}
