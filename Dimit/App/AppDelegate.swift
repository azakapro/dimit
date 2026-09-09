import AppKit
import CoreGraphics

// NSApplicationDelegate callbacks all run on the main thread in practice;
// marking the class @MainActor makes that explicit to the compiler so the
// stored-property initializer below (which constructs a @MainActor
// AppState) type-checks without a workaround.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var displayManager: DisplayManager?
    private var gammaController: GammaController?
    private var displayCoordinator: DisplayCoordinator?
    private var menuBarController: MenuBarController?

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
        CGDisplayRestoreColorSyncSettings()

        NSApp.setActivationPolicy(.accessory)

        let displayManager = DisplayManager()
        let gammaController = GammaController()
        self.displayManager = displayManager
        self.gammaController = gammaController
        let coordinator = DisplayCoordinator(appState: appState, displayManager: displayManager, gammaController: gammaController)
        displayCoordinator = coordinator

        menuBarController = MenuBarController(appState: appState) { [weak coordinator] in
            coordinator?.restoreColours()
        }

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
        gammaController?.restoreAll()
    }
}
