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
            // Two conceptual veils, composited into the one window we have:
            // a red veil for warmth, then a black veil for dimming *over*
            // it, so dimming darkens the red too.
            //
            //   out = ad·BLACK + (1-ad)·[aw·RED + (1-aw)·content]
            //       = (1-ad)·aw·RED + (1-ad)(1-aw)·content
            //
            // Matching that to one window's `alpha·colour + (1-alpha)·content`
            // gives the alpha and red channel below.
            //
            // An earlier version took `max(warmthAlpha, brightnessAlpha)`
            // with a fixed pure-red colour, and the independent review
            // caught two bugs in it that this replaces:
            //
            //  1. At 0K the alpha reached exactly 1.0, so NIGHT + Fallback
            //     painted an opaque red rectangle over everything including
            //     the menu bar — hiding the very controls needed to undo it,
            //     in the mode that exists *because* the display is already
            //     misbehaving. `warmthVeil` is capped below 1 so some of the
            //     real screen always survives.
            //  2. Dimming at neutral warmth still painted red, so lowering
            //     brightness at 6500K made black pixels redder and
            //     *brighter*. `warmthVeil` is 0 at 6500K, which makes the
            //     colour black there — the exact multiply that dimming wants.
            let warmthVeil = (1 - state.warmthK.clamped(to: 0...Config.maxWarmthK) / Config.maxWarmthK)
                * Config.fallbackMaxWarmthVeil
            let dimVeil = 1 - brightness
            let alpha = (1 - (1 - warmthVeil) * (1 - dimVeil)).clamped(to: 0...1)
            let redChannel = alpha > 0 ? ((1 - dimVeil) * warmthVeil / alpha).clamped(to: 0...1) : 0
            return DisplayCommand(
                displayID: display.id,
                gamma: nil,
                overlayAlpha: alpha,
                overlayTint: .red(intensity: redChannel),
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
