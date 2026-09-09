import CoreGraphics

/// Pure diff between two `[DisplayCommand]` snapshots — ARCHITECTURE.md
/// §2.1: "Applier diffs the new command list against the last applied one
/// and calls controllers only for changed fields." That's what keeps idle
/// CPU near zero: dragging a slider fires `render()` often, but this diff
/// only reports real work when the *gamma* actually changed, not on every
/// call (e.g. dragging brightness below the dim floor changes
/// `overlayAlpha` on every tick while `gamma.dim` stays pinned at the
/// floor — C2 has no overlay yet, so that must not cost a
/// `CGSetDisplayTransferByTable` call every tick).
enum Applier {
    struct Diff: Equatable {
        /// Displays whose gamma actually changed (new, changed, or turned
        /// on) and need a real `CGSetDisplayTransferByTable` call.
        var toApply: [DisplayCommand] = []
        /// Displays that had gamma applied and now don't (turned off).
        /// `CGDisplayRestoreColorSyncSettings()` is global — it restores
        /// every display in one call — so the caller only needs to know
        /// *whether* to call it, not iterate this list; it's kept as a
        /// list anyway so tests can assert exactly which display(s)
        /// triggered the restore.
        var toRestore: [CGDirectDisplayID] = []
    }

    static func diff(previous: [DisplayCommand], current: [DisplayCommand]) -> Diff {
        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.displayID, $0) })
        var result = Diff()

        for command in current {
            switch (previousByID[command.displayID]?.gamma, command.gamma) {
            case (nil, nil):
                continue // never touched, still off
            case (.some, nil):
                result.toRestore.append(command.displayID)
            case (nil, .some):
                result.toApply.append(command) // newly on, or newly connected while on
            case let (.some(old), .some(new)) where old != new:
                result.toApply.append(command) // warmth/dim actually changed
            case (.some, .some):
                continue // gamma unchanged — e.g. only overlayAlpha moved
            }
        }
        return result
    }
}
