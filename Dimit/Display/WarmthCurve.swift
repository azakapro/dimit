import Foundation

/// Pure Kelvin → RGB multiplier curve. No CoreGraphics, no side effects,
/// fully unit-testable — CLAUDE.md §3.2 and §12 ("write the test for the
/// pure function it depends on").
///
/// This is a **custom calibrated curve, not literal blackbody radiation.**
/// A literal Tanner Helland / Krystek blackbody approximation was tried
/// first and rejected: normalized to (1,1,1) at 6500K, it puts 2700K at
/// roughly (1, 0.65, 0.34) and drives blue to exactly 0 at 1900K — both
/// well outside the ranges CLAUDE.md §3.2 requires (2700K: g 0.72–0.78,
/// b 0.45–0.55; 1900K: g 0.55–0.62, b 0.20–0.30). Real blackbody math is
/// far more aggressive than what any shipping night-mode filter (Night
/// Shift, f.lux, Tap Zap) actually renders on screen — those all use
/// gentler, hand-tuned curves for the same reason. So this curve is
/// instead defined by calibration anchors landing exactly on the CLAUDE.md
/// ranges (using their midpoints), piecewise-linear in between. Piecewise
/// linear was chosen over a spline because it is trivial to verify by hand
/// in a unit test and is monotonic by construction — no smoothing library,
/// no risk of overshoot.
enum WarmthCurve {
    struct RGB: Equatable {
        let r: Double
        let g: Double
        let b: Double
    }

    /// (Kelvin, R, G, B), highest Kelvin first. R is 1.0 throughout this
    /// range in every source we compared (blackbody and consumer curves
    /// agree: red saturates well before 1000K).
    private static let anchors: [(k: Double, r: Double, g: Double, b: Double)] = [
        (6500, 1.000, 1.000, 1.000), // neutral, no filter
        (4000, 1.000, 0.850, 0.700), // DAY preset
        (2700, 1.000, 0.750, 0.500), // EVENING preset; midpoint of CLAUDE.md's 0.72–0.78 / 0.45–0.55
        (1900, 1.000, 0.585, 0.250), // midpoint of CLAUDE.md's 0.55–0.62 / 0.20–0.30
        (1000, 1.000, 0.450, 0.080), // boundary before the "below the physics" linear ramp
    ]

    /// - Parameter kelvin: clamped to [0, 6500]. NIGHT preset and the
    ///   slider's bottom stop both use 0 ("0K" — a name, not a physical
    ///   temperature; CLAUDE.md §5.1 `warmth.zero_k.tip`).
    static func rgb(kelvin: Double) -> RGB {
        let k = kelvin.clamped(to: Config.minWarmthK...Config.maxWarmthK)

        guard k > 1000 else {
            // Linear ramp from the 1000K anchor down to pure red at 0K.
            // Green and blue must reach exactly 0 at k=0 (CLAUDE.md §3.2).
            let anchor = anchors.last! // 1000K
            let t = k / 1000.0
            return RGB(r: 1.0, g: anchor.g * t, b: anchor.b * t)
        }

        for i in 0..<(anchors.count - 1) {
            let hi = anchors[i]
            let lo = anchors[i + 1]
            if k <= hi.k && k >= lo.k {
                let t = (k - lo.k) / (hi.k - lo.k) // 0 at lo, 1 at hi
                return RGB(
                    r: 1.0,
                    g: lo.g + (hi.g - lo.g) * t,
                    b: lo.b + (hi.b - lo.b) * t
                )
            }
        }
        // Unreachable given the clamp above and the anchor table's coverage
        // of [1000, 6500]. Code review flagged the old silent
        // `return RGB(1,1,1)` here: if a future edit to `anchors` ever
        // opened a real gap, that fallback would make warmth *look* like it
        // silently turned off (a plausible-looking wrong value) instead of
        // failing loudly. assertionFailure crashes debug/test builds so a
        // gap gets caught immediately; the fallback value only matters if
        // it were ever hit in release, where assertions are compiled out.
        assertionFailure("WarmthCurve.rgb: no anchor pair covers \(k)K — anchors table has a gap")
        return RGB(r: 1, g: 1, b: 1)
    }
}
