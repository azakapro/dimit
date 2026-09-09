import CoreGraphics

/// Pure gamma-table arithmetic — ARCHITECTURE.md §2.4. No CoreGraphics
/// *calls*, only the `CGGammaValue` (`Float`) type, so this is fully
/// testable without a real display.
enum GammaMath {
    /// One display's captured-at-first-touch gamma table, per channel.
    /// This is the restore baseline: "normal" for that physical display,
    /// captured once and never re-read while a tint might already be
    /// showing (see `GammaController`'s UUID-keyed cache).
    struct Table: Equatable {
        var red: [CGGammaValue]
        var green: [CGGammaValue]
        var blue: [CGGammaValue]
    }

    /// `r[i] = clamp(origR[i] * mulR * dim, 0, 1)`, same for g/b —
    /// ARCHITECTURE.md §2.4, applied index-for-index against the baseline
    /// captured for this specific display (not a fixed-size table: sizes
    /// vary, e.g. 1024 entries on this dev machine's built-in panel).
    static func apply(baseline: Table, multiplier: WarmthCurve.RGB, dim: Double) -> Table {
        Table(
            red: scale(baseline.red, by: multiplier.r * dim),
            green: scale(baseline.green, by: multiplier.g * dim),
            blue: scale(baseline.blue, by: multiplier.b * dim)
        )
    }

    private static func scale(_ channel: [CGGammaValue], by factor: Double) -> [CGGammaValue] {
        channel.map { value in
            CGGammaValue(Double(value) * factor).clamped(to: 0...1)
        }
    }
}
