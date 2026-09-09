import CoreGraphics
import Foundation
import IOKit

/// Third-party external-monitor brightness via DDC/CI — CLAUDE.md §3.4:
/// "VCP code 0x10 (brightness) via IOKit. On Apple Silicon use the
/// IOAVService path (`IOAVServiceCreateWithService`,
/// `IOAVServiceWriteI2C`/`ReadI2C`, as used by m1ddc/MonitorControl/
/// OpenDisplay)."
///
/// **Every private symbol here was verified to resolve on this machine
/// before any of this was written** (macOS 27.0 beta, M1 Pro), the same
/// discipline C3's `BrightnessController` used: `IOAVServiceCreate`,
/// `IOAVServiceCreateWithService`, `IOAVServiceReadI2C` and
/// `IOAVServiceWriteI2C` all live inside the *public* IOKit framework at
/// `/System/Library/Frameworks/IOKit.framework/IOKit` as private symbols.
///
/// **Verified against one real monitor on 2026-09-10** (Xiaomi Mi Monitor,
/// docs/QA.md § External-monitor session): the service resolution, the
/// framing and the checksums all reach the panel and get DDC/CI replies
/// back — but that panel answers every Get VCP with a constant error frame
/// rather than a value, so on it this backend correctly resolves to
/// `unsupported`. The same session showed m1ddc parsing that frame as
/// "brightness 110": the reply validation in `parseVCPReply` is what keeps
/// PWM-Safe from pinning against a number that doesn't exist. No monitor
/// has yet *answered* through this code, so it stays behind two gates
/// (`AppState.ddcEnabled`, default OFF, plus the "Experimental" toggle in
/// Settings → Displays). On a machine with no external display,
/// `canControl` returns false for every display and nothing below it can
/// run at all.
@MainActor
final class DDCBackend: BrightnessBackend {
    let name = "DDC/CI"

    /// Reads the user's Experimental toggle without this type knowing
    /// `AppState` exists — AppDelegate wires it up. CLAUDE.md §3.4 calls
    /// this flag `Config.ddcEnabled`; it shipped as `AppState.ddcEnabled`
    /// so it could be persisted and bound to a real toggle (disclosed in
    /// CLAUDE.md §3.4's own "As built in C5b" note).
    private let isEnabled: () -> Bool

    /// What a display resolved to, cached per UUID. `canControl` runs on
    /// every pipeline pass (every slider tick) and neither an IORegistry
    /// walk nor a 40 ms DDC round trip can happen that often.
    private enum Resolution {
        /// The monitor answered a brightness query: its service, and the
        /// maximum it reported.
        case usable(service: DDCLink.ServiceRef, maximum: UInt16)
        /// Resolved and rejected — no service, or it wouldn't answer.
        /// Cached so a monitor that can't do DDC isn't re-probed forever.
        case unusable
    }

    private var resolutions: [String: Resolution] = [:]

    init(isEnabled: @escaping () -> Bool = { false }) {
        self.isEnabled = isEnabled
    }

    // MARK: - BrightnessBackend

    /// True only for a display that has actually **answered a brightness
    /// query**, not merely one with an `IOAVService` attached.
    ///
    /// C5b review caught the difference mattering: a monitor on a
    /// DDC-capable port that doesn't implement VCP 0x10 would pass a
    /// service-exists check, get picked as the backend, fail all three pin
    /// attempts and land in `.wontHold` — whose UI string is "DISPLAY
    /// WON'T HOLD 100%". CLAUDE.md §3.6 reserves that for a display that
    /// *has* a working backend and won't hold the value; the honest state
    /// for a monitor that can't do DDC brightness at all is
    /// `.unsupported` ("PWM-Safe needs an Apple display or a DDC/CI
    /// monitor"), which is what returning false here produces.
    func canControl(_ display: DisplayInfo) -> Bool {
        guard isEligible(display) else { return false }
        if case .usable = resolution(for: display) { return true }
        return false
    }

