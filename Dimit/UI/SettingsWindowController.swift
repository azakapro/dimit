import AppKit
import SwiftUI

/// Hosts `SettingsView` in a real `NSWindow`.
///
/// Deliberately *not* SwiftUI's `Settings {}` scene: the standard way to
/// open that programmatically is `@Environment(\.openSettings)`, which is
/// macOS 14+, and CLAUDE.md §2 fixes the deployment target at macOS 13.
/// The pre-14 alternative is sending an undocumented
/// `showSettingsWindow:`/`showPreferencesWindow:` selector to `NSApp`,
/// whose name Apple actually changed between macOS versions — exactly the
/// kind of thing that silently stops working on an OS we can't test. A
/// window we own has none of that risk and behaves identically to the
/// user.
///
/// Reuses one window across opens rather than creating a new one each time,
/// so reopening Settings returns to the tab the user was last on.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    private let appState: AppState
    private let displayManager: DisplayManager
    private let pwmSafeCoordinator: PWMSafeCoordinator
    private let restoreColours: () -> Void

    init(
        appState: AppState,
        displayManager: DisplayManager,
        pwmSafeCoordinator: PWMSafeCoordinator,
        restoreColours: @escaping () -> Void
    ) {
        self.appState = appState
        self.displayManager = displayManager
        self.pwmSafeCoordinator = pwmSafeCoordinator
        self.restoreColours = restoreColours
    }

    func show() {
        if window == nil {
            window = makeWindow()
        }
        // An LSUIElement app isn't automatically brought forward when it
        // opens a window — without this the Settings window can appear
        // behind whatever the user was just using.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(
            rootView: SettingsView(
                appState: appState,
                displayManager: displayManager,
                pwmSafeCoordinator: pwmSafeCoordinator,
                restoreColours: restoreColours
            )
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = appState.localized("settings.title")
        window.styleMask = [.titled, .closable, .miniaturizable]
        // `.isReleasedWhenClosed` defaults to true for NSWindow created
        // this way; leaving it on would free the window on close while
        // this controller still holds a reference to it — a use-after-free
        // the second time the user opens Settings.
        window.isReleasedWhenClosed = false
        // Size before centering — see OnboardingWindowController for why
        // centering an unsized window lands it at the top of the screen.
        // Only on creation: reopening keeps wherever the user dragged it.
        window.setContentSize(hosting.view.fittingSize)
        window.center()
        return window
    }
}
