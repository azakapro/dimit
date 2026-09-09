import ServiceManagement

/// CLAUDE.md §3.9: "Launch at login via SMAppService.mainApp (macOS 13+)."
/// `SMAppService.mainApp` is itself already the single source of truth for
/// this setting (backed by `launchd`, survives reboot, visible in System
/// Settings → General → Login Items) — there is nothing to persist in
/// `PersistedState`, and duplicating its answer there would just create a
/// second value that could disagree with the real one. This wraps it only
/// to give Settings' toggle one small testable surface instead of calling
/// the framework type directly from SwiftUI.
///
/// No new permission prompt (CLAUDE.md §8): registering the *main app
/// itself* as its own login item needs no entitlement and shows no
/// authorization dialog — that's specific to `SMAppService.mainApp`, unlike
/// the daemon/agent-plist APIs it replaces.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Throws so the caller (Settings' toggle) can show the real reason a
    /// registration failed rather than silently leaving the toggle in the
    /// wrong state — CLAUDE.md §12's "graceful path" habit, applied to a
    /// system API instead of a private one this time.
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
