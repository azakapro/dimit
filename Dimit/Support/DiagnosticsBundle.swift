import Foundation
import OSLog

/// CLAUDE.md §7: "macOS version, hardware model, displays (name, builtin,
/// vendor, DDC support, brightness backend), app version, last 200 log
/// lines. Nothing that identifies the user or the machine's owner (§4.2).
/// Copied to clipboard as text, so the user can read it before sending it
/// anywhere." `buildText` is a pure function over already-fetched values so it
/// is unit-testable without touching `sysctl`/`OSLogStore`/`Bundle.main` —
/// `current()` is the thin, untested glue that gathers those and calls it,
/// same split as `Renderer.render` vs. the controllers that call it.
enum DiagnosticsBundle {
    struct DisplayEntry: Equatable {
        var name: String
        var isBuiltin: Bool
        var isAppleDisplay: Bool
        var supportsDDC: Bool
        /// The backend's `name` if one can control this display, `nil`
        /// otherwise — CLAUDE.md's own wording, "brightness backend," is
        /// naturally optional (some displays genuinely have none).
        var brightnessBackend: String?
    }

    static func buildText(
        appVersion: String,
        macOSVersion: String,
        hardwareModel: String,
        displays: [DisplayEntry],
        recentLogLines: [String]
    ) -> String {
        var lines: [String] = [
            "Dimit diagnostics",
            "App version: \(appVersion)",
            "macOS: \(macOSVersion)",
            "Hardware: \(hardwareModel)",
            "",
            "Displays (\(displays.count)):",
        ]

        if displays.isEmpty {
            lines.append("  (none enumerated)")
        }
        for (index, display) in displays.enumerated() {
            var tags: [String] = []
            if display.isBuiltin { tags.append("built-in") }
            if display.isAppleDisplay { tags.append("Apple display") }
            // Deliberately no "DDC" tag from `supportsDDC`: it is always
            // false (see DisplayManager), so emitting it would have told
            // every beta tester's support bundle that DDC is unsupported
            // on a monitor DDC might actively be driving. The backend line
            // below reports "DDC/CI" when it really is, which is the same
            // fact, truthfully.
            let tagSuffix = tags.isEmpty ? "" : " [\(tags.joined(separator: ", "))]"
            let backend = display.brightnessBackend ?? "none"
            lines.append("  \(index + 1). \(display.name)\(tagSuffix) — brightness backend: \(backend)")
        }

        // An earlier draft of CLAUDE.md §7 asked for a "license state"
        // line here. There is no licensing and there never will be — the
        // 2026-09-09 distribution decision (§4) made every copy
        // unconditional — so there is no state to report, and inventing a
        // placeholder like "Unlicensed" would describe product behavior
        // that doesn't exist. Deliberately absent, and
        // `DiagnosticsBundleTests` pins that it stays absent.

        lines.append("")
        lines.append("Log (last \(recentLogLines.count) lines):")
        lines.append(contentsOf: recentLogLines)

        return lines.joined(separator: "\n")
    }

    @MainActor
    static func current(displayManager: DisplayManager, pwmSafeCoordinator: PWMSafeCoordinator) -> String {
        let displayEntries = displayManager.displays.map { display in
            DisplayEntry(
                name: display.name,
                isBuiltin: display.isBuiltin,
                isAppleDisplay: display.isAppleDisplay,
                supportsDDC: display.supportsDDC,
                brightnessBackend: pwmSafeCoordinator.backendName(for: display)
            )
        }
        return buildText(
            appVersion: appVersionString(),
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            hardwareModel: hardwareModelIdentifier(),
            displays: displayEntries,
            recentLogLines: recentLogLines()
        )
    }

    private static func appVersionString() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private static func hardwareModelIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "?" }
        var buffer = [CChar](repeating: 0, count: size)
        let result = sysctlbyname("hw.model", &buffer, &size, nil, 0)
        guard result == 0 else { return "?" }
        return String(cString: buffer)
    }

    /// `OSLogStore(scope: .currentProcessIdentifier)` needs no special
    /// entitlement (unlike `.system`, which requires elevated privileges
    /// this non-sandboxed but otherwise ordinary app doesn't have) — it
    /// only reads this process's own log entries, which is exactly "our
    /// last 200 lines," not the whole system's.
    private static func recentLogLines(limit: Int = 200) -> [String] {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            // A generous window (this session's entire run could be days
            // long for a menu-bar app) — filtered to our own subsystem and
            // capped to `limit` right after, so an idle app that has logged
            // very little still shows its true history rather than an
            // artificially narrow recent slice.
            let position = store.position(date: .distantPast)
            let entries = try store.getEntries(at: position)
                .compactMap { $0 as? OSLogEntryLog }
                .filter { $0.subsystem == Config.bundleID }
            return entries.suffix(limit).map { entry in
                let time = entry.date.formatted(date: .omitted, time: .standard)
                return "\(time) [\(entry.category)] \(entry.composedMessage)"
            }
        } catch {
            // Never let a diagnostics *tool* itself be the thing that
            // fails silently — but also don't throw out of `current()`
            // over it: a diagnostics bundle missing its log section is far
            // more useful to support than no diagnostics bundle at all.
            Log.app.error("DiagnosticsBundle: couldn't read log entries: \(error, privacy: .public)")
            return ["(could not read log entries: \(error.localizedDescription))"]
        }
    }
}
