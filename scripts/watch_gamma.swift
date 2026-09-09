// Prints the live gamma table of the main display once a second, so you can
// watch what the OS does to it while you do something else — start a screen
// recording, share in Zoom, sleep and wake, plug a monitor in.
//
// Run it, leave it running, then do the thing:
//
//     swift scripts/watch_gamma.swift
//
// TINTED means Dimit's filter is actually on the hardware right now.
// NEUTRAL means it is not, whatever the menu bar icon claims.
//
// Written for the "does starting a screen recording kill the tint?" question,
// which nothing in the test suite can answer: a recording needs a permission
// the app must never request (CLAUDE.md §1.5), so a human has to start one
// while something watches.
import CoreGraphics
import Foundation

let display = CGMainDisplayID()
let capacity = Int(CGDisplayGammaTableCapacity(display))

func sample() -> (r: Float, g: Float, b: Float)? {
    var red = [CGGammaValue](repeating: 0, count: capacity)
    var green = red, blue = red
    var count: UInt32 = 0
    guard CGGetDisplayTransferByTable(display, UInt32(capacity), &red, &green, &blue, &count) == .success,
          count > 1 else { return nil }
    let i = Int(count) / 2
    return (red[i], green[i], blue[i])
}

// Line-buffer stdout: without this, piping this script to a file or to
// `tee` shows nothing until it exits, which defeats the point of watching
// it live.
setvbuf(stdout, nil, _IOLBF, 0)

let formatter = DateFormatter()
formatter.dateFormat = "HH:mm:ss"

print("Watching the main display's gamma table. Ctrl-C to stop.")
print("Turn Dimit ON at a warm setting first — you should see TINTED.")
print("Then start your screen recording and watch this column.\n")
print("time      red      green    blue     verdict")

var previous: String?
while true {
    guard let s = sample() else {
        print("\(formatter.string(from: Date()))  <could not read the gamma table>")
        Thread.sleep(forTimeInterval: 1)
        continue
    }
    // Neutral means all three channels agree; a warm tint pulls green and
    // blue below red. This is the same check the integration probes use.
    let isNeutral = abs(s.r - s.g) < 0.001 && abs(s.g - s.b) < 0.001
    let verdict = isNeutral ? "NEUTRAL — no filter on the hardware" : "TINTED"
    let line = String(format: "%@  %.5f  %.5f  %.5f  %@",
                      formatter.string(from: Date()), s.r, s.g, s.b, verdict)
    // Only reprint when something actually changes, so a transition is
    // obvious in the scrollback instead of buried in identical rows.
    let signature = verdict + String(format: "%.4f%.4f", s.g, s.b)
    if signature != previous {
        print(line + (previous == nil ? "" : "   <-- CHANGED"))
        previous = signature
    }
    Thread.sleep(forTimeInterval: 1)
}
