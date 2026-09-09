// gamma_spike.swift — the very first thing to run on a new macOS build.
//
//   swift scripts/gamma_spike.swift
//
// Purpose: prove (or disprove) that CGSetDisplayTransferByTable visibly changes
// the screen on THIS macOS build. A successful return code and a successful
// read-back do NOT prove the panel changed (Apple bugs FB19136488, FB22273730:
// the table is stored and the display ignores it). A human must watch.
//
// Run it twice: once with System Settings → Displays → "Automatically adjust
// brightness" ON, once OFF. Record both results in docs/QA.md.
//
// Restores colours after 4 s, on Ctrl-C, and on SIGTERM. If the screen ever
// stays tinted: `defaults delete com.apple.windowserver` is NOT needed —
// just run `swift scripts/gamma_spike.swift restore`.

import CoreGraphics
import Foundation

if CommandLine.arguments.contains("restore") {
    CGDisplayRestoreColorSyncSettings()
    print("restored")
    exit(0)
}

signal(SIGINT) { _ in CGDisplayRestoreColorSyncSettings(); exit(0) }
signal(SIGTERM) { _ in CGDisplayRestoreColorSyncSettings(); exit(0) }

var count: UInt32 = 0
var ids = [CGDirectDisplayID](repeating: 0, count: 16)
CGGetActiveDisplayList(16, &ids, &count)
print("macOS:", ProcessInfo.processInfo.operatingSystemVersionString)
print("displays:", count)

for id in ids.prefix(Int(count)) {
    let cap = CGDisplayGammaTableCapacity(id)
    var r = [CGGammaValue](repeating: 0, count: Int(cap))
    var g = r
    var b = r
    var n: UInt32 = 0
    let readErr = CGGetDisplayTransferByTable(id, cap, &r, &g, &b, &n)
    print("display \(id) builtin=\(CGDisplayIsBuiltin(id) != 0) capacity=\(cap) read=\(readErr.rawValue) n=\(n)")

    // Pure red: keep the original red curve, zero green and blue.
    let zeros = [CGGammaValue](repeating: 0, count: Int(n))
    let setErr = CGSetDisplayTransferByTable(id, n, r, zeros, zeros)
    print("  set pure red -> \(setErr.rawValue)  (0 = kCGErrorSuccess)")

    var r2 = [CGGammaValue](repeating: 0, count: Int(n))
    var g2 = r2
    var b2 = r2
    var n2: UInt32 = 0
    _ = CGGetDisplayTransferByTable(id, n, &r2, &g2, &b2, &n2)
    print("  read-back green max = \(g2.max() ?? -1)  (0.0 means the table was stored)")
}

print("")
print(">>> LOOK AT THE SCREEN NOW. It should be PURE RED for 4 seconds. <<<")
print("    Red  = gamma path works on this build.")
print("    Not red although 'set' returned 0 = the Tahoe-class bug; Fallback overlay becomes primary.")
Thread.sleep(forTimeInterval: 4)
CGDisplayRestoreColorSyncSettings()
print("restored")
