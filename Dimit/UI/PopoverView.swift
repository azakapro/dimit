import SwiftUI

/// CLAUDE.md §1: "Two sliders, three presets, one button. Anything else
/// lives behind a Settings gear." ARCHITECTURE.md §10 has the fuller visual
/// spec (gradients, segmented control, PWM row help text); this C1 pass
/// gets the structure and every string wired to the catalog, plain
/// system controls throughout. Custom styling is polish for a later cycle,
/// not a blocker for a working skeleton.
struct PopoverView: View {
    @ObservedObject var appState: AppState
    // @Environment, not Locale.current: Locale.current ignores a
    // .environment(\.locale, ...) override, which is both how SwiftUI
    // previews/tests switch locale and how C4's in-app language override
    // will need to work (CLAUDE.md §5: "Settings has a language override").
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            onOffButton
            warmthRow
            brightnessRow
            presetPicker
            pwmSafeRow
        }
        .padding(16)
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Text("app.name")
                .font(.headline)
            Spacer()
            Button {
                // Settings window arrives in C4.
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .disabled(true)
            .accessibilityLabel(Text("settings.title"))
        }
    }

    private var onOffButton: some View {
        Button {
            appState.isOn.toggle()
        } label: {
            // Label shows CURRENT state, matching the tint below (orange
            // when on) — code review on C1 caught this inverted (label said
            // "OFF" on an orange, active-looking button while isOn was
            // true). The accessibility hint below correctly describes the
            // opposite word: what activating the button will change it TO.
            Text(appState.isOn ? "main.on" : "main.off")
                .font(.title2.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(appState.isOn ? .orange : .secondary)
        .accessibilityHint(Text(appState.isOn ? "main.off" : "main.on"))
    }

    private var warmthRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("main.warmth")
                Spacer()
                Text(formattedWarmth)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $appState.warmthK, in: Config.minWarmthK...Config.maxWarmthK, step: 100)
                .accessibilityValue(Text(formattedWarmth))
        }
    }

    private var brightnessRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("main.brightness")
                Spacer()
                Text(formattedBrightness)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $appState.brightness, in: Config.minBrightness...Config.maxBrightness)
                .accessibilityValue(Text(formattedBrightness))
        }
    }

    private var presetPicker: some View {
        Picker("", selection: presetBinding) {
            ForEach(PresetID.allCases, id: \.self) { preset in
                Text(preset.titleKey).tag(Optional(preset))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var presetBinding: Binding<PresetID?> {
        Binding(
            get: { appState.activePreset },
            set: { newValue in
                guard let preset = newValue else { return }
                appState.apply(preset: preset)
            }
        )
    }

    private var pwmSafeRow: some View {
        Toggle(isOn: $appState.pwmSafe) {
            Text("main.pwm_safe")
        }
        // The real pin/verify/retry state machine is C3's PWMSafeCoordinator.
        // Disabled here so the toggle can't lie about a mode that doesn't
        // do anything yet.
        .disabled(true)
        .help(Text("main.pwm_safe.help"))
    }

    // CLAUDE.md §5: "6500 K" with a space in UZ/RU, "6500K" in EN.
    private var formattedWarmth: String {
        let value = Int(appState.warmthK)
        let isEnglish = locale.language.languageCode?.identifier == "en"
        return isEnglish ? "\(value)K" : "\(value) K"
    }

    private var formattedBrightness: String {
        "\(Int((appState.brightness * 100).rounded()))%"
    }
}

#Preview {
    PopoverView(appState: AppState())
}
