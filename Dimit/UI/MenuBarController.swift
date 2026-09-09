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
    private let restoreColours: () -> Void
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState, restoreColours: @escaping () -> Void) {
        self.appState = appState
        self.restoreColours = restoreColours
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.popover = NSPopover()
        super.init()

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView(appState: appState))

        if let button = statusItem.button {
            button.image = MenuBarIcon.image(isOn: appState.isOn)
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        appState.$isOn
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isOn in
                self?.statusItem.button?.image = MenuBarIcon.image(isOn: isOn)
            }
            .store(in: &cancellables)
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

        for preset in PresetID.allCases {
            let item = NSMenuItem(
                title: String(localized: preset.titleKey),
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
            title: String(localized: toggleTitleKey),
            action: #selector(toggleOnOff),
            keyEquivalent: ""
        )
        toggleItem.target = self
        toggleItem.state = appState.isOn ? .on : .off
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        // CLAUDE.md §3.3 / onboarding: a manual "restore colours" safety
        // valve, independent of the ON/OFF state — useful if a gamma
        // read-back mismatch or any other display weirdness leaves the
        // screen looking wrong. C2's new string; see Resources/Localizable.xcstrings.
        let restoreItem = NSMenuItem(
            title: String(localized: "menu.restore_colours"),
            action: #selector(restoreColoursClicked),
            keyEquivalent: ""
        )
        restoreItem.target = self
        menu.addItem(restoreItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: String(localized: "menu.settings"),
            action: nil, // C4
            keyEquivalent: ""
        )
        settingsItem.isEnabled = false
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(
            title: String(localized: "menu.quit"),
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
}
