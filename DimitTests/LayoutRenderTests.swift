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
