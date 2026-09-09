import SwiftUI

/// ARCHITECTURE.md §10's settings window, minus the one tab whose feature
/// doesn't exist yet: License (C7). It's omitted rather than shown
/// disabled — an empty tab the user can click into and find nothing in is
/// worse than one that isn't there. Schedule (C5) is no longer in that
/// category as of this cycle.
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
