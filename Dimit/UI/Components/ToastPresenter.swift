import AppKit
import SwiftUI

/// A brief, permission-free on-screen message near the status item —
/// CLAUDE.md §3.6: "show 'PWM-Safe re-pinned brightness to 100%...' once
/// per session." `UNUserNotificationCenter` would need an authorization
/// prompt, which CLAUDE.md §1.2/§1.5's "never require unnecessary
/// permissions" spirit argues against for something this minor and rare
/// (once per session, at most). A small borderless window that
/// auto-dismisses needs nothing from the user at all.
@MainActor
enum ToastPresenter {
    private struct ToastView: View {
        let text: String
        var body: some View {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: 280)
                .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    /// Kept alive as a static so the window doesn't get deallocated the
    /// instant this function returns; replacing it (rather than stacking
    /// multiple) is fine since CLAUDE.md's own trigger is "once per
    /// session" — there is never a reason to show two at once.
    private static var currentWindow: NSWindow?

    static func show(_ text: LocalizedStringResource, near button: NSStatusBarButton?) {
        let hosting = NSHostingController(rootView: ToastView(text: String(localized: text)))
        let size = hosting.view.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentViewController = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .statusBar
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]

        if let buttonWindow = button?.window {
            let buttonFrameInScreen = buttonWindow.convertToScreen(button?.convert(button!.bounds, to: nil) ?? .zero)
            let origin = NSPoint(
                x: buttonFrameInScreen.midX - size.width / 2,
                y: buttonFrameInScreen.minY - size.height - 8
            )
            window.setFrameOrigin(origin)
        } else if let screen = NSScreen.main {
            window.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height - 40))
        }

        currentWindow = window
        window.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            window.orderOut(nil)
            if currentWindow === window { currentWindow = nil }
        }
    }
}
