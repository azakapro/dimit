import os

/// One `os.Logger` per subsystem area. `log show --predicate 'subsystem ==
/// "app.dimit.mac"'` finds everything; category narrows it down. Never log
/// the license key itself — CLAUDE.md §4.2 "log nothing but key-hash."
enum Log {
    static let app = Logger(subsystem: Config.bundleID, category: "app")
    static let display = Logger(subsystem: Config.bundleID, category: "display")
    static let license = Logger(subsystem: Config.bundleID, category: "license")
}
