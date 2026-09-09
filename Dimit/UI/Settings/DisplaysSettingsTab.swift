import SwiftUI

/// ARCHITECTURE.md §10: "Displays (per-display list with backend name and
/// DDC experimental toggle)." The DDC toggle itself is out of scope for
/// C4 (docs/PLAN.md: "Out: DDC" — `DDCController` is still C3's permanent
/// stub until C5 actually implements it), so this shows the per-display
/// list and real backend names only; the toggle arrives with C5's real
/// `DDCController`.
struct DisplaysSettingsTab: View {
    @ObservedObject var appState: AppState
    @ObservedObject var displayManager: DisplayManager
    @ObservedObject var pwmSafeCoordinator: PWMSafeCoordinator

    var body: some View {
        Form {
            Section {
                ForEach(displayManager.displays) { display in
                    DisplayRow(appState: appState, display: display, backendName: pwmSafeCoordinator.backendName(for: display))
                }
            }

            // C5b/CLAUDE.md §3.4: "Ships in 1.0 as an Experimental toggle
            // in Settings (`Config.ddcEnabled`, default OFF); promoted to
            // default ON in 1.1 after a second monitor and beta feedback."
            Section {
                Toggle(isOn: $appState.ddcEnabled) {
                    Text("settings.ddc_experimental")
                }
                Text("settings.ddc_help")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("settings.ddc_single_display_only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

private struct DisplayRow: View {
    @ObservedObject var appState: AppState
    let display: DisplayInfo
    let backendName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(display.name).bold()
                if display.isBuiltin {
                    Tag(text: "settings.display_builtin")
                }
                if display.isAppleDisplay {
                    Tag(text: "settings.display_apple")
                }
            }
            Text(backendLine)
                .font(.caption)
                .foregroundStyle(backendName == nil ? .orange : .secondary)
        }
        .padding(.vertical, 2)
    }

    private var backendLine: String {
        guard let backendName else {
            return appState.localized("settings.display_no_backend")
        }
        return appState.localized("settings.display_backend", backendName)
    }
}

private struct Tag: View {
    let text: LocalizedStringResource

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.secondary.opacity(0.15), in: Capsule())
    }
}
