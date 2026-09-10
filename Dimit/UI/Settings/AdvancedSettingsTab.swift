import AppKit
import SwiftUI

/// ARCHITECTURE.md §10: "Advanced (restore colours, copy diagnostics)."
/// A Fallback-mode toggle lived at the top of this tab from C3 until
/// 2026-09-10, when the owner removed the mode as too confusing.
struct AdvancedSettingsTab: View {
    @ObservedObject var appState: AppState
    @ObservedObject var displayManager: DisplayManager
    @ObservedObject var pwmSafeCoordinator: PWMSafeCoordinator
    let restoreColours: () -> Void

    @State private var didCopyDiagnostics = false

    var body: some View {
        Form {
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
