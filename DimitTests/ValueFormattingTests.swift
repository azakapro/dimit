import XCTest
@testable import Dimit

final class ValueFormattingTests: XCTestCase {
    // CLAUDE.md §5: "6500 K" with a space in UZ/RU, "6500K" in EN.
    func test_warmth_englishHasNoSpace_uzbekAndRussianHaveOne() {
        XCTAssertEqual(ValueFormatting.warmth(6500, locale: Locale(identifier: "en")), "6500K")
        XCTAssertEqual(ValueFormatting.warmth(6500, locale: Locale(identifier: "uz")), "6500 K")
        XCTAssertEqual(ValueFormatting.warmth(6500, locale: Locale(identifier: "ru")), "6500 K")
    }

    // The preset editor used to show "4,000K" (en) / "4 000K" (ru) via
    // SwiftUI's locale-aware integer interpolation while the popover showed
    // "4000K" / "4000 K" — pins that no locale gets a grouping separator.
    func test_warmth_neverUsesAGroupingSeparator() {
        for id in ["en", "uz", "ru", "en_US", "ru_RU", "de_DE"] {
            let text = ValueFormatting.warmth(4000, locale: Locale(identifier: id))
            XCTAssertFalse(text.contains(","), id)
            XCTAssertTrue(text.hasPrefix("4000"), "\(id): got \(text)")
        }
    }

    func test_warmth_roundsToWholeKelvin() {
        XCTAssertEqual(ValueFormatting.warmth(2699.6, locale: Locale(identifier: "en")), "2700K")
    }

    func test_brightness_isWholePercent() {
        XCTAssertEqual(ValueFormatting.brightness(1.0), "100%")
        XCTAssertEqual(ValueFormatting.brightness(0.4), "40%")
        XCTAssertEqual(ValueFormatting.brightness(0.104), "10%")
    }
}
