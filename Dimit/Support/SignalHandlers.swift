import CoreGraphics
import Darwin

/// CLAUDE.md §3.3: "restore ... from an atexit/signal handler for crashes
/// (SIGTERM/SIGINT; do not try to handle SIGSEGV elaborately)." `signal()`
/// handlers can't capture context — `CGDisplayRestoreColorSyncSettings()`
/// takes no arguments, so none is needed. Same pattern already proven in
/// `scripts/gamma_spike.swift` during C0.
///
/// Known, accepted tradeoff (flagged in code review, not silently missed):
/// `CGDisplayRestoreColorSyncSettings()` and `exit()` are not on the strict
/// async-signal-safe allowlist (they can allocate and take locks), so in
/// principle a signal arriving while the interrupted thread already holds
/// one of those same locks could deadlock instead of restoring. A fully
/// safe version would only flip an atomic flag here and do the real work
/// on the main run loop via a self-pipe — meaningfully more machinery than
/// CLAUDE.md asks for ("do not try to handle SIGSEGV elaborately" reads as
/// the same "keep this simple" spirit for its sibling signals), and this
/// exact pattern is what the spec's own §2.2 literally specifies
/// ("SIGTERM/SIGINT → ... CGDisplayRestoreColorSyncSettings() then exit").
/// Kept as specified; revisit only if it's ever observed to actually hang.
enum SignalHandlers {
    static func install() {
        signal(SIGTERM) { _ in
            CGDisplayRestoreColorSyncSettings()
            exit(0)
        }
        signal(SIGINT) { _ in
            CGDisplayRestoreColorSyncSettings()
            exit(0)
        }
    }
}
