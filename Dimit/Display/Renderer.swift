import Foundation

/// The single pure decision function: given the user-visible state and the
/// currently connected displays, decide what every display should show.
/// No CoreGraphics calls, no side effects — ARCHITECTURE.md §2.1.
///
/// `Applier` (`Dimit/Display/Applier.swift`) diffs consecutive outputs of
/// this function and only reports fields that actually changed; that split
/// is what keeps idle CPU near zero and slider latency low, and it is why
/// this function must be cheap and pure.
enum Renderer {
    static func render(_ state: RenderState, displays: [DisplayInfo]) -> [DisplayCommand] {
        displays.map { command(for: state, display: $0) }
    }

    private static func command(for state: RenderState, display: DisplayInfo) -> DisplayCommand {
        guard state.isOn else {
            return DisplayCommand(displayID: display.id, gamma: nil, overlayAlpha: 0, hardwareBrightness: nil)
        }

        let brightness = state.brightness.clamped(to: 0...1)

        // Fallback mode: CLAUDE.md §3.3 / ARCHITECTURE.md §2.7 — gamma is
        // deliberately left at baseline (this is the whole reason Fallback
        // mode exists: it's the escape hatch for when gamma itself is
        // broken, e.g. the macOS 26 Tahoe-class bugs). `gamma: nil` here
        // reuses exactly the same "restore, then leave alone" semantics
        // OFF uses — Applier's diff doesn't need to know *why* gamma
        // should be left alone, only that it should be.
        //
        // The overlay approximates both warmth and dim as one alpha over
        // a fixed red tint, rather than exactly reproducing what gamma
        // would have done — an overlay can only composite a color on top,
        // it can't multiply the framebuffer's existing colors the way a
        // gamma table does, so an exact match isn't possible by
        // construction. Fallback mode is a rarely-used safety net, not
        // the primary experience, so a simple, clearly-visible
        // approximation (redder and darker as warmth/brightness drop) is
        // the right amount of engineering for what it's for.
        if state.fallbackMode {
            let warmthAlpha = 1 - (state.warmthK.clamped(to: 0...Config.maxWarmthK) / Config.maxWarmthK)
            let brightnessAlpha = 1 - brightness
            let alpha = max(warmthAlpha, brightnessAlpha).clamped(to: 0...1)
            return DisplayCommand(
                displayID: display.id,
                gamma: nil,
                overlayAlpha: alpha,
                overlayTint: .red,
                hardwareBrightness: state.pwmSafe ? 1.0 : nil
            )
        }

        let multiplier = WarmthCurve.rgb(kelvin: state.warmthK)
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
            overlayTint: .black,
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
    var fallbackMode: Bool = false
}
