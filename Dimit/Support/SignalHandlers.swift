import CoreGraphics
import Darwin

/// CLAUDE.md §3.3: "restore ... from an atexit/signal handler for crashes
/// (SIGTERM/SIGINT; do not try to handle SIGSEGV elaborately)." `signal()`
/// handlers can't capture context — `CGDisplayRestoreColorSyncSettings()`
/// takes no arguments, so none is needed. Same pattern already proven in
/// `scripts/gamma_spike.swift` during C0.
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
