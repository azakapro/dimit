import AppKit
import Combine
import SwiftUI

/// Owns the status item, the left-click popover and the right-click menu.
/// CLAUDE.md §3.9: "Left-click opens the popover; right-click shows a
/// context menu (presets, toggle, settings, quit)."
@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let appState: AppState
    private let pwmSafeCoordinator: PWMSafeCoordinator
    private let restoreColours: () -> Void
    private let openSettings: () -> Void
    /// C7/ARCHITECTURE.md §4. `canCheckForUpdates` false greys the "Check
    /// for Updates…" item (Sparkle refuses a second concurrent check).
    /// Evaluated when the menu is built, which is every right-click.
    /// Required, like `restoreColours`/`openSettings`: a caller that forgets
    /// to wire updates should fail to compile, not ship a dead item.
    private let checkForUpdates: () -> Void
    private let canCheckForUpdates: () -> Bool
    private var cancellables = Set<AnyCancellable>()

    init(
        appState: AppState,
        pwmSafeCoordinator: PWMSafeCoordinator,
        restoreColours: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        checkForUpdates: @escaping () -> Void,
        canCheckForUpdates: @escaping () -> Bool
    ) {
        self.appState = appState
        self.pwmSafeCoordinator = pwmSafeCoordinator
        self.restoreColours = restoreColours
        self.openSettings = openSettings
        self.checkForUpdates = checkForUpdates
        self.canCheckForUpdates = canCheckForUpdates
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.popover = NSPopover()
        super.init()

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverRoot(
                appState: appState,
                pwmSafeCoordinator: pwmSafeCoordinator,
                openSettings: { [weak self] in
                    // Close the transient popover first — otherwise the
                    // Settings window opens behind it and the popover's
                    // click-outside dismissal fights the window activation.
                    self?.popover.performClose(nil)
                    self?.openSettings()
                }
            )
        )

        if let button = statusItem.button {
            button.image = MenuBarIcon.image(isOn: appState.isOn, pwmPinned: pwmSafeCoordinator.summaryState == .pinned,
                                    accessibilityDescription: appState.localized(appState.isOn ? "main.on" : "main.off"))
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        appState.$isOn
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)

        pwmSafeCoordinator.$states
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)

        // CLAUDE.md §3.6: "show 'PWM-Safe re-pinned brightness to 100%...'
        // once per session" — PWMSafeCoordinator decides *when* (once,
        // ever, per launch); this just decides *how* to show it.
        pwmSafeCoordinator.repinnedToastSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                ToastPresenter.show(self.appState.localized("pwm.repinned"), near: self.statusItem.button)
            }
            .store(in: &cancellables)
    }

    private func updateIcon() {
        statusItem.button?.image = MenuBarIcon.image(isOn: appState.isOn, pwmPinned: pwmSafeCoordinator.summaryState == .pinned,
                                    accessibilityDescription: appState.localized(appState.isOn ? "main.on" : "main.off"))
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Accessory (LSUIElement) apps don't automatically become the
            // active app just because their status item was clicked in
            // every hosting environment; without this the popover can be
            // marked `isShown` internally while never actually gaining key
            // window status. Standard practice for status-item popovers.
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        // Every item below sets its own enabled state explicitly. With the
        // default `autoenablesItems`, NSMenu re-derives enablement from
        // target validation when the menu pops up and silently overrides
        // `isEnabled` — which made the updates item's greying dead code
        // until a C7 review caught it. The items are enabled by default,
        // so only the one that ever needs greying has to say so.
        menu.autoenablesItems = false

        for preset in PresetID.allCases {
            let item = NSMenuItem(
                title: appState.localized(preset.titleKey),
                action: #selector(selectPreset(_:)),
                keyEquivalent: ""
            )
            item.representedObject = preset
            item.target = self
            item.state = (appState.activePreset == preset) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // Shows current state (checked = on), matching the popover button
        // fixed in code review rather than an action-phrased "Turn Off" —
        // `main.on`/`main.off` are bare state words in the catalog, and one
        // consistent meaning for them everywhere is simpler to keep correct
        // than a per-surface convention.
        let toggleTitleKey: LocalizedStringResource = appState.isOn ? "main.on" : "main.off"
        let toggleItem = NSMenuItem(
            title: appState.localized(toggleTitleKey),
            action: #selector(toggleOnOff),
            keyEquivalent: ""
        )
        toggleItem.target = self
        toggleItem.state = appState.isOn ? .on : .off
        menu.addItem(toggleItem)

        // CLAUDE.md §3.3 / onboarding: a manual "restore colours" safety
        // valve, independent of the ON/OFF state — useful if a gamma
        // read-back mismatch or any other display weirdness leaves the
        // screen looking wrong.
        let restoreItem = NSMenuItem(
            title: appState.localized("menu.restore_colours"),
            action: #selector(restoreColoursClicked),
            keyEquivalent: ""
        )
        restoreItem.target = self
        menu.addItem(restoreItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: appState.localized("menu.settings"),
            action: #selector(settingsClicked),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        // C7: a user-initiated check is allowed whatever the automatic
        // opt-in says (CLAUDE.md §4.3) — the user clicking is the consent.
        let updatesItem = NSMenuItem(
            title: appState.localized("menu.check_updates"),
            action: #selector(checkForUpdatesClicked),
            keyEquivalent: ""
        )
        updatesItem.target = self
        updatesItem.isEnabled = canCheckForUpdates()
        menu.addItem(updatesItem)

        let quitItem = NSMenuItem(
            title: appState.localized("menu.quit"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        // popUp(positioning:at:in:) shows the menu directly without ever
        // touching statusItem.menu — code review on C1 pointed out the
        // previous attach/click/detach approach (set statusItem.menu, call
        // performClick to force it open, then clear statusItem.menu again)
        // worked, but only by relying on an undocumented ordering between
        // NSStatusItem.menu and NSButton.performClick rather than a menu
        // API meant for exactly this.
        guard let button = statusItem.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? PresetID else { return }
        appState.apply(preset: preset)
    }

    @objc private func toggleOnOff() {
        appState.isOn.toggle()
    }

    @objc private func restoreColoursClicked() {
        restoreColours()
    }

    @objc private func settingsClicked() {
        openSettings()
    }

    @objc private func checkForUpdatesClicked() {
        checkForUpdates()
    }
}

/// Wraps `PopoverView` so the language override reaches it. `PopoverView`
/// reads `@Environment(\.locale)` itself (for the "6500K" vs "6500 K"
/// formatting), and a view can't see an environment value it sets on its
/// own body — the override has to be applied one level up, here.
private struct PopoverRoot: View {
    @ObservedObject var appState: AppState
    @ObservedObject var pwmSafeCoordinator: PWMSafeCoordinator
    let openSettings: () -> Void

    var body: some View {
        PopoverView(appState: appState, pwmSafeCoordinator: pwmSafeCoordinator, openSettings: openSettings)
            .environment(\.locale, appState.effectiveLocale)
    }
}
