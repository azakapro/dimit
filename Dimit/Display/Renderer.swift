import Foundation

/// The single pure decision function: given the user-visible state and the
/// currently connected displays, decide what every display should show.
/// No CoreGraphics calls, no side effects — ARCHITECTURE.md §2.1.
///
/// `Applier` (C2) will diff consecutive outputs of this function and only
/// call the real controllers for fields that changed; that split is what
/// keeps idle CPU near zero and slider latency low, and it is why this
/// function must be cheap and pure.
enum Renderer {
    static func render(_ state: RenderState, displays: [DisplayInfo]) -> [DisplayCommand] {
        displays.map { command(for: state, display: $0) }
    }

    private static func command(for state: RenderState, display: DisplayInfo) -> DisplayCommand {
        guard state.isOn else {
            return DisplayCommand(displayID: display.id, gamma: nil, overlayAlpha: 0, hardwareBrightness: nil)
        }

        let multiplier = WarmthCurve.rgb(kelvin: state.warmthK)
        // Defensive clamp to the math's own valid domain (0...1), matching
        // WarmthCurve's clamp on its input — code review on C1 caught that
        // this one was missing. Note this is 0...1, not
        // Config.minBrightness...maxBrightness: that pair is a *UI* policy
        // (the slider won't let a user drag below 10%), whereas brightness
        // 0 is a real, supported point in this function's own math (fully
        // opaque overlay) that a future caller — the schedule engine ramping
        // down, say — may legitimately reach.
        let brightness = state.brightness.clamped(to: 0...1)
        let floor = Config.gammaDimFloor
        let dim: Double
        let overlayAlpha: Double
        if brightness >= floor {
            dim = brightness
            overlayAlpha = 0
        } else {
            dim = floor
            // At brightness 0 the overlay is fully opaque black; at the
            // floor it is fully transparent. Linear in between.
            overlayAlpha = 1 - (brightness / floor)
        }

        return DisplayCommand(
            displayID: display.id,
            gamma: GammaSpec(multiplier: multiplier, dim: dim),
            overlayAlpha: overlayAlpha,
            hardwareBrightness: state.pwmSafe ? 1.0 : nil
        )
    }
}

/// The subset of `AppState` that rendering depends on, as a plain value
/// type. Keeping this separate from the `ObservableObject` means
/// `Renderer` tests never need to spin up an `AppState` (main-actor,
/// Combine, UserDefaults) — they just construct a `RenderState` literal.
struct RenderState: Equatable {
    var isOn: Bool
    var warmthK: Double
    var brightness: Double
    var pwmSafe: Bool
}
