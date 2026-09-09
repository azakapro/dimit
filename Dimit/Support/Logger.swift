import os

/// One `os.Logger` per subsystem area. `log show --predicate 'subsystem ==
/// "app.dimit.mac"'` finds everything; category narrows it down.
///
/// CLAUDE.md §4.2: log nothing that identifies anyone — failures, never
/// payloads. There is nothing sensitive to leak here by design (no account,
/// no key, no device ID, nothing in the Keychain), but the logs are read
/// back verbatim into the diagnostics bundle the user pastes into a support
/// message, so the habit is what keeps that safe as features are added.
enum Log {
    static let app = Logger(subsystem: Config.bundleID, category: "app")
    static let display = Logger(subsystem: Config.bundleID, category: "display")
}
