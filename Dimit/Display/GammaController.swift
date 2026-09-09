import CoreGraphics

/// Owns the actual `CGSetDisplayTransferByTable` calls and the baseline
/// cache. Every private/low-level call in this file is named in a comment
/// with its exact symbol, per CLAUDE.md §12 — though gamma is public
/// CoreGraphics API, not a private framework; that discipline starts
/// mattering for real in C3's `BrightnessController`.
@MainActor
final class GammaController {
    /// Keyed by display **UUID**, not `CGDirectDisplayID` — ARCHITECTURE.md
    /// §2.4: IDs change across reconnects, but more importantly, a baseline
    /// must be captured exactly once per physical display and never
    /// re-read afterward. If a display disconnects and reconnects while
    /// tinted, re-reading `CGGetDisplayTransferByTable` at that point would
    /// capture the *tinted* table as if it were neutral, baking the tint in
    /// permanently. The cache is memory-only by design (ARCHITECTURE.md
    /// §2.8: "Gamma baselines: memory only, never persisted — stale
    /// baselines would bake a tint in").
    private var baselines: [String: GammaMath.Table] = [:]

    /// Diagnostics-only counter: how many times a read-back after `apply`
    /// didn't match what was just set. A match proves nothing on macOS 26+
    /// (Apple bugs FB19136488, FB22273730 — the table can be stored while
    /// the panel ignores it), but a *mismatch* is still worth counting;
    /// C3's diagnostics bundle surfaces this.
    private(set) var gammaMismatchCount = 0

    /// Applies `command.gamma` to `command.displayID`. Returns whether it
    /// actually took effect (`false` if there's no gamma to apply, no
    /// baseline could be captured, or the CoreGraphics call itself failed
    /// — each case also logged). The return value matters: code review
    /// caught `DisplayCoordinator` originally recording every attempted
    /// command into `lastApplied` regardless of outcome, which meant a
    /// failed apply was never retried — `Applier.diff` would see the next
    /// identical `render()` output as "unchanged" and skip it forever,
    /// even though the display never actually got the tint.
    @discardableResult
    func apply(_ command: DisplayCommand, uuid: String) -> Bool {
        guard let gamma = command.gamma else { return false }
        guard let baseline = baseline(for: command.displayID, uuid: uuid) else {
            Log.display.error("no gamma baseline for display \(command.displayID, privacy: .public); skipping apply")
            return false
        }

        let table = GammaMath.apply(baseline: baseline, multiplier: gamma.multiplier, dim: gamma.dim)
        let result = set(table, on: command.displayID)
        guard result == .success else {
            Log.display.error("CGSetDisplayTransferByTable failed (\(result.rawValue, privacy: .public)) for display \(command.displayID, privacy: .public)")
            return false
        }
        verifyReadBack(table, on: command.displayID)
        return true
    }

    /// CLAUDE.md §3.3: restore on OFF, on quit, from the signal handlers,
    /// and on launch before anything else. `CGDisplayRestoreColorSyncSettings()`
    /// resets every display's gamma to the user's ColorSync profile in one
    /// global call; there is no per-display restore API, so callers never
    /// need to loop over displays to restore them.
    ///
    /// Not the *only* place this exact CoreGraphics call appears —
    /// `Dimit/Support/SignalHandlers.swift`'s `SIGTERM`/`SIGINT` handlers
    /// call it directly too, because a `@convention(c)` signal handler
    /// can't safely call into a `@MainActor` Swift object (actor hops and
    /// ARC aren't async-signal-safe). That duplication is real and
    /// deliberate, not an oversight; a change to this method's behavior
    /// (e.g. adding a "restores performed" diagnostics counter, matching
    /// `gammaMismatchCount` below) needs the same change made there too.
    func restoreAll() {
        CGDisplayRestoreColorSyncSettings()
    }

