import AppKit

// NSApplicationDelegate callbacks all run on the main thread in practice;
// marking the class @MainActor makes that explicit to the compiler so the
// stored-property initializer below (which constructs a @MainActor
// AppState) type-checks without a workaround.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt-and-suspenders with Info.plist's LSUIElement: guarantees no
        // Dock icon / Cmd-Tab entry even if something about the bundle's
        // Info.plist processing goes sideways in a particular build config.
        NSApp.setActivationPolicy(.accessory)
        menuBarController = MenuBarController(appState: appState)
        Log.app.info("Dimit launched, version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?", privacy: .public)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Persistence is debounced 250 ms, so without this any change made
        // just before quitting is lost — flip a preset, hit Quit, and it's
        // gone. Flush synchronously here.
        appState.flush()

        // C2 adds the gamma restore call here. Nothing touches the display
        // yet in C1, so there is nothing to restore.
    }
}
