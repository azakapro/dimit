import XCTest
@testable import Dimit

/// The DDC/CI *protocol* logic — checksums and reply parsing — is pure and
/// fully testable without a monitor. The I2C transport around it is not:
/// this session had no external display, so `DDCBackend`'s actual reads and
/// writes are unverified against real hardware and ship behind two gates
/// (default-OFF persisted toggle + "Experimental" labelling). What *is*
/// verified here is the part that would silently corrupt a message, and the
/// property that matters most for everyone without an external monitor:
/// that nothing DDC-related runs at all.
@MainActor
final class DDCTests: XCTestCase {
    // MARK: - Checksum, against the VESA DDC/CI 1.1 spec's own worked examples

    // The spec (§6.2/§6.3) publishes these, and ddcutil carries them as
    // its own regression vectors. Using them instead of restating the
    // implementation's formula matters: an earlier version of this test
    // computed `0x3F ^ 0x84 ^ ...` inline, which is the same XOR the code
    // performs — it could never have caught a wrong seed, which turned out
    // to be the single highest-risk unknown in this whole file.
    func test_checksum_matchesTheSpecsPublishedVectors() {
        // §6.2, a host->display request: 6E 51 82 F5 01 -> 0x49
        XCTAssertEqual(DDCLink.checksum(of: [0x82, 0xF5, 0x01], seed: 0x6E ^ 0x51), 0x49)
        // §6.3, a display->host reply, seeded with the 0x50 virtual host
        // address: 6F 6E 82 A1 00 -> 0x1D
        XCTAssertEqual(DDCLink.checksum(of: [0x6E, 0x82, 0xA1, 0x00], seed: 0x50), 0x1D)
        // §6.4, the null reply: 6F 6E 80 -> 0xBE
        XCTAssertEqual(DDCLink.checksum(of: [0x6E, 0x80], seed: 0x50), 0xBE)
    }

    // Get VCP 0x10 (brightness): 6E 51 82 01 10 -> 0xAC per the spec.
    // MonitorControl and m1ddc both send 0xFD here instead, omitting the
    // 0x51 — which is why `readVCP` tries both seeds rather than betting
    // on either. This pins that both values are what we think they are.
    func test_getBrightnessRequest_bothSeedsProduceTheKnownValues() {
        let payload: [UInt8] = [0x82, 0x01, 0x10]
        XCTAssertEqual(DDCLink.checksum(of: payload, seed: DDCLink.getChecksumSeedSpec), 0xAC)
        XCTAssertEqual(DDCLink.checksum(of: payload, seed: DDCLink.getChecksumSeedReference), 0xFD)
    }

    // Set VCP 0x10 to 100: 6E 51 84 03 10 00 64 -> 0xCC per the spec.
    // This path matches both reference implementations exactly.
    func test_setBrightnessRequest_matchesTheSpecVector() {
        XCTAssertEqual(DDCLink.checksum(of: [0x84, 0x03, 0x10, 0x00, 0x64], seed: 0x6E ^ 0x51), 0xCC)
    }

    // MARK: - Reply parsing

    /// A well-formed "current N of max M" brightness reply, carrying a
    /// correct trailing checksum (seed 0x50, the spec's virtual host
    /// address) so it survives the validation `parseVCPReply` now does.
    private func reply(current: UInt16, maximum: UInt16, code: UInt8 = 0x10, result: UInt8 = 0x00) -> [UInt8] {
        var bytes: [UInt8] = [
            0x6E, 0x88, 0x02, result, code, 0x00,
            UInt8(maximum >> 8), UInt8(maximum & 0xFF),
            UInt8(current >> 8), UInt8(current & 0xFF),
        ]
        bytes.append(DDCLink.checksum(of: bytes, seed: DDCLink.replyChecksumSeed))
        return bytes
    }

    func test_parseReply_readsCurrentAndMaximum() {
        let parsed = DDCLink.parseVCPReply(reply(current: 50, maximum: 100), expecting: 0x10)
        XCTAssertEqual(parsed?.current, 50)
        XCTAssertEqual(parsed?.maximum, 100)
    }

    func test_parseReply_handlesMultiByteValues() {
        let parsed = DDCLink.parseVCPReply(reply(current: 0x0140, maximum: 0x03E8), expecting: 0x10)
        XCTAssertEqual(parsed?.current, 320)
        XCTAssertEqual(parsed?.maximum, 1000)
    }