    /// Drops every cached baseline whose UUID isn't in `currentUUIDs`
    /// (ARCHITECTURE.md §2.2: "drop cached baselines for gone displays").
    /// Without this the cache would grow forever across plug/unplug
    /// cycles, and — the real reason it matters — if a display ever reused
    /// a UUID (not something CoreGraphics is documented to do, but not a
    /// guarantee either), a stale baseline could be silently reapplied to
    /// a different physical panel. Takes the full current set rather than
    /// one UUID at a time so the cache is the single source of truth for
    /// "what have we touched" — code review on C1 caught `DisplayCoordinator`
    /// keeping its own shadow `Set<String>` of known UUIDs purely to compute
    /// this, a second copy of state this cache already owns.
    func evictBaselines(keepingOnly currentUUIDs: Set<String>) {
        // Collect stale keys before removing: mutating a Dictionary while
        // iterating its own `.keys` view is unsafe.
        let staleUUIDs = baselines.keys.filter { !currentUUIDs.contains($0) }
        for uuid in staleUUIDs {
            baselines.removeValue(forKey: uuid)
        }
    }

    // MARK: - CoreGraphics calls, isolated here

    private func baseline(for displayID: CGDirectDisplayID, uuid: String) -> GammaMath.Table? {
        if let cached = baselines[uuid] { return cached }

        let capacity = CGDisplayGammaTableCapacity(displayID)
        guard capacity > 0 else {
            Log.display.error("CGDisplayGammaTableCapacity returned 0 for display \(displayID, privacy: .public)")
            return nil
        }

        var red = [CGGammaValue](repeating: 0, count: Int(capacity))
        var green = red
        var blue = red
        var sampleCount: UInt32 = 0
        let err = CGGetDisplayTransferByTable(displayID, capacity, &red, &green, &blue, &sampleCount)
        guard err == .success, sampleCount > 0 else {
            Log.display.error("CGGetDisplayTransferByTable failed (\(err.rawValue, privacy: .public)) for display \(displayID, privacy: .public)")
            return nil
        }

        let table = GammaMath.Table(
            red: Array(red.prefix(Int(sampleCount))),
            green: Array(green.prefix(Int(sampleCount))),
            blue: Array(blue.prefix(Int(sampleCount)))
        )
        baselines[uuid] = table
        return table
    }

    private func set(_ table: GammaMath.Table, on displayID: CGDirectDisplayID) -> CGError {
        table.red.withUnsafeBufferPointer { r in
            table.green.withUnsafeBufferPointer { g in
                table.blue.withUnsafeBufferPointer { b in
                    CGSetDisplayTransferByTable(displayID, UInt32(table.red.count), r.baseAddress, g.baseAddress, b.baseAddress)
                }
            }
        }
    }

    private func verifyReadBack(_ expected: GammaMath.Table, on displayID: CGDirectDisplayID) {
        var red = [CGGammaValue](repeating: 0, count: expected.red.count)
        var green = red
        var blue = red
        var sampleCount: UInt32 = 0
        let err = CGGetDisplayTransferByTable(displayID, UInt32(expected.red.count), &red, &green, &blue, &sampleCount)
        guard err == .success else { return } // can't verify; not itself an error worth counting

        // Code review caught this only ever comparing the red channel.
        // Real bug: 0K's whole point is zeroing green/blue while leaving
        // red alone, so a failure mode that corrupts exactly those two
        // channels — the literal "table stored, channel not applied" shape
        // of the Tahoe-era bugs this counter exists to catch — would have
        // reported "verified" every time.
        let tolerance: Float = 0.001
        func channelMatches(_ actual: [CGGammaValue], _ expected: [CGGammaValue]) -> Bool {
            zip(actual, expected).allSatisfy { abs($0 - $1) < tolerance }
        }
        let matches = channelMatches(red, expected.red)
            && channelMatches(green, expected.green)
            && channelMatches(blue, expected.blue)
        guard !matches else { return }

        gammaMismatchCount += 1
        Log.display.warning("gamma read-back mismatch for display \(displayID, privacy: .public) (count: \(self.gammaMismatchCount, privacy: .public)) — known macOS 26 class of bug, not necessarily ours")
    }
}
