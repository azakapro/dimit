import SwiftUI

/// ARCHITECTURE.md §10's settings window. It once also promised a License
/// tab; that tab has no feature behind it any more and never will — the
/// 2026-09-09 distribution decision (CLAUDE.md §4) made every copy
/// unconditional, so there is nothing to activate, manage or deactivate.
/// Schedule joined the window in C5.
struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var displayManager: DisplayManager
    @ObservedObject var pwmSafeCoordinator: PWMSafeCoordinator
    let restoreColours: () -> Void

    var body: some View {
        TabView {
            GeneralSettingsTab(appState: appState)
                .tabItem { Text("settings.tab.general") }

            ScheduleSettingsTab(appState: appState)
                .tabItem { Text("schedule.title") }

            DisplaysSettingsTab(
                appState: appState,
                displayManager: displayManager,
                pwmSafeCoordinator: pwmSafeCoordinator
            )
            .tabItem { Text("settings.tab.displays") }

            AdvancedSettingsTab(
                appState: appState,
                displayManager: displayManager,
                pwmSafeCoordinator: pwmSafeCoordinator,
                restoreColours: restoreColours
            )
            .tabItem { Text("settings.tab.advanced") }
        }
        .frame(width: 520, height: 460)
        // CLAUDE.md §5's language override. Applied at this root (and at
        // the popover's and onboarding's) rather than by relaunching —
        // see AppState.locale's own comment for why that deviates from
        // §5's literal "set Bundle on relaunch" wording.
        .environment(\.locale, appState.effectiveLocale)
    }
}