    // A monitor answering "I don't support that feature" must never be
    // read as a real value — a nonzero result byte means exactly that.
    func test_parseReply_rejectsUnsupportedFeatureResult() {
        XCTAssertNil(DDCLink.parseVCPReply(reply(current: 50, maximum: 100, result: 0x01), expecting: 0x10))
    }

    // A reply about a *different* VCP code means the exchange desynced;
    // trusting it would apply a brightness read from, say, a contrast query.
    func test_parseReply_rejectsAReplyForADifferentVCPCode() {
        XCTAssertNil(DDCLink.parseVCPReply(reply(current: 50, maximum: 100, code: 0x12), expecting: 0x10))
    }

    // The hole this closes: a corrupted reply that happens to satisfy the
    // structural checks would otherwise yield a garbage maximum, which
    // `set` scales the user's brightness by — or a garbage current that
    // reads as >= 0.99 and makes `verifyPin` report a successful pin while
    // the backlight sits somewhere else entirely.
    func test_parseReply_rejectsAReplyWhoseChecksumDoesNotMatch() {
        var corrupted = reply(current: 50, maximum: 100)
        corrupted[8] ^= 0xFF // flip the current-value high byte, leave the checksum stale
        XCTAssertNil(DDCLink.parseVCPReply(corrupted, expecting: 0x10))
    }

    // The display's "I have nothing for you" reply (spec §6.4) must be
    // rejected rather than parsed as a brightness value. It is the most
    // common real-world response from a busy monitor.
    func test_parseReply_rejectsTheNullMessage() {
        var nullReply: [UInt8] = [0x6E, 0x80]
        nullReply.append(DDCLink.checksum(of: nullReply, seed: DDCLink.replyChecksumSeed))
        nullReply.append(contentsOf: [UInt8](repeating: 0, count: 8))
        XCTAssertNil(DDCLink.parseVCPReply(nullReply, expecting: 0x10))
    }

    func test_parseReply_rejectsTruncatedOrGarbageReplies() {
        XCTAssertNil(DDCLink.parseVCPReply([], expecting: 0x10))
        XCTAssertNil(DDCLink.parseVCPReply([0x6E, 0x88], expecting: 0x10))
        var notAVCPReply = reply(current: 50, maximum: 100)
        notAVCPReply[2] = 0x09 // not the 0x02 "VCP feature reply" opcode
        XCTAssertNil(DDCLink.parseVCPReply(notAVCPReply, expecting: 0x10))
    }

    // A monitor reporting a zero maximum would make the fraction maths
    // divide by zero; `DDCBackend.get` guards on it, and this pins that a
    // zero max is at least parsed rather than crashing.
    func test_parseReply_zeroMaximum_parsesButIsRejectedByTheCaller() {
        let parsed = DDCLink.parseVCPReply(reply(current: 0, maximum: 0), expecting: 0x10)
        XCTAssertEqual(parsed?.maximum, 0)
    }

    // MARK: - The property that matters on a machine with no external display

    // Every other guard in this file protects a monitor nobody here has.
    // This one protects *this* machine, and every user who never plugs
    // anything in: with the toggle off — the default — DDC must be
    // completely inert, and the built-in panel must never be a DDC
    // candidate even with the toggle on.
    func test_disabledByDefault_neverClaimsAnyDisplay() {
        let backend = DDCBackend() // default isEnabled: { false }
        let external = DisplayInfo(id: 2, uuid: "ext", name: "Some Monitor", isBuiltin: false)
        XCTAssertFalse(backend.canControl(external))
        XCTAssertNil(backend.get(external))
        XCTAssertEqual(backend.set(external, 1.0), .unsupported)
    }

    func test_evenWhenEnabled_neverClaimsTheBuiltInPanel() {
        let backend = DDCBackend(isEnabled: { true })
        let builtin = DisplayInfo(id: 1, uuid: "builtin", name: "Built-in", isBuiltin: true)
        XCTAssertFalse(backend.canControl(builtin), "the internal panel is DisplayServices' job, never DDC's")
        XCTAssertEqual(backend.set(builtin, 1.0), .unsupported)
    }

    // Runs against this machine's real IORegistry: no external display is
    // connected, so even an enabled backend must find nothing and say so
    // cleanly rather than erroring or hanging.
    func test_enabledWithNoExternalDisplayConnected_staysUnsupported() {
        let backend = DDCBackend(isEnabled: { true })
        let external = DisplayInfo(id: 99, uuid: "not-connected", name: "Absent", isBuiltin: false)
        XCTAssertFalse(backend.canControl(external))
        XCTAssertEqual(backend.set(external, 0.5), .unsupported)
    }
}
