import AppKit
import SwiftUI

/// Shows `OnboardingView` once, on first launch, and records completion
/// in `Persistence.hasCompletedOnboarding` so it never shows again —
/// ARCHITECTURE.md §10 "first launch only."
///
/// Completion is recorded on *either* "Get Started" or the window's own
/// close button. Closing without finishing is a valid way to dismiss a
/// one-time intro; showing it again next launch to a user who already
/// closed it once would just be nagging.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let persistence: Persistence
    private let appState: AppState
    private let restoreColours: () -> Void

    init(appState: AppState, persistence: Persistence = .shared, restoreColours: @escaping () -> Void) {
        self.appState = appState
        self.persistence = persistence
        self.restoreColours = restoreColours
    }

    /// No-op after the first completed run.
    func showIfNeeded() {
        guard !persistence.hasCompletedOnboarding else { return }
        show()
    }

    private func show() {
        let hosting = NSHostingController(
            rootView: OnboardingView(
                appState: appState,
                restoreColours: restoreColours,
                finish: { [weak self] in self?.finish() }
            )
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = appState.localized("app.name")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window

        // Size from the SwiftUI content *before* centering. `center()` on a
        // window still at NSWindow's placeholder size put the intro near the
        // top of the screen (observed at y=33 on first launch) — and moving
        // `center()` after `makeKeyAndOrderFront` didn't help, because the
        // hosting controller resizes the window asynchronously either way.
        window.setContentSize(hosting.view.fittingSize)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        persistence.hasCompletedOnboarding = true
        window?.close()
        window = nil
    }

    /// Only a *user-initiated* close (the title-bar button) counts as
    /// dismissing onboarding. `windowShouldClose` is the one delegate
    /// callback AppKit sends for that gesture alone — `windowWillClose`
    /// also fires when the app terminates, and recording completion there
    /// meant quitting (or being SIGTERM'd) during the intro marked it done
    /// without the user ever seeing past step 1. Found by an integration
    /// probe on first launch, not by review.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        persistence.hasCompletedOnboarding = true
        return true
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
