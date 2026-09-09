import CoreGraphics
import Darwin
import IOKit

/// Every private/semi-private brightness API lives in this one file,
/// behind the `BrightnessBackend` protocol, each with a graceful
/// `.unsupported` path — CLAUDE.md §12. Every symbol name and framework
/// path is verified against this machine (M1 Pro, macOS 27.0 beta) before
/// being trusted; see each backend's comment for what was actually
/// observed, not just what the spec expected.

/// Primary backend for Apple displays — CLAUDE.md §3.4. Loads
/// `/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices`
/// via `dlopen`/`dlsym` for `DisplayServicesGetBrightness`/`SetBrightness`.
/// Verified directly on this machine before writing any of the rest of
/// this cycle: dlopen succeeds (the framework lives in the dyld shared
/// cache, not as a standalone file — `file` on the on-disk path reports
/// "No such file or directory", which is expected and not a failure),
/// both symbols resolve, get/set/read-back all behave exactly as CLAUDE.md
/// describes, and a value set to 1.0 reads back as exactly 1.0.
final class DisplayServicesBackend: BrightnessBackend {
    let name = "DisplayServices"

    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private let getFn: GetFn?
    private let setFn: SetFn?

    init() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW) else {
            Log.display.error("dlopen DisplayServices failed: \(String(cString: dlerror()), privacy: .public)")
            getFn = nil
            setFn = nil
            return
        }
        if let sym = dlsym(handle, "DisplayServicesGetBrightness") {
            getFn = unsafeBitCast(sym, to: GetFn.self)
        } else {
            Log.display.error("dlsym DisplayServicesGetBrightness failed")
            getFn = nil
        }
        if let sym = dlsym(handle, "DisplayServicesSetBrightness") {
            setFn = unsafeBitCast(sym, to: SetFn.self)
        } else {
            Log.display.error("dlsym DisplayServicesSetBrightness failed")
            setFn = nil
        }
    }

    func canControl(_ display: DisplayInfo) -> Bool {
        // CLAUDE.md §3.4: "Apple displays (built-in, Studio Display, Pro
        // Display XDR)." Future macOS may remove these symbols entirely
        // (the framework is private) — that's the getFn/setFn nil case,
        // handled gracefully rather than crashing.
        getFn != nil && setFn != nil && display.isAppleDisplay
    }

    func get(_ display: DisplayInfo) -> Float? {
        guard let getFn else { return nil }
        var value: Float = -1
        let result = getFn(display.id, &value)
        guard result == 0, value >= 0 else { return nil }
        return value
    }

    func set(_ display: DisplayInfo, _ value: Float) -> BrightnessResult {
        guard let setFn else { return .unsupported }
        let result = setFn(display.id, value)
        return result == 0 ? .ok : .failed(result)
    }
}

/// Fallback for Apple displays when `DisplayServicesBackend` can't control
/// one — CLAUDE.md §3.4: "CoreDisplay_Display_SetUserBrightness /
/// GetUserBrightness from CoreDisplay.framework."
///
/// **Verified finding, not assumed:** on this machine's built-in panel,
/// `CoreDisplay_Display_GetUserBrightness` returns a constant `1.0`
/// regardless of the display's actual brightness — confirmed by setting
/// the real brightness (via `DisplayServicesBackend`) to several different
/// values and reading `CoreDisplay`'s value each time; it never moved.
/// `CoreDisplay`'s "UserBrightness" concept apparently isn't the same
/// thing as the panel's real backlight level on Apple Silicon built-in
/// displays — it may be a user *adjustment/offset* that only matters when
/// paired with auto-brightness, or it may simply not apply to this panel
/// type at all. This backend only ever engages when `DisplayServicesBackend`
/// can't (that's the whole point of trying backends in canControl order),
/// which doesn't happen on this dev machine, so this couldn't be tested on
/// a display where it would actually matter — a Studio Display or Pro
/// Display XDR might behave completely differently. **Flagged in
/// docs/QA.md for a beta tester with one of those to verify**: if `get()`
/// is similarly constant there, this backend's pin verification would
/// falsely report success even if `set()` silently did nothing.
final class CoreDisplayBackend: BrightnessBackend {
    let name = "CoreDisplay"

    private typealias GetFn = @convention(c) (CGDirectDisplayID) -> Double
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Double) -> Void

    private let getFn: GetFn?
    private let setFn: SetFn?

    init() {
        guard let handle = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_NOW) else {
            Log.display.error("dlopen CoreDisplay failed: \(String(cString: dlerror()), privacy: .public)")
            getFn = nil
            setFn = nil
            return
        }
        if let sym = dlsym(handle, "CoreDisplay_Display_GetUserBrightness") {
            getFn = unsafeBitCast(sym, to: GetFn.self)
        } else {
            Log.display.error("dlsym CoreDisplay_Display_GetUserBrightness failed")
            getFn = nil
        }
        if let sym = dlsym(handle, "CoreDisplay_Display_SetUserBrightness") {
            setFn = unsafeBitCast(sym, to: SetFn.self)
        } else {
            Log.display.error("dlsym CoreDisplay_Display_SetUserBrightness failed")
            setFn = nil
        }
    }

    func canControl(_ display: DisplayInfo) -> Bool {
        getFn != nil && setFn != nil && display.isAppleDisplay
    }

    func get(_ display: DisplayInfo) -> Float? {
        guard let getFn else { return nil }
        return Float(getFn(display.id))
    }

    func set(_ display: DisplayInfo, _ value: Float) -> BrightnessResult {
        guard let setFn else { return .unsupported }
        setFn(display.id, Double(value))
        return .ok // this API has no return value to check
    }
}

/// Read-only cross-check via the public IORegistry — ARCHITECTURE.md §2.5:
/// "used only to cross-check that a pin held when backend 1 or 2 cannot
/// read back." `set` always returns `.unsupported`; this backend never
/// controls anything, only observes.
///
/// **Verified finding, not assumed:** on this machine, none of the four
/// fields under `AppleARMBacklight`'s `IODisplayParameters`
/// (`brightness`, `rawBrightness`, `BrightnessMilliNits`,
/// `BrightnessMicroAmps`) changed at all when the real brightness was set
/// to several different values via `DisplayServicesBackend` — all stayed
/// exactly where they started. This is a real, tested finding, not a
/// theoretical caveat: this backend's `get()` should not be trusted as a
/// live cross-check on this hardware/macOS combination. It's implemented
/// per spec anyway (harmless, and may behave differently on Intel Macs or
/// other Apple Silicon generations) but `PWMSafeCoordinator` does not
/// depend on it — `DisplayServicesBackend`'s own read-back already works
/// correctly and is what pin verification actually uses.
final class IORegistryReadOnlyBackend: BrightnessBackend {
    let name = "IORegistry(AppleARMBacklight)"

    func canControl(_ display: DisplayInfo) -> Bool {
        false // read-only, by design — never selected as the active backend
    }

    func get(_ display: DisplayInfo) -> Float? {
        guard display.isBuiltin else { return nil } // AppleARMBacklight is the built-in panel only
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleARMBacklight"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard let props = IORegistryEntryCreateCFProperty(service, "IODisplayParameters" as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        guard let dict = props.takeRetainedValue() as? [String: Any],
              let brightness = dict["brightness"] as? [String: Any],
              let value = brightness["value"] as? Int,
              let max = brightness["max"] as? Int,
              max > 0
        else {
            return nil
        }
        return Float(value) / Float(max)
    }

    func set(_ display: DisplayInfo, _ value: Float) -> BrightnessResult {
        .unsupported
    }
}
