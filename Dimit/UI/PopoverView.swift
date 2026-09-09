import SwiftUI

/// CLAUDE.md §1: "Two sliders, three presets, one button. Anything else
/// lives behind a Settings gear." ARCHITECTURE.md §10 has the fuller visual
/// spec (gradients, segmented control, PWM row help text); this pass gets
/// the structure and every string wired to the catalog, plain system
/// controls throughout. Custom styling is polish for a later cycle, not a
/// blocker for a working app.
struct PopoverView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var pwmSafeCoordinator: PWMSafeCoordinator
    // @Environment, not Locale.current: Locale.current ignores a
    // .environment(\.locale, ...) override, which is both how SwiftUI
    // previews/tests switch locale and how C4's in-app language override
    // will need to work (CLAUDE.md §5: "Settings has a language override").
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if appState.showAutoBrightnessBanner {
                autoBrightnessBanner
            }
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

    // CLAUDE.md §3.3: shown once, ever, the first time the filter turns ON
    // on macOS ≥ 26 (no reliable detection key exists for auto-brightness
    // itself — see AppState.swift's comment).
    private var autoBrightnessBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("banner.autobrightness")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("banner.open_settings")
                        .font(.caption.bold())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                Spacer()
                Button {
                    appState.dismissAutoBrightnessBanner()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("banner.dismiss"))
            }
        }
        .padding(10)
        .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
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
        // Reads as "Dimit, ON, button" rather than the bare "OFF, button, ON"
        // an earlier hint produced (label, trait, then a lone contradictory
        // word). Uses only strings already in the catalog; proper
        // action-phrase hints ("Turns the filter off") need new UZ/RU
        // translations and belong with C4's full VoiceOver pass.
        .accessibilityLabel(Text("app.name"))
        .accessibilityValue(Text(appState.isOn ? "main.on" : "main.off"))
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
            // CLAUDE.md §8 quality bar: "VoiceOver labels for both sliders."
            // Without an explicit label a bare Slider announces only its
            // value ("6500K") with no indication of *what* it controls —
            // the visible Text above it is a separate a11y element.
            Slider(value: $appState.warmthK, in: Config.minWarmthK...Config.maxWarmthK, step: 100)
                .accessibilityLabel(Text("main.warmth"))
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
                .accessibilityLabel(Text("main.brightness"))
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
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $appState.pwmSafe) {
                Text("main.pwm_safe")
            }
            .help(Text("main.pwm_safe.help"))

            if appState.pwmSafe, let status = pwmStatusText {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(pwmStatusIsWarning ? .orange : .secondary)
            }
        }
    }

    // Maps PWMSafeCoordinator.summaryState to the catalog strings CLAUDE.md
    // §5.1 already defines for each state. `.pinned` shows the battery
    // note (CLAUDE.md §3.6) rather than a redundant "it's on" message —
    // the toggle itself and the (in this build, placeholder) menu-bar dot
    // already say that.
    private var pwmStatusText: LocalizedStringResource? {
        switch pwmSafeCoordinator.summaryState {
        case .pinning: return "pwm.waiting"
        case .wontHold: return "pwm.wont_hold"
        case .unsupported: return "pwm.unsupported"
        case .pinned: return "main.pwm_safe.help" // doubles as the battery note
        case .off, nil: return nil
        }
    }

    private var pwmStatusIsWarning: Bool {
        switch pwmSafeCoordinator.summaryState {
        case .wontHold, .unsupported: return true
        default: return false
        }
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
    PopoverView(appState: AppState(), pwmSafeCoordinator: PWMSafeCoordinator(backends: []))
}
