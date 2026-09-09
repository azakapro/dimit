import AppKit

/// The display pipeline's four pieces are constructed together, live for
/// the app's entire run, and are torn down together — one struct instead
/// of four independent optionals (code review: four separate `Optional`
/// stored properties invited a future partial-teardown bug, e.g. resetting
/// `menuBarController` alone without the other three, leaving nothing that
/// actually represents "is the pipeline up").
private struct DisplayPipeline {
    let displayManager: DisplayManager
    let gammaController: GammaController
    let displayCoordinator: DisplayCoordinator
    let menuBarController: MenuBarController
}

// NSApplicationDelegate callbacks all run on the main thread in practice;
// marking the class @MainActor makes that explicit to the compiler so the
// stored-property initializer below (which constructs a @MainActor
// AppState) type-checks without a workaround.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var pipeline: DisplayPipeline?

    func applicationDidFinishLaunching(_ notification: Notification) {
        SignalHandlers.install()

        // "On launch before anything else" (CLAUDE.md §3.3 and
        // docs/PLAN.md's C2 scope) — a previous crash isn't caught (SIGSEGV
        // is deliberately not handled), so WindowServer may still be
        // showing a stale tint from before this launch. This must run
        // before DisplayCoordinator exists: its first `reapply()` reads
        // "the current gamma table" as the restore baseline the moment
        // it's created, and if that read happened before this restore, a
        // leftover tint would be captured as if it were neutral — then
        // every further warmth/dim multiplier would compound on top of it.
        //
        // Routed through GammaController rather than calling
        // CGDisplayRestoreColorSyncSettings() directly here (an earlier
        // version did that — code review pointed out AppDelegate had no
        // need to import CoreGraphics at all: constructing GammaController
        // first costs nothing, since its init doesn't touch a display
        // itself, and it keeps every restore call going through the one
        // method that owns that responsibility).
        let gammaController = GammaController()
        gammaController.restoreAll()

        NSApp.setActivationPolicy(.accessory)

        let displayManager = DisplayManager()
        let coordinator = DisplayCoordinator(appState: appState, displayManager: displayManager, gammaController: gammaController)
        let menuBarController = MenuBarController(appState: appState) { [weak coordinator] in
            coordinator?.restoreColours()
        }
        pipeline = DisplayPipeline(
            displayManager: displayManager,
            gammaController: gammaController,
            displayCoordinator: coordinator,
            menuBarController: menuBarController
        )

        Log.app.info("Dimit launched, version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?", privacy: .public)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Persistence is debounced 250 ms, so without this any change made
        // just before quitting is lost — flip a preset, hit Quit, and it's
        // gone. Flush synchronously here.
        appState.flush()

        // CLAUDE.md §3.3: restore on quit. Belt-and-suspenders with
        // DisplayCoordinator's own reaction to isOn (there is none pending
        // here — quitting doesn't change isOn — so this direct call is
        // what actually restores the screen on a normal Cmd-Q).
        pipeline?.gammaController.restoreAll()
    }
}