    /// The gate, checked by **every** entry point rather than only by
    /// `canControl`.
    ///
    /// Putting it solely in `canControl` and trusting `backend(for:)`'s
    /// ordering to protect `get`/`set` was a real bug found in C5b
    /// review: `set(builtInDisplay, x)` would resolve the *external*
    /// monitor's service (resolution ignores which display it was asked
    /// about — there is only ever one candidate) and write brightness to
    /// the wrong panel, then cache that service under the built-in's
    /// UUID. Only call ordering prevented it. A gate one layer deep in
    /// the selection path isn't a gate on the transport.
    private func isEligible(_ display: DisplayInfo) -> Bool {
        guard isEnabled() else { return false }
        return !display.isBuiltin // the internal panel is DisplayServices' job
    }

    func get(_ display: DisplayInfo) -> Float? {
        guard isEligible(display) else { return nil }
        guard case .usable(let service, let maximum) = resolution(for: display), maximum > 0 else { return nil }
        // The *current* value genuinely has to be re-read; only the
        // maximum is fixed for the life of the connection.
        guard let reading = DDCLink.readVCP(service: service, code: DDCLink.brightnessVCP) else { return nil }
        guard reading.maximum > 0 else { return nil }
        return Float(reading.current) / Float(reading.maximum)
    }

    func set(_ display: DisplayInfo, _ value: Float) -> BrightnessResult {
        // Uses the maximum cached at resolution time rather than re-reading
        // it. DDC/CI carries a raw device value, not a fraction, so the
        // scale is needed — but a monitor's maximum doesn't change while
        // it stays plugged in, and re-reading it cost a 40 ms blocking
        // round trip on *every write* (C5b review, against PLAN's "never
        // hangs the UI").
        guard isEligible(display) else { return .unsupported }
        guard case .usable(let service, let maximum) = resolution(for: display), maximum > 0 else { return .unsupported }
        // `clamped` propagates NaN, and `UInt16(nan)` traps — a hardware
        // path is the last place to take that risk, even with no caller
        // that can currently produce one.
        guard value.isFinite else { return .failed(-1) }
        let scaled = UInt16((Double(value).clamped(to: 0...1) * Double(maximum)).rounded())
        return DDCLink.writeVCP(service: service, code: DDCLink.brightnessVCP, value: scaled) ? .ok : .failed(-1)
    }

    /// Called by `DisplayCoordinator` when the display list changes — a
    /// cached service handle and the maximum beside it both belong to one
    /// physical connection and must not outlive it.
    func invalidateCache() {
        resolutions.removeAll()
    }

    // MARK: - Display -> IOAVService resolution

    private func resolution(for display: DisplayInfo) -> Resolution {
        if let cached = resolutions[display.uuid] { return cached }

        guard let service = DDCLink.singleExternalService(),
              let reading = DDCLink.readVCP(service: service, code: DDCLink.brightnessVCP),
              reading.maximum > 0
        else {
            resolutions[display.uuid] = .unusable
            return .unusable
        }
        let resolved = Resolution.usable(service: service, maximum: reading.maximum)
        resolutions[display.uuid] = resolved
        Log.display.info("DDC: \(display.uuid, privacy: .public) answers VCP 0x10, max \(reading.maximum, privacy: .public)")
        return resolved
    }
}

// MARK: - The private-API boundary

/// Every `IOAVService*` call in the app is inside this one type, behind a
/// graceful `nil`/`false` path — CLAUDE.md §12: "Every private-API call is
/// isolated in one file, behind a protocol, with a graceful `.unsupported`
/// path and a comment naming the framework path and symbol."
///
/// Internal rather than `private` only so `DimitTests` can exercise the
/// pure protocol maths (checksum, reply parsing) directly — the parts that
/// would silently corrupt a message, and the only parts testable without a
/// monitor attached.
enum DDCLink {
    /// `IOAVServiceCreateWithService` hands back a `CFTypeRef` with no
    /// public type of its own; this alias keeps the intent readable
    /// without pretending to know more about it than that. Nested rather
    /// than module-scope: Apple's own private header uses exactly this
    /// name, so a top-level alias would silently shadow it if IOKit ever
    /// makes it public.
    typealias ServiceRef = CFTypeRef

