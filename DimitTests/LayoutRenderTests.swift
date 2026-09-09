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
                XCTAssertLessThan(size.height, 900, "\(mode.rawValue)/\(locale): unreasonably tall — a string is probably wrapping badly or a section is duplicating")
            }
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
