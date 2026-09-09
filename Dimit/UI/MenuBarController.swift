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
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
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

        let toggleTitleKey: LocalizedStringResource = appState.isOn ? "main.off" : "main.on"
        let toggleItem = NSMenuItem(
            title: String(localized: toggleTitleKey),
            action: #selector(toggleOnOff),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

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

        // Attach-click-detach so the next left-click still opens the
        // popover instead of the menu (the standard idiom for a status
        // item that shows different UI per click button).
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? PresetID else { return }
        appState.apply(preset: preset)
    }

    @objc private func toggleOnOff() {
        appState.isOn.toggle()
    }
}
