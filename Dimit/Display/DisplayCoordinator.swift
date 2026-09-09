import Combine
import CoreGraphics

/// The apply pipeline — ARCHITECTURE.md §2.1. Owns nothing about *how* to
/// enumerate displays or touch gamma (that's `DisplayManager` /
/// `GammaController`); this just wires "something changed" to
/// "render, diff, apply."
///
/// Subscribes to `appState.objectWillChange` rather than each individual
/// `@Published` property: `objectWillChange` fires in `willSet`, before the
/// new value is stored, so reading `appState.renderState` *inside* a
/// synchronous sink would see the *old* value. `.receive(on: .main)`
/// defers the read to the next run-loop turn, by which point the
/// synchronous write has long since completed. This also means a single
/// user action that sets several `@Published` fields in a row (e.g.
/// `AppState.apply(preset:)` setting `warmthK`, then `brightness`, then
/// `activePreset`) can trigger this pipeline more than once — Applier's
/// diff makes every call after the first a no-op once state has settled,
/// so this doesn't cost extra `CGSetDisplayTransferByTable` calls, only a
/// few redundant (cheap) `Renderer.render` calls.
@MainActor
final class DisplayCoordinator {
    private let appState: AppState
    private let displayManager: DisplayManager
    private let gammaController: GammaController

    private var lastApplied: [DisplayCommand] = []
    private var knownUUIDs: Set<String> = []
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState, displayManager: DisplayManager, gammaController: GammaController) {
        self.appState = appState
        self.displayManager = displayManager
        self.gammaController = gammaController

        appState.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reapply() }
            .store(in: &cancellables)

        displayManager.$displays
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reapply() }
            .store(in: &cancellables)

        // Apply once for whatever state was already loaded at launch (e.g.
        // isOn restored true from a previous session) rather than waiting
        // for the first change.
        reapply()
    }

    private func reapply() {
        let displays = displayManager.displays
        evictBaselinesForDisconnectedDisplays(currentlyConnected: displays)

        let uuidByID = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0.uuid) })
        let commands = Renderer.render(appState.renderState, displays: displays)
        let diff = Applier.diff(previous: lastApplied, current: commands)

        for command in diff.toApply {
            guard let uuid = uuidByID[command.displayID] else { continue }
            gammaController.apply(command, uuid: uuid)
        }
        if !diff.toRestore.isEmpty {
            gammaController.restoreAll()
        }

        lastApplied = commands
    }

    private func evictBaselinesForDisconnectedDisplays(currentlyConnected: [DisplayInfo]) {
        let currentUUIDs = Set(currentlyConnected.map(\.uuid))
        for goneUUID in knownUUIDs.subtracting(currentUUIDs) {
            gammaController.dropBaseline(uuid: goneUUID)
        }
        knownUUIDs = currentUUIDs
    }

    /// The right-click menu's "Restore colours" — a manual safety valve,
    /// independent of `isOn` (CLAUDE.md's onboarding also gets one "for
    /// safety"). Turns the filter off *and* forces an immediate restore,
    /// rather than only flipping `isOn` and waiting for the async
    /// `objectWillChange` hop: this is explicitly a panic button, so it
    /// shouldn't depend on the normal pipeline's timing to take effect.
    func restoreColours() {
        appState.isOn = false
        gammaController.restoreAll()
    }
}
