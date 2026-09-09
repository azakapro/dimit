import AppKit
import CoreGraphics
import ColorSync

/// Owns real display enumeration and the two lifecycle events that force
/// a re-apply: reconfiguration (plug/unplug/resolution change) and wake
/// from sleep — ARCHITECTURE.md §2.2.
@MainActor
final class DisplayManager: ObservableObject {
    @Published private(set) var displays: [DisplayInfo] = []

    private var reconfigureWorkItem: DispatchWorkItem?
    private var wakeReapplyWorkItem: DispatchWorkItem?
    private var wakeObservers: [NSObjectProtocol] = []

    init() {
        refresh()

        let err = CGDisplayRegisterReconfigurationCallback(dimitDisplayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
        if err != .success {
            Log.display.error("CGDisplayRegisterReconfigurationCallback failed: \(err.rawValue, privacy: .public)")
        }
        observeWake()
    }

    deinit {
        // Must pass the *same* userInfo pointer used at registration —
        // caught this while writing it: CGDisplayRemoveReconfigurationCallback
        // isn't documented as matching by callback pointer alone, and
        // passing `nil` here risks leaving the real registration (keyed to
        // this instance's now-freed address) dangling, which would be a
        // use-after-free the next time any display reconfigures.
        // `passUnretained` only reads `self`'s address, which is still
        // valid for that during `deinit`.
        CGDisplayRemoveReconfigurationCallback(dimitDisplayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
        // AppDelegate holds this for the app's entire lifetime in practice,
        // so this mostly documents intent and matters for tests that
        // construct/discard a DisplayManager.
        let center = NSWorkspace.shared.notificationCenter
        for token in wakeObservers { center.removeObserver(token) }
    }

    // MARK: - Reconfiguration (called from the C callback below)

    fileprivate func handleReconfiguration(flags: CGDisplayChangeSummaryFlags) {
        // The header docs: this callback runs once *before* reconfiguration
        // (per online display, flag = kCGDisplayBeginConfigurationFlag) and
        // once *after* (flags describe what changed). Only the "after" call
        // has a state worth re-enumerating from.
        guard !flags.contains(.beginConfigurationFlag) else { return }

        // A single physical event (unplug, replug, resolution change) fires
        // this callback once per affected display, so coalesce a burst of
        // calls into one re-enumeration — ARCHITECTURE.md §2.2: "300 ms
        // debounce."
        reconfigureWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.refresh() }
        reconfigureWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    // MARK: - Wake

    private func observeWake() {
        let center = NSWorkspace.shared.notificationCenter
        // Both: full-system wake (NSWorkspace.didWakeNotification) and the
        // display-only case, e.g. displays sleeping on their own timer
        // while the Mac itself stays awake (NSWorkspace.screensDidWakeNotification).
        // CLAUDE.md §3.1: "WindowServer resets gamma on wake — Tap Zap
        // documents this exact bug."
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // `queue: .main` guarantees this runs on the main thread,
                // but the compiler can't derive main-actor isolation from
                // an OperationQueue argument — assumeIsolated documents
                // the guarantee explicitly instead of leaving a warning
                // that (with strict-concurrency at "minimal") would
                // otherwise be silently ignorable forever.
                MainActor.assumeIsolated {
                    self?.scheduleWakeReapply()
                }
            }
            wakeObservers.append(token)
        }
    }

    private func scheduleWakeReapply() {
        wakeReapplyWorkItem?.cancel()
        // ARCHITECTURE.md §2.2: "re-apply after 1.0 s." WindowServer needs
        // a moment after a wake notification before display state is
        // actually settled; re-enumerating immediately risks reading
        // transiently wrong values.
        let item = DispatchWorkItem { [weak self] in self?.refresh() }
        wakeReapplyWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    // MARK: - Enumeration

    private func refresh() {
        var count: UInt32 = 0
        let sizeErr = CGGetActiveDisplayList(0, nil, &count)
        guard sizeErr == .success, count > 0 else {
            if sizeErr != .success {
                Log.display.error("CGGetActiveDisplayList (size query) failed: \(sizeErr.rawValue, privacy: .public)")
            }
            displays = []
            return
        }

        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        let err = CGGetActiveDisplayList(count, &ids, &count)
        guard err == .success else {
            Log.display.error("CGGetActiveDisplayList failed: \(err.rawValue, privacy: .public)")
            return
        }

        displays = ids.prefix(Int(count)).map(Self.info)
    }

    private static func info(for id: CGDirectDisplayID) -> DisplayInfo {
        DisplayInfo(
            id: id,
            uuid: uuidString(for: id),
            name: localizedName(for: id) ?? "Display \(id)",
            isBuiltin: CGDisplayIsBuiltin(id) != 0,
            // CLAUDE.md §3.1: "isAppleDisplay (vendor 0x610 via
            // IOKit/CGDisplayVendorNumber)" — confirmed 0x610 on this
            // machine's built-in panel (docs/QA.md).
            isAppleDisplay: CGDisplayVendorNumber(id) == 0x610,
            supportsDDC: false // C5
        )
    }

    /// `CGDisplayCreateUUIDFromDisplayID` lives in ColorSync.framework, not
    /// CoreGraphics (verified against the SDK headers — its declaration is
    /// in ColorSyncDevice.h). It's vanishingly unlikely to fail for a real
    /// connected display; the fallback keeps a stable-for-this-boot string
    /// instead of crashing.
    private static func uuidString(for id: CGDirectDisplayID) -> String {
        guard let ref = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else {
            return "unknown-\(id)"
        }
        return CFUUIDCreateString(nil, ref) as String
    }

    /// `CGDirectDisplayID` has no direct "get the human name" API; the name
    /// lives on `NSScreen`, matched via the `NSScreenNumber` device
    /// description key (verified against a live probe: this key's value
    /// equals the display's `CGDirectDisplayID`).
    private static func localizedName(for id: CGDirectDisplayID) -> String? {
        NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }?.localizedName
    }
}

/// A `@convention(c)` function can't capture context, so `userInfo` carries
/// the `DisplayManager` instance across the C boundary (the standard
/// pattern for this API — CGDisplayRegisterReconfigurationCallback's own
/// docs describe `userInfo` as existing for exactly this).
private func dimitDisplayReconfigurationCallback(
    _ display: CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _ userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo else { return }
    let manager = Unmanaged<DisplayManager>.fromOpaque(userInfo).takeUnretainedValue()
    // The header docs: this callback runs "on the event processing
    // thread," which for a standard AppKit run loop is the main thread.
    // assumeIsolated documents that assumption rather than silently
    // hoping it holds.
    MainActor.assumeIsolated {
        manager.handleReconfiguration(flags: flags)
    }
}
