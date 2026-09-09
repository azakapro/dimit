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
/// **The I2C traffic itself is unverified against real hardware** — this
/// session had no external monitor. It ships behind two separate gates
/// (`Config.ddcEnabled`-backed `AppState.ddcEnabled`, default OFF, plus
/// an "Experimental" toggle in Settings → Displays) precisely because of
/// that. On a machine with no external display, `canControl` returns
/// false for every display and nothing below it can run at all — which
/// *is* verified here, and is the property that makes shipping the rest
/// untested acceptable.
final class DDCBackend: BrightnessBackend {
    let name = "DDC/CI"

    /// Reads the user's Experimental toggle without this type knowing
    /// `AppState` exists — AppDelegate wires it up. CLAUDE.md §3.4:
    /// "Ships in 1.0 as an Experimental toggle in Settings
    /// (`Config.ddcEnabled`, default OFF)."
    private let isEnabled: () -> Bool

    /// One `IOAVService` per display UUID we've successfully resolved.
    /// Cached because `canControl` runs on every pipeline pass (every
    /// slider tick) and walking the IORegistry that often would be
    /// absurd; invalidated whenever the display list changes.
    private var services: [String: IOAVServiceRef] = [:]
    private var resolvedForUUIDs: Set<String> = []

    init(isEnabled: @escaping () -> Bool = { false }) {
        self.isEnabled = isEnabled
    }

    // MARK: - BrightnessBackend

    func canControl(_ display: DisplayInfo) -> Bool {
        guard isEnabled() else { return false }
        guard !display.isBuiltin else { return false } // the internal panel is DisplayServices' job
        return service(for: display) != nil
    }

    func get(_ display: DisplayInfo) -> Float? {
        guard let service = service(for: display) else { return nil }
        guard let reading = DDCLink.readVCP(service: service, code: DDCLink.brightnessVCP) else { return nil }
        guard reading.maximum > 0 else { return nil }
        return Float(reading.current) / Float(reading.maximum)
    }

    func set(_ display: DisplayInfo, _ value: Float) -> BrightnessResult {
        guard let service = service(for: display) else { return .unsupported }
        // DDC/CI carries a raw device value, not a fraction — scale into
        // the monitor's own reported range rather than assuming 0...100.
        // A monitor that won't tell us its maximum is one we shouldn't be
        // writing guesses to.
        guard let reading = DDCLink.readVCP(service: service, code: DDCLink.brightnessVCP), reading.maximum > 0 else {
            return .failed(-1)
        }
        let scaled = UInt16((Double(value).clamped(to: 0...1) * Double(reading.maximum)).rounded())
        return DDCLink.writeVCP(service: service, code: DDCLink.brightnessVCP, value: scaled) ? .ok : .failed(-1)
    }

    /// Called by `DisplayCoordinator` when the display list changes — the
    /// cached `IOAVService` handles belong to specific physical
    /// connections and must not outlive one.
    func invalidateCache() {
        services.removeAll()
        resolvedForUUIDs.removeAll()
    }

    // MARK: - Display -> IOAVService resolution

    private func service(for display: DisplayInfo) -> IOAVServiceRef? {
        if let cached = services[display.uuid] { return cached }
        guard !resolvedForUUIDs.contains(display.uuid) else { return nil } // already tried, genuinely none
        resolvedForUUIDs.insert(display.uuid)

        guard let resolved = DDCLink.externalService(matching: display) else { return nil }
        services[display.uuid] = resolved
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
    /// VCP feature code 0x10 = luminance/brightness (CLAUDE.md §3.4).
    static let brightnessVCP: UInt8 = 0x10

    /// The DDC/CI I2C slave address, and the "source address" byte every
    /// request carries. Standard DDC/CI, not Apple-specific.
    private static let i2cAddress: UInt32 = 0x37
    private static let sourceAddress: UInt8 = 0x51
    /// Checksum seed: the destination address (0x6E) XOR the source
    /// address, since `IOAVServiceWriteI2C` takes the address separately
    /// from the payload but the DDC checksum is defined over both.
    private static let checksumSeed: UInt8 = 0x6E ^ 0x51

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
    /// (On macOS 27 the older `IOMobileFramebufferShim` class that m1ddc
    /// matches against does not exist at all — verified, it matches zero
    /// services — which is why this goes through `DCPAVServiceProxy`.)
    static func externalService(matching display: DisplayInfo) -> IOAVServiceRef? {
        guard createWithService != nil else { return nil }
        guard externalDisplayCount() == 1 else {
            if externalDisplayCount() > 1 {
                Log.display.info("DDC: \(externalDisplayCount(), privacy: .public) external displays connected; per-display DDC matching is unverified, staying unsupported")
            }
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
    static func writeVCP(service: IOAVServiceRef, code: UInt8, value: UInt16) -> Bool {
        guard let writeI2C else { return false }
        var message: [UInt8] = [
            0x84, // 0x80 | 4 payload bytes
            0x03, // set VCP feature
            code,
            UInt8(value >> 8),
            UInt8(value & 0xFF),
        ]
        message.append(checksum(of: message))
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
    static func readVCP(service: IOAVServiceRef, code: UInt8) -> VCPReading? {
        guard let writeI2C, let readI2C else { return nil }

        var request: [UInt8] = [
            0x82, // 0x80 | 2 payload bytes
            0x01, // get VCP feature
            code,
        ]
        request.append(checksum(of: request))

        let writeResult = request.withUnsafeBytes { buffer in
            writeI2C(service, i2cAddress, UInt32(sourceAddress), buffer.baseAddress!, UInt32(buffer.count))
        }
        guard writeResult == KERN_SUCCESS else { return nil }

        // The DDC/CI spec requires the host to wait before reading the
        // reply; 40 ms is the conventional value every open-source
        // implementation of this uses.
        usleep(40_000)

        var reply = [UInt8](repeating: 0, count: 11)
        let readResult = reply.withUnsafeMutableBytes { buffer in
            readI2C(service, i2cAddress, UInt32(sourceAddress), buffer.baseAddress!, UInt32(buffer.count))
        }
        guard readResult == KERN_SUCCESS else { return nil }
        return parseVCPReply(reply, expecting: code)
    }

    /// Reply layout: `[source, length, 0x02, result, code, type, maxHi,
    /// maxLo, curHi, curLo, checksum]`. A non-zero `result` byte is the
    /// monitor saying it doesn't support this feature.
    static func parseVCPReply(_ reply: [UInt8], expecting code: UInt8) -> VCPReading? {
        guard reply.count >= 10 else { return nil }
        guard reply[2] == 0x02 else { return nil } // not a VCP feature reply
        guard reply[3] == 0x00 else { return nil } // monitor reports the feature unsupported
        guard reply[4] == code else { return nil } // reply is for a different VCP code
        let maximum = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        return VCPReading(current: current, maximum: maximum)
    }

    /// DDC/CI checksum: XOR of the destination and source addresses and
    /// every payload byte.
    static func checksum(of message: [UInt8]) -> UInt8 {
        message.reduce(checksumSeed) { $0 ^ $1 }
    }
}

/// `IOAVServiceCreateWithService` hands back a `CFTypeRef` with no public
/// type of its own; this alias keeps the intent readable at the call sites
/// above without pretending to know more about it than that.
typealias IOAVServiceRef = CFTypeRef
