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
final class DDCTests: XCTestCase {
    // MARK: - Checksum (DDC/CI: XOR of dest addr, source addr, and payload)

    func test_checksum_matchesTheWorkedExampleForASetBrightnessMessage() {
        // Set VCP 0x10 to 50 (0x0032): [0x84, 0x03, 0x10, 0x00, 0x32]
        // seed = 0x6E ^ 0x51 = 0x3F
        // 0x3F ^ 0x84 ^ 0x03 ^ 0x10 ^ 0x00 ^ 0x32
        let expected: UInt8 = 0x3F ^ 0x84 ^ 0x03 ^ 0x10 ^ 0x00 ^ 0x32
        XCTAssertEqual(DDCLink.checksum(of: [0x84, 0x03, 0x10, 0x00, 0x32]), expected)
    }

    func test_checksum_changesWhenAnyByteChanges() {
        let base = DDCLink.checksum(of: [0x84, 0x03, 0x10, 0x00, 0x32])
        XCTAssertNotEqual(base, DDCLink.checksum(of: [0x84, 0x03, 0x10, 0x00, 0x33]))
        XCTAssertNotEqual(base, DDCLink.checksum(of: [0x84, 0x03, 0x11, 0x00, 0x32]))
    }

    // MARK: - Reply parsing

    /// A well-formed "current 50 of max 100" brightness reply.
    private func reply(current: UInt16, maximum: UInt16, code: UInt8 = 0x10, result: UInt8 = 0x00) -> [UInt8] {
        [
            0x6E, 0x88, 0x02, result, code, 0x00,
            UInt8(maximum >> 8), UInt8(maximum & 0xFF),
            UInt8(current >> 8), UInt8(current & 0xFF),
            0x00,
        ]
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
