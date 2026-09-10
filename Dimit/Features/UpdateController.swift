import Combine
import Foundation
import Sparkle

/// The one piece of network code in the app — CLAUDE.md §1.2, §4.3 and
/// ARCHITECTURE.md §4: Sparkle's update check, **off until the user opts
/// in**, and then only a signed appcast fetched from `SUFeedURL`.
///
/// `AppState.updateChecksEnabled` (persisted since C4, default `false`) is
/// the single source of truth. This type mirrors it onto the updater and
/// nothing else; Sparkle's own "check automatically?" prompt is disabled in
/// Info.plist (`SUEnableAutomaticChecks = NO`) so the onboarding checkbox
/// is the only place the question is ever asked. Sparkle persists the
/// mirrored value under its own `SUEnableAutomaticChecks` defaults key —
/// derived state, re-written from `AppState` on every launch; `AppState`
/// wins if they ever disagree.
///
/// A manual "Check for Updates…" works regardless of the opt-in: the
/// opt-in protects against *unasked* traffic, and a user clicking a menu
/// item is asking.
@MainActor
final class UpdateController {
    private let updater: UpdaterControlling
    /// Kept alive deliberately. `SPUStandardUpdaterController` owns the
    /// updater *and* the standard user driver (the update UI); dropping it
    /// after `init` happens to work in Sparkle 2.9 only because the updater
    /// retains the driver too — a C7 review point, not something to rely on.
    private let standardController: SPUStandardUpdaterController?
    private var cancellables = Set<AnyCancellable>()

    /// Production: wraps `SPUStandardUpdaterController`, which owns the
    /// updater, the standard UI and the "Check for Updates…" user driver.
    convenience init(appState: AppState) {
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.init(appState: appState, updater: controller.updater, standardController: controller)
    }

    /// Injectable for tests — the mapping below is what needs pinning, not
    /// Sparkle itself.
    init(appState: AppState, updater: UpdaterControlling, standardController: SPUStandardUpdaterController? = nil) {
        self.updater = updater
        self.standardController = standardController
        // Synchronous on purpose: `@Published` delivers the *new* value to
        // the sink, and this sink uses that value rather than re-reading
        // `appState` — so the `willSet` trap DisplayCoordinator and
        // ScheduleCoordinator needed `.receive(on:)` for doesn't apply, and
        // the opt-in reaches Sparkle before `init` returns, i.e. before
        // Sparkle could schedule anything.
        appState.$updateChecksEnabled
            .sink { [weak self] enabled in
                self?.updater.automaticallyChecksForUpdates = enabled
            }
            .store(in: &cancellables)
    }

    /// User-initiated. Sparkle shows its own localized UI for the result
    /// (no update, an update, an error).
    func checkForUpdates() {
        updater.checkForUpdates()
    }

    /// Menu validation: Sparkle refuses concurrent checks.
    var canCheckForUpdates: Bool { updater.canCheckForUpdates }
}

/// What `UpdateController` needs from an updater, so a test can substitute a
/// fake and assert that the opt-in really is the only thing that turns
/// automatic checks on — and that nothing here ever starts a check by itself.
@MainActor
protocol UpdaterControlling: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var canCheckForUpdates: Bool { get }
    func checkForUpdates()
}

extension SPUUpdater: UpdaterControlling {}
