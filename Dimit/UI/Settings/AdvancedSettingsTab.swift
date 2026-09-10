import AppKit
import SwiftUI

/// ARCHITECTURE.md §10: "Advanced (Fallback mode, restore colours, copy
/// diagnostics)."
///
/// Fallback mode also stays in the right-click menu where C3 put it. Two
/// paths to one `appState.fallbackMode` binding can't diverge (there is no
/// second copy of the value), and the menu item is the one that still works
/// when the thing the user needs to fix is *the screen being unreadable* —
/// which is exactly when Fallback mode matters and exactly when hunting for
/// a Settings tab is hardest.
struct AdvancedSettingsTab: View {
    @ObservedObject var appState: AppState
    @ObservedObject var displayManager: DisplayManager
    @ObservedObject var pwmSafeCoordinator: PWMSafeCoordinator
    let restoreColours: () -> Void

    @State private var didCopyDiagnostics = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $appState.fallbackMode) {
                    Text("fallback.title")
                }
                Text("fallback.help")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // Fallback mode changes *how* the screen is tinted, not
                // whether it is — so switching it on while Dimit is off does
                // nothing visible at all. The owner did exactly that and
                // reported the feature as broken; it wasn't (verified on
                // hardware: with the filter on it puts a real overlay at
                // window level 1001, alpha 0.70, and leaves gamma neutral).
                // Nothing on screen said the filter had to be on, so this
                // does, and only when it applies.
                if appState.fallbackMode, !appState.isOn {
                    Text("fallback.needs_on")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                Button {
                    restoreColours()
                } label: {
                    Text("menu.restore_colours")
                }

                HStack {
                    Button {
                        copyDiagnostics()
                    } label: {
                        Text("settings.copy_diag")
                    }
                    if didCopyDiagnostics {
                        Text("settings.diagnostics_copied")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func copyDiagnostics() {
        let text = DiagnosticsBundle.current(
            displayManager: displayManager,
            pwmSafeCoordinator: pwmSafeCoordinator
        )
        // CLAUDE.md §7: "Copied to clipboard as text." clearContents() is
        // required before setString — NSPasteboard keeps the previous
        // owner's data otherwise and the write silently no-ops.
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        withAnimation { didCopyDiagnostics = true }
        // Confirmation is transient: leaving "copied" on screen forever
        // makes it ambiguous whether a *later* click did anything.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { didCopyDiagnostics = false }
        }
    }
}
