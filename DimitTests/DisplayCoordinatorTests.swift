import Combine
import XCTest
@testable import Dimit

@MainActor
final class DisplayCoordinatorTests: XCTestCase {
    private final class Displays: DisplayProviding {
        @Published var displays = [DisplayInfo(id: 101, uuid: "a", name: "A")]
        var displayUpdates: AnyPublisher<[DisplayInfo], Never> { $displays.eraseToAnyPublisher() }
    }
    private final class Gamma: GammaApplying {
        var applies: [String] = []
        var events: [String] = []
        var succeeds = true
        func apply(_ command: DisplayCommand, uuid: String) -> Bool {
            applies.append(uuid)
            events.append("apply:" + uuid)
            return succeeds
        }
        func restoreAll() { events.append("restore") }
        func evictBaselines(keepingOnly currentUUIDs: Set<String>) {}
    }
    private final class Overlay: OverlayDimming {
        var recreations = 0
        func sync(commands: [DisplayCommand], displays: [DisplayInfo]) {}
        func handleDisplaysChanged() { recreations += 1 }
        func removeAll() {}
    }
    private func drain() {
        let done = expectation(description: "drain main queue")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { done.fulfill() }
        wait(for: [done], timeout: 1)
    }
    private func state() -> AppState {
        let s = AppState(persistence: Persistence(suiteName: "test.\(UUID().uuidString)"))
        s.isOn = true
        s.warmthK = 2700
        return s
    }
    func test_wakeWithIdenticalDisplayList_restoresThenReapplies() {
        let s = state(), d = Displays(), g = Gamma(), o = Overlay()
        let c = DisplayCoordinator(appState: s, displayManager: d, gammaController: g,
            pwmSafeCoordinator: PWMSafeCoordinator(backends: []), overlayDimmer: o)
        drain()
        g.events = []
        d.displays = Array(d.displays) // DisplayManager republishes this on wake.
        drain()
        XCTAssertEqual(g.events, ["restore", "apply:a"])
        withExtendedLifetime(c) {}
    }
    func test_sameUUIDReconfiguration_recreatesOverlay() {
        let s = state(), d = Displays(), g = Gamma(), o = Overlay()
        let c = DisplayCoordinator(appState: s, displayManager: d, gammaController: g,
            pwmSafeCoordinator: PWMSafeCoordinator(backends: []), overlayDimmer: o)
        drain()
        let before = o.recreations
        d.displays = Array(d.displays) // Resolution/arrangement can change without DisplayInfo changing.
        drain()
        XCTAssertEqual(o.recreations, before + 1)
        withExtendedLifetime(c) {}
    }
    func test_reusedDisplayID_newUUID_isAppliedAfterRestore() {
        let s = state(), d = Displays(), g = Gamma(), o = Overlay()
        let c = DisplayCoordinator(appState: s, displayManager: d, gammaController: g,
            pwmSafeCoordinator: PWMSafeCoordinator(backends: []), overlayDimmer: o)
        drain()
        g.events = []
        d.displays = [DisplayInfo(id: 101, uuid: "b", name: "B")]
        drain()
        XCTAssertEqual(g.events, ["restore", "apply:b"])
        withExtendedLifetime(c) {}
    }
    func test_firstApplyFailure_isRetriedOnNextStateChange() {
        let s = state(), d = Displays(), g = Gamma(), o = Overlay()
        g.succeeds = false
        let c = DisplayCoordinator(appState: s, displayManager: d, gammaController: g,
            pwmSafeCoordinator: PWMSafeCoordinator(backends: []), overlayDimmer: o)
        drain()
        g.applies = []
        g.succeeds = true
        s.locale = "ru" // another pipeline pass, same desired gamma
        drain()
        XCTAssertEqual(g.applies, ["a"])
        withExtendedLifetime(c) {}
    }
}