    /// VCP feature code 0x10 = luminance/brightness (CLAUDE.md §3.4).
    static let brightnessVCP: UInt8 = 0x10

    /// The DDC/CI I2C slave address, and the "source address" byte every
    /// request carries. Standard DDC/CI, not Apple-specific.
    private static let i2cAddress: UInt32 = 0x37
    private static let sourceAddress: UInt8 = 0x51

    /// Checksum seeds — **the one place this implementation had to choose
    /// between the specification and every shipping implementation.**
    ///
    /// A *set* request seeds with destination XOR source (0x6E ^ 0x51 =
    /// 0x3F). Both m1ddc and MonitorControl agree, and so does the spec.
    ///
    /// A *get* request is where they diverge: both references seed with
    /// **0x6E alone**, omitting the source address, even though 0x51 does
    /// go on the wire as `IOAVServiceWriteI2C`'s `dataAddress` and the
    /// spec (and ddcutil) include it. Fetched and read both sources
    /// directly to confirm rather than trusting recollection —
    /// m1ddc `sources/i2c.m`: `data[3] = 0x6e ^ data[0] ^ data[1] ^ data[2]`;
    /// MonitorControl `Arm64DDC.swift`: `chk: ARM64_DDC_7BIT_ADDRESS << 1`
    /// for a single-byte send, `^ dataAddress` otherwise.
    ///
    /// `readVCP` **tries both**: the reference seed first (what millions
    /// of monitor-hours actually use), then the spec seed. A request whose
    /// checksum a monitor rejects gets no usable reply, so the fallback
    /// costs one extra round trip only when the first was already going
    /// to fail — and the feature works either way rather than being inert
    /// if the guess is wrong.
    ///
    /// First real data point (2026-09-10, Xiaomi Mi Monitor, docs/QA.md):
    /// that panel accepts the **spec** seed and answers the reference seed
    /// with an error frame — the opposite of what both references assume.
    /// One monitor isn't grounds to flip the order, but it is grounds to
    /// keep trying both.
    private static let setChecksumSeed: UInt8 = 0x6E ^ 0x51
    static let getChecksumSeedReference: UInt8 = 0x6E
    static let getChecksumSeedSpec: UInt8 = 0x6E ^ 0x51
    /// Reply checksum seed: 0x50, the "virtual host address."
    /// MonitorControl validates replies with exactly this and uses the
    /// result as its retry criterion.
    static let replyChecksumSeed: UInt8 = 0x50

    /// Matches MonitorControl's defaults (50 ms read wait). An earlier
    /// comment here claimed "40 ms is the conventional value every
    /// open-source implementation uses" — checked, and that was wrong in
    /// both directions: m1ddc defaults to 10 ms, MonitorControl to 50 ms.
    /// Taking the larger, since a monitor that needs 50 ms returns an
    /// empty reply at 40.
    private static let readWaitMicroseconds: UInt32 = 50_000
    /// Deliberately 2, where MonitorControl uses 5. Every attempt blocks
    /// the main thread (see `DDCBackend`'s note on threading), so the
    /// worst case is bounded at ~100 ms rather than ~250 ms until DDC
    /// transactions move off the main actor.
    private static let readAttempts = 2

    // MARK: Symbol resolution

