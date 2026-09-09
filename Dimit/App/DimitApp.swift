import SwiftUI

@main
struct DimitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No visible window on launch — this is a menu-bar-only app
        // (LSUIElement in Info.plist). An empty Settings scene is the
        // standard way to give SwiftUI's App protocol something to host
        // without opening a window; AppDelegate creates the real UI
        // (status item + popover) in applicationDidFinishLaunching.
        Settings {
            EmptyView()
        }
    }
}
