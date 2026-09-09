import XCTest
@testable import Dimit

final class DiagnosticsBundleTests: XCTestCase {
    func test_buildText_includesTheBasicFacts() {
        let text = DiagnosticsBundle.buildText(
            appVersion: "0.2 (1)",
            macOSVersion: "Version 27.0 (Build 26A5416b)",
            hardwareModel: "MacBookPro18,1",
            displays: [],
            recentLogLines: []
        )
        XCTAssertTrue(text.contains("0.2 (1)"))
        XCTAssertTrue(text.contains("27.0"))
        XCTAssertTrue(text.contains("MacBookPro18,1"))
    }

    func test_buildText_listsEachDisplayWithItsTagsAndBackend() {
        let displays = [
            DiagnosticsBundle.DisplayEntry(
                name: "Built-in Retina Display",
                isBuiltin: true,
                isAppleDisplay: true,
                supportsDDC: false,
                brightnessBackend: "DisplayServices"
            ),
            DiagnosticsBundle.DisplayEntry(
                name: "Dell U2720Q",
                isBuiltin: false,
                isAppleDisplay: false,
                supportsDDC: false,
                brightnessBackend: nil
            ),
        ]
        let text = DiagnosticsBundle.buildText(
            appVersion: "0.2 (1)", macOSVersion: "27.0", hardwareModel: "MacBookPro18,1",
            displays: displays, recentLogLines: []
        )

        XCTAssertTrue(text.contains("Displays (2):"))
        XCTAssertTrue(text.contains("Built-in Retina Display"))
        XCTAssertTrue(text.contains("built-in"))
        XCTAssertTrue(text.contains("Apple display"))
        XCTAssertTrue(text.contains("DisplayServices"))
        XCTAssertTrue(text.contains("Dell U2720Q"))
        // No backend -> "none", not a blank or a crash on the optional.
        XCTAssertTrue(text.contains("brightness backend: none"))
    }

    func test_buildText_withNoDisplays_saysSoRatherThanShowingAnEmptySection() {
        let text = DiagnosticsBundle.buildText(
            appVersion: "0.2 (1)", macOSVersion: "27.0", hardwareModel: "Mac14,9",
            displays: [], recentLogLines: []
        )
        XCTAssertTrue(text.contains("(none enumerated)"))
    }

    // An earlier draft of CLAUDE.md §7 asked for a "license state" line.
    // There is no licensing and never will be (CLAUDE.md §4: every copy is
    // unconditional), so the bundle must say nothing about it rather than
    // carry a placeholder describing behavior that doesn't exist.
    func test_buildText_mentionsNoLicenseState() {
        let text = DiagnosticsBundle.buildText(
            appVersion: "0.2 (1)", macOSVersion: "27.0", hardwareModel: "Mac14,9",
            displays: [], recentLogLines: []
        )
        XCTAssertFalse(text.lowercased().contains("licens"))
    }

    func test_buildText_includesLogLinesInOrder() {
        let lines = ["10:00:00 first", "10:00:01 second"]
        let text = DiagnosticsBundle.buildText(
            appVersion: "0.2 (1)", macOSVersion: "27.0", hardwareModel: "Mac14,9",
            displays: [], recentLogLines: lines
        )
        XCTAssertTrue(text.contains("Log (last 2 lines):"))
        let firstRange = text.range(of: "first")
        let secondRange = text.range(of: "second")
        XCTAssertNotNil(firstRange)
        XCTAssertNotNil(secondRange)
        XCTAssertTrue(firstRange!.lowerBound < secondRange!.lowerBound, "log lines must stay in chronological order")
    }

    // The one test here that touches the real machine: `current()` wires
    // the live DisplayManager and the real backend list together. Asserts
    // only on structure that holds on any Mac with at least one display,
    // not on this machine's specific hardware.
    @MainActor
    func test_current_assemblesRealDisplaysAndLog() {
        let displayManager = DisplayManager()
        let coordinator = PWMSafeCoordinator(backends: [DisplayServicesBackend(), CoreDisplayBackend(), DDCBackend()])
        Log.app.info("DiagnosticsBundleTests marker line")

        let text = DiagnosticsBundle.current(displayManager: displayManager, pwmSafeCoordinator: coordinator)

        XCTAssertTrue(text.hasPrefix("Dimit diagnostics"))
        XCTAssertTrue(text.contains("Hardware: "))
        XCTAssertTrue(text.contains("Displays (\(displayManager.displays.count)):"))
        for display in displayManager.displays {
            XCTAssertTrue(text.contains(display.name), "every enumerated display should be listed")
        }
        XCTAssertTrue(text.contains("Log (last "))
    }

    // CLAUDE.md §4.2: the bundle carries nothing that identifies anyone.
    // The user pastes this text into a support message, so anything that
    // looks like a credential must never reach it — kept as a literal
    // search because the point is the *output*, not any type in the code.
    func test_buildText_neverContainsAnythingThatLooksLikeACredential() {
        let text = DiagnosticsBundle.buildText(
            appVersion: "0.2 (1)", macOSVersion: "27.0", hardwareModel: "Mac14,9",
            displays: [], recentLogLines: ["a normal log line"]
        )
        XCTAssertFalse(text.contains("DIMT-"))
    }
}