    private typealias CreateWithServiceFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias WriteI2CFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeRawPointer, UInt32) -> IOReturn
    private typealias ReadI2CFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    private static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)

    private static let createWithService: CreateWithServiceFn? = symbol("IOAVServiceCreateWithService")
    private static let writeI2C: WriteI2CFn? = symbol("IOAVServiceWriteI2C")
    private static let readI2C: ReadI2CFn? = symbol("IOAVServiceReadI2C")

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let sym = dlsym(handle, name) else {
            Log.display.error("DDC: symbol \(name, privacy: .public) missing; DDC unavailable on this macOS")
            return nil
        }
        return unsafeBitCast(sym, to: T.self)
    }

    // MARK: Finding the display's AV service

    /// Resolves the `IOAVService` for an external display.
    ///
    /// Matching is deliberately conservative: this returns a service
    /// **only when the mapping is unambiguous** — exactly one external
    /// display connected and exactly one `DCPAVServiceProxy` reporting
    /// `Location == "External"`. With several external monitors there is
    /// no verified way (on this machine, with no external display at all
    /// to test against) to say which proxy belongs to which
    /// `CGDirectDisplayID`, and guessing wrong means sending brightness
    /// commands to the wrong monitor. Returning `nil` degrades to the
    /// same clean "unsupported" state a non-DDC monitor already produces.
    /// Relaxing this needs someone with two external displays to verify
    /// an ordering heuristic first.
    ///
    /// (`IOMobileFramebufferShim` matches zero services on macOS 27 —
    /// verified on this machine — which is why this goes through
    /// `DCPAVServiceProxy`. An earlier version of this comment credited
    /// that class to m1ddc; that was wrong. m1ddc matches
    /// `IOObjectConformsTo(service, "IOMobileFramebuffer")`, which *does*
    /// still match here (3 live `AppleCLCD2` nodes), and pairs each
    /// framebuffer to the `DCPAVServiceProxy` beneath it — so per-display
    /// matching is achievable and the single-display restriction above is
    /// conservatism, not a hard limit. Implementing that pairing without
    /// a second external display to verify it against would mean shipping
    /// an untestable guess about which monitor receives a write, which is
    /// the one mistake this whole file is arranged to avoid.)
    static func singleExternalService() -> ServiceRef? {
        guard createWithService != nil else { return nil }
        let externalCount = externalDisplayCount()
        guard externalCount == 1 else {
            Log.display.info("DDC: \(externalCount, privacy: .public) external displays; DDC needs exactly one to match unambiguously, staying unsupported")
            return nil
        }

        var proxies: [io_service_t] = []
        var iterator: io_iterator_t = 0
        guard let matchingDict = IOServiceMatching("DCPAVServiceProxy"),
              IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator) == KERN_SUCCESS
        else { return nil }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            if locationString(of: service) == "External" {
                proxies.append(service)
            } else {
                IOObjectRelease(service)
            }
            service = IOIteratorNext(iterator)
        }
        IOObjectRelease(iterator)

        defer { proxies.forEach { IOObjectRelease($0) } }
        guard proxies.count == 1, let proxy = proxies.first else { return nil }
        return createWithService?(kCFAllocatorDefault, proxy)?.takeRetainedValue()
    }

    private static func locationString(of service: io_service_t) -> String? {
        guard let value = IORegistryEntryCreateCFProperty(service, "Location" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
        else { return nil }
        return value
    }

    private static func externalDisplayCount() -> Int {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return 0 }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return 0 }
        return ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 }.count
    }

    // MARK: DDC/CI messages

    struct VCPReading {
        var current: UInt16
        var maximum: UInt16
    }

    /// "Set VCP Feature": `[length, 0x03, code, valueHigh, valueLow, checksum]`.
    static func writeVCP(service: ServiceRef, code: UInt8, value: UInt16) -> Bool {
        guard let writeI2C else { return false }
        var message: [UInt8] = [
            0x84, // 0x80 | 4 payload bytes
            0x03, // set VCP feature
            code,
            UInt8(value >> 8),
            UInt8(value & 0xFF),
        ]
        message.append(checksum(of: message, seed: setChecksumSeed))
        let result = message.withUnsafeBytes { buffer in
            writeI2C(service, i2cAddress, UInt32(sourceAddress), buffer.baseAddress!, UInt32(buffer.count))
        }
        if result != KERN_SUCCESS {
            Log.display.error("DDC: write VCP 0x\(String(code, radix: 16), privacy: .public) failed: \(result, privacy: .public)")
        }
        return result == KERN_SUCCESS
    }

    /// "Get VCP Feature" request plus its 11-byte reply. Returns `nil` on
    /// any transport error, a mismatched reply, or a monitor that reports
    /// the feature unsupported — never a guessed value.
    static func readVCP(service: ServiceRef, code: UInt8) -> VCPReading? {
        // Try the reference seed first, then the spec seed — see the
        // `getChecksumSeed*` comment. Each seed gets the full retry count,
        // because a dropped exchange (routine on this bus) and a rejected
        // checksum look identical from here: no reply either way.
        for seed in [getChecksumSeedReference, getChecksumSeedSpec] {
            for _ in 0..<readAttempts {
                if let reading = attemptReadVCP(service: service, code: code, seed: seed) {
                    return reading
                }
            }
        }
        return nil
    }

    private static func attemptReadVCP(service: ServiceRef, code: UInt8, seed: UInt8) -> VCPReading? {
        guard let writeI2C, let readI2C else { return nil }

        var request: [UInt8] = [
            0x82, // 0x80 | 2 payload bytes
            0x01, // get VCP feature
            code,
        ]
        request.append(checksum(of: request, seed: seed))

        let writeResult = request.withUnsafeBytes { buffer in
            writeI2C(service, i2cAddress, UInt32(sourceAddress), buffer.baseAddress!, UInt32(buffer.count))
        }
        guard writeResult == KERN_SUCCESS else { return nil }

        // The display needs time to prepare its reply before we read it.
        usleep(readWaitMicroseconds)

        // Offset **0**, not the 0x51 the *write* uses. Verified against
        // MonitorControl's Apple Silicon path, which passes
        // `UInt32(dataAddress)` when writing and a hardcoded `0` when
        // reading. An earlier version of this file passed 0x51 for both,
        // which would have read from the wrong I2C offset — the exact
        // "silently talks to the wrong place" failure that makes
        // untestable hardware code dangerous, and not something any
        // amount of local testing here could have surfaced.
        var reply = [UInt8](repeating: 0, count: 11)
        let readResult = reply.withUnsafeMutableBytes { buffer in
            readI2C(service, i2cAddress, 0, buffer.baseAddress!, UInt32(buffer.count))
        }
        guard readResult == KERN_SUCCESS else { return nil }
        return parseVCPReply(reply, expecting: code)
    }

    /// Reply layout: `[source, length, 0x02, result, code, type, maxHi,
    /// maxLo, curHi, curLo, checksum]`. A non-zero `result` byte is the
    /// monitor saying it doesn't support this feature.
    static func parseVCPReply(_ reply: [UInt8], expecting code: UInt8) -> VCPReading? {
        guard reply.count == 11 else { return nil }
        // Validate the reply's own checksum before trusting any byte in
        // it. Omitting this was a real hole: a corrupted reply that
        // happened to satisfy the three structural checks below would
        // yield a garbage maximum, and `set` scales the user's requested
        // brightness by exactly that number. Worse, a garbage *current*
        // can read as >= 0.99 and make `verifyPin` report a successful
        // pin while the backlight is actually somewhere else entirely —
        // silently defeating the one thing PWM-Safe exists to do.
        // MonitorControl validates this and uses it as its retry
        // criterion; seed 0x50, the virtual host address.
        guard checksum(of: Array(reply.dropLast()), seed: replyChecksumSeed) == reply[10] else { return nil }
        guard reply[2] == 0x02 else { return nil } // not a VCP feature reply
        guard reply[3] == 0x00 else { return nil } // monitor reports the feature unsupported
        guard reply[4] == code else { return nil } // reply is for a different VCP code
        let maximum = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        return VCPReading(current: current, maximum: maximum)
    }

    /// DDC/CI checksum: XOR of a frame-type-dependent seed and every
    /// payload byte. The seed is explicit rather than a single constant
    /// because set requests, get requests and replies each use a
    /// different one — see `setChecksumSeed` and friends.
    static func checksum(of message: [UInt8], seed: UInt8) -> UInt8 {
        message.reduce(seed) { $0 ^ $1 }
    }
}


