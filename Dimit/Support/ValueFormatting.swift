import Foundation

/// The one place the two slider values are turned into text — the popover,
/// the preset editor, and anything later (a status pill, a menu item) must
/// agree. CLAUDE.md §5: "6500 K" with a space in UZ/RU, "6500K" in EN. No
/// grouping separator in any language: SwiftUI's `Text("\(Int)")` would
/// otherwise render "4,000K" / "4 000K", which was exactly what the preset
/// editor showed before this helper existed and the popover didn't — two
/// formats for the same number on screen at once.
enum ValueFormatting {
    static func warmth(_ kelvin: Double, locale: Locale) -> String {
        let value = Int(kelvin.rounded())
        let isEnglish = locale.language.languageCode?.identifier == "en"
        return isEnglish ? "\(value)K" : "\(value) K"
    }

    static func brightness(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}
