import AppKit
import SwiftUI
import XCTest
@testable import Dimit

/// Hosts each C4 view off-screen in every supported language and checks it
/// lays out inside its intended frame — CLAUDE.md §5: "Menu bar / popover
/// must fit 1.4× English string length. Test with Russian, which is
/// longest." This environment can't screenshot popovers or windows above
/// its own pane, so rasterizing the SwiftUI hierarchy directly is the one
/// way to look at these surfaces here. Set `DIMIT_RENDER_DIR` to also
/// write PNGs for eyeballing; otherwise this only asserts on geometry.
@MainActor
final class LayoutRenderTests: XCTestCase {
    private let locales = ["en", "uz", "ru"]

    func test_popover_fitsIn320ptWidth_inEveryLanguage() {
        for locale in locales {
            let state = freshState(locale: locale)
            let view = PopoverView(
                appState: state,
                pwmSafeCoordinator: PWMSafeCoordinator(backends: []),
                openSettings: {}
            )
            .environment(\.locale, Locale(identifier: locale))
            let size = render(view, name: "popover-\(locale)")
            XCTAssertEqual(size.width, 320, accuracy: 0.5, "\(locale): popover must stay at its fixed 320pt width")
            XCTAssertLessThan(size.height, 520, "\(locale): popover grew unreasonably tall — a string is probably wrapping badly")
        }
    }

    func test_settings_fitsItsFixedFrame_inEveryLanguage() {
        for locale in locales {
            let state = freshState(locale: locale)
            let view = SettingsView(
                appState: state,
                displayManager: DisplayManager(),
                pwmSafeCoordinator: PWMSafeCoordinator(backends: []),
                restoreColours: {}
            )
            let size = render(view, name: "settings-\(locale)")
            XCTAssertEqual(size.width, 520, accuracy: 0.5, "\(locale)")
            XCTAssertEqual(size.height, 460, accuracy: 0.5, "\(locale)")
        }
    }

    // The whole-window render above always lands on Settings' first tab
    // (General) — it never actually looks at the Schedule tab's own
    // controls (a segmented mode picker, DatePickers, a DisclosureGroup,
    // a Stepper: several control types not used anywhere else in this
    // codebase yet). Rendered directly, in each of its three modes.
    func test_scheduleTab_fitsAndRenders_inEveryMode_andEveryLanguage() {
        for locale in locales {
            for mode in ScheduleMode.allCases {
                let state = freshState(locale: locale)
                state.scheduleConfig.mode = mode
                if mode == .sunsetToSunrise {
                    state.scheduleConfig.location = Coordinate(latitude: 41.2995, longitude: 69.2401)
                    state.scheduleConfig.selectedCityID = "tashkent"
                }
                let view = ScheduleSettingsTab(appState: state)
                    .environment(\.locale, Locale(identifier: locale))
                    .frame(width: 520)
                let size = render(view, name: "schedule-\(mode.rawValue)-\(locale)")
                XCTAssertGreaterThan(size.height, 0, "\(mode.rawValue)/\(locale): view produced no content")
                // SettingsView's real window is a fixed 520x460, and its
                // TabView reserves roughly 40pt for the tab bar itself,
                // leaving ~420pt of actual content height. An earlier
                // version of this test only checked "&lt; 900" — comfortably
                // true even for content that would need to scroll inside
                // the real window, so it never actually proved the tab
                // fits (an independent review caught the gap, though not
                // a live failure: every mode measures well under the real
                // budget). `Form`/`.formStyle(.grouped)` scrolls
                // gracefully if this ever needs to grow past it, so this
                // is a real ceiling, not a hard crash risk — but a
                // regression here means the tab now needs scrolling to
                // see everything, in the one language (Russian) most
                // likely to hit it first.
                XCTAssertLessThan(size.height, 420, "\(mode.rawValue)/\(locale): exceeds the real Settings window's content height — this tab would now need scrolling")
            }
        }
    }

    // The Displays tab gained C5b's Experimental DDC toggle plus two
    // paragraphs of help text — the longest prose in Settings, and never
    // render-tested before (the whole-window test only ever shows the
    // first tab).
    func test_displaysTab_fitsAndRenders_inEveryLanguage() {
        for locale in locales {
            let state = freshState(locale: locale)
            state.ddcEnabled = true // the expanded state, with help text showing
            let view = DisplaysSettingsTab(
                appState: state,
                displayManager: DisplayManager(),
                pwmSafeCoordinator: PWMSafeCoordinator(backends: [])
            )
            .environment(\.locale, Locale(identifier: locale))
            .frame(width: 520)
            let size = render(view, name: "displays-\(locale)")
            XCTAssertGreaterThan(size.height, 0, "\(locale): produced no content")
            XCTAssertLessThan(size.height, 420, "\(locale): exceeds the real Settings window's content height")
        }
    }

    func test_onboarding_fitsItsFixedFrame_inEveryLanguage() {
        for locale in locales {
            let state = freshState(locale: locale)
            let view = OnboardingView(appState: state, restoreColours: {}, finish: {})
            let size = render(view, name: "onboarding-\(locale)")
            XCTAssertEqual(size.width, 460, accuracy: 0.5, "\(locale)")
            XCTAssertEqual(size.height, 360, accuracy: 0.5, "\(locale)")
        }
    }

    // MARK: - Helpers

    private func freshState(locale: String) -> AppState {
        let state = AppState(persistence: Persistence(suiteName: "test.\(UUID().uuidString)"))
        state.locale = locale
        state.isOn = true
        state.pwmSafe = true
        return state
    }

    /// Returns the hosted view's fitting size; writes a PNG when asked.
    @discardableResult
    private func render<V: View>(_ view: V, name: String) -> CGSize {
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()

        if let dir = ProcessInfo.processInfo.environment["DIMIT_RENDER_DIR"],
           let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
            }
        }
        return size
    }
}
