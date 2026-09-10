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
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // `SMAppService`'s errors reach the user as bare POSIX strings —
            // the owner hit "The operation couldn't be completed. Invalid
            // argument", which says nothing about what to do. The domain and
            // code are what actually identify the cause, and they were
            // nowhere: not in the UI, not in the log, so not in a diagnostics
            // bundle either. Logged before rethrowing so the next occurrence
            // is diagnosable from `settings.copy_diag` instead of guesswork.
            let ns = error as NSError
            Log.app.error("""
                LaunchAtLogin.setEnabled(\(enabled, privacy: .public)) failed: \
                \(ns.domain, privacy: .public) \(ns.code, privacy: .public) \
                \(ns.localizedDescription, privacy: .public) \
                bundle=\(Bundle.main.bundlePath, privacy: .public) \
                status=\(SMAppService.mainApp.status.rawValue, privacy: .public)
                """)
            throw error
        }
    }

    /// Why a registration failure is *likely*, for the message shown to the
    /// user. `SMAppService` does not tell us, so this is an informed guess
    /// keyed on the one condition that is both common and checkable: macOS
    /// will not register a login item for an app it considers to be running
    /// from a temporary or untrusted place — most often because the user is
    /// running Dimit straight from the disk image or the Downloads folder
    /// instead of having moved it to Applications.
    ///
    /// Deliberately not phrased as a certainty: a probe on the dev machine
    /// registered a login item successfully from `/tmp`, so location alone
    /// does not always break it, and claiming a cause we have not proven
    /// would send someone down the wrong path.
    static var isInApplicationsFolder: Bool {
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }
}
