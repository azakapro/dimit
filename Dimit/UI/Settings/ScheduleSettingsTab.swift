import SwiftUI

/// ARCHITECTURE.md §10 / CLAUDE.md §3.8. The tab C4 explicitly omitted
/// ("Schedule tab in Settings" arrives with C5) now exists.
struct ScheduleSettingsTab: View {
    @ObservedObject var appState: AppState

    // Lazy, not eagerly constructed: this view rebuilds on every AppState
    // change (including every schedule tick's own writes), and a plain
    // `= LocationProvider()` default would allocate a fresh
    // CLLocationManager on each rebuild only to discard it — SwiftUI keeps
    // just the first result. Created once, on first actual use, in
    // requestLocation() below.
    @State private var locationProvider: LocationProvider?
    @State private var locationMessage: String?
    @State private var manualLatitudeText = ""
    @State private var manualLongitudeText = ""
    // True while a one-shot CoreLocation request is outstanding — disables
    // the button so a slow permission dialog or GPS fix can't be
    // double-clicked into two overlapping requests, the second of which
    // would silently replace `LocationProvider`'s single stored completion
    // and drop the first click's result forever (found by an independent
    // review).
    @State private var isRequestingLocation = false

    var body: some View {
        Form {
            Section {
                Picker(selection: $appState.scheduleConfig.mode) {
                    Text("schedule.manual").tag(ScheduleMode.manual)
                    Text("schedule.sun").tag(ScheduleMode.sunsetToSunrise)
                    Text("schedule.fixed").tag(ScheduleMode.fixedTimes)
                } label: {
                    Text("schedule.mode_title")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            switch appState.scheduleConfig.mode {
            case .manual:
                EmptyView()
            case .sunsetToSunrise:
                locationSection
                timeSection(title: "schedule.bedtime", binding: $appState.scheduleConfig.bedtime)
                rampSection
            case .fixedTimes:
                timeSection(title: "schedule.fixed_day_start", binding: $appState.scheduleConfig.fixedDayStart)
                timeSection(title: "schedule.fixed_evening_start", binding: $appState.scheduleConfig.fixedEveningStart)
                timeSection(title: "schedule.bedtime", binding: $appState.scheduleConfig.bedtime)
                rampSection
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Sunset -> Sunrise: location

    @ViewBuilder
    private var locationSection: some View {
        Section {
            HStack {
                Button {
                    requestLocation()
                } label: {
                    Text("schedule.use_location")
                }
                .disabled(isRequestingLocation)
                if let locationMessage {
                    Text(locationMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Picker(selection: cityBinding) {
                Text("schedule.location_none").tag(Optional<String>.none)
                ForEach(CityList.all) { city in
                    Text(city.titleKey).tag(Optional(city.id))
                }
            } label: {
                Text("schedule.city")
            }

            DisclosureGroup {
                HStack {
                    TextField("schedule.latitude", text: $manualLatitudeText)
                        .accessibilityLabel(Text("schedule.latitude"))
                    TextField("schedule.longitude", text: $manualLongitudeText)
                        .accessibilityLabel(Text("schedule.longitude"))
                    Button {
                        applyManualCoordinates()
                    } label: {
                        Text("schedule.apply_coordinates")
                    }
                    .disabled(!manualCoordinatesAreValid)
                }
            } label: {
                Text("schedule.manual_coordinates")
            }

            Text(currentLocationDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var cityBinding: Binding<String?> {
        Binding(
            get: { appState.scheduleConfig.selectedCityID },
            set: { newID in
                guard let newID, let city = CityList.city(id: newID) else {
                    appState.scheduleConfig.selectedCityID = nil
                    return
                }
                appState.scheduleConfig.selectedCityID = newID
                appState.scheduleConfig.location = city.coordinate
                locationMessage = nil
            }
        )
    }

    private var currentLocationDescription: String {
        if let cityID = appState.scheduleConfig.selectedCityID, let city = CityList.city(id: cityID) {
            return appState.localized("schedule.location_using_city", appState.localized(city.titleKey))
        }
        if appState.scheduleConfig.location != nil {
            return appState.localized("schedule.location_using_coordinates")
        }
        return appState.localized("schedule.location_none")
    }

    private func requestLocation() {
        locationMessage = nil
        isRequestingLocation = true
        let provider = locationProvider ?? LocationProvider()
        locationProvider = provider
        provider.requestOneTimeLocation { result in
            isRequestingLocation = false
            switch result {
            case .success(let coordinate):
                appState.scheduleConfig.location = coordinate
                appState.scheduleConfig.selectedCityID = nil
                locationMessage = nil
            case .denied:
                locationMessage = appState.localized("schedule.location_denied")
            case .failed:
                locationMessage = appState.localized("schedule.location_failed")
            }
        }
    }

    /// Real latitude/longitude range, not just "parses as a Double" — a
    /// fat-fingered "413" instead of "41.3" used to sail straight through
    /// into `SolarCalculator`, which would either compute a nonsensical
    /// time or silently return `nil` ("sun never rises"), with no error
    /// shown anywhere (found by an independent review).
    private static let latitudeRange = -90.0...90.0
    private static let longitudeRange = -180.0...180.0

    private var manualCoordinatesAreValid: Bool {
        guard let lat = Double(manualLatitudeText), let lon = Double(manualLongitudeText) else { return false }
        return Self.latitudeRange.contains(lat) && Self.longitudeRange.contains(lon)
    }

    private func applyManualCoordinates() {
        guard let lat = Double(manualLatitudeText), let lon = Double(manualLongitudeText),
              Self.latitudeRange.contains(lat), Self.longitudeRange.contains(lon)
        else { return }
        appState.scheduleConfig.location = Coordinate(latitude: lat, longitude: lon)
        appState.scheduleConfig.selectedCityID = nil
        locationMessage = nil
    }

    // MARK: - Shared rows

    private func timeSection(title: LocalizedStringResource, binding: Binding<TimeOfDay>) -> some View {
        Section {
            DatePicker(
                selection: timeOfDayAsDate(binding),
                displayedComponents: .hourAndMinute
            ) {
                Text(title)
            }
        }
    }

    /// `DatePicker` needs a `Date`; `TimeOfDay` only ever cares about
    /// hour/minute, so this projects through a fixed reference date rather
    /// than adding a second representation of the same information.
    private func timeOfDayAsDate(_ binding: Binding<TimeOfDay>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: binding.wrappedValue.hour, minute: binding.wrappedValue.minute, second: 0, of: Date()) ?? Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                binding.wrappedValue = TimeOfDay(hour: components.hour ?? 0, minute: components.minute ?? 0)
            }
        )
    }

    private var rampSection: some View {
        Section {
            Stepper(
                value: $appState.scheduleConfig.rampMinutes,
                in: 1...120,
                step: 5
            ) {
                HStack {
                    Text("schedule.transition")
                    Spacer()
                    Text(appState.localized("schedule.ramp_minutes_value", appState.scheduleConfig.rampMinutes))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
