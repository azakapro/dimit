import AppKit
import KeyboardShortcuts

/// CLAUDE.md §3.9: "Global hotkeys via KeyboardShortcuts: toggle ON/OFF
/// (default ⌃⌥⌘Z), cycle presets, warmth ±, brightness ±." Names live here
/// (not scattered across Settings' recorder views) because
/// `KeyboardShortcuts.Name` values are looked up by this static identity —
/// one definition, referenced from both the recorder UI and the handler
/// registration below.
extension KeyboardShortcuts.Name {
    static let toggleOnOff = Self("toggleOnOff", default: .init(.z, modifiers: [.control, .option, .command]))
    static let cyclePresets = Self("cyclePresets")
    static let warmthUp = Self("warmthUp")
    static let warmthDown = Self("warmthDown")
    static let brightnessUp = Self("brightnessUp")
    static let brightnessDown = Self("brightnessDown")
}

/// Wires each global shortcut to the one `AppState` mutation it performs.
/// Deliberately thin: `KeyboardShortcuts` owns the actual Carbon-level
/// event tap and can't be meaningfully unit-tested without it (there is no
/// fake backend to inject, unlike `BrightnessBackend`), so the *logic* each
/// handler calls (`cycleToNextPreset`, `adjustWarmth`, `adjustBrightness`)
/// lives in `AppState` instead, tested there per CLAUDE.md §12 ("write the
/// test for the pure function it depends on").
///
/// CLAUDE.md §8 "no new permission prompts": `KeyboardShortcuts` registers
/// global hotkeys via Carbon's `RegisterEventHotKey`, which needs no
/// Accessibility/Input Monitoring permission for a plain key-combo listener
/// (only *simulating* input or reading arbitrary keystrokes needs that) —
/// confirmed against the library's own documentation before adding it.
@MainActor
final class HotkeyManager {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState

        KeyboardShortcuts.onKeyUp(for: .toggleOnOff) { [weak appState] in
            appState?.isOn.toggle()
        }
        KeyboardShortcuts.onKeyUp(for: .cyclePresets) { [weak appState] in
            appState?.cycleToNextPreset()
        }
        KeyboardShortcuts.onKeyUp(for: .warmthUp) { [weak appState] in
            appState?.adjustWarmth(by: Config.warmthHotkeyStepK)
        }
        KeyboardShortcuts.onKeyUp(for: .warmthDown) { [weak appState] in
            appState?.adjustWarmth(by: -Config.warmthHotkeyStepK)
        }
        KeyboardShortcuts.onKeyUp(for: .brightnessUp) { [weak appState] in
            appState?.adjustBrightness(by: Config.brightnessHotkeyStep)
        }
        KeyboardShortcuts.onKeyUp(for: .brightnessDown) { [weak appState] in
            appState?.adjustBrightness(by: -Config.brightnessHotkeyStep)
        }
    }
}
