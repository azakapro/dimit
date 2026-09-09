import CoreLocation

/// CLAUDE.md §3.8/§8: "uses CoreLocation *only if user grants* ... No
/// Accessibility/Screen Recording/Location prompts unless the user enables
/// Sunset schedule with 'Use my location'."
///
/// `requestOneTimeLocation(completion:)` is the **only** method here that
/// touches `CLLocationManager`'s authorization — it must only ever be
/// called from that one button's action, never from `init`, from selecting
/// Sunset→Sunrise mode, or from anything else that runs without the user
/// having just pressed that specific button. One request, one location fix,
/// no continuous tracking: this app has no use for anything more than a
/// single coordinate to feed the solar calculator.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    enum Result {
        case success(Coordinate)
        case denied
        case failed
    }

    private let manager = CLLocationManager()
    private var completion: ((Result) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    /// Overwrites any not-yet-fired `completion` from a previous call — a
    /// caller must not invoke this again while one is already in flight,
    /// or the first caller's result is silently dropped. `ScheduleSettingsTab`
    /// enforces this by disabling its "Use my location" button for exactly
    /// this reason; there is no queueing here because there is only ever
    /// the one call site.
    func requestOneTimeLocation(completion: @escaping (Result) -> Void) {
        self.completion = completion
        switch manager.authorizationStatus {
        case .authorizedAlways:
            manager.requestLocation()
        case .notDetermined:
            // Shows the system prompt; the result arrives via
            // `locationManagerDidChangeAuthorization`, not synchronously.
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            finish(.denied)
        @unknown default:
            finish(.failed)
        }
    }

    // Apple documents CLLocationManager's delegate callbacks as arriving on
    // the thread that created the manager — main, here, since `init` runs
    // from SwiftUI view/state setup — but `DisplayManager`'s own reconfig
    // callback comment notes a similar promise elsewhere in this codebase
    // is officially only "the thread currently processing events," not a
    // hard guarantee. Same defensive hop for the same reason: nonisolated
    // delegate methods hopping into `@MainActor` work (`finish` touches
    // `completion`, whose callers touch `AppState`) shouldn't depend on an
    // ObjC framework's documented-but-unenforced thread contract.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedAlways:
                manager.requestLocation()
            case .denied, .restricted:
                self.finish(.denied)
            case .notDetermined:
                break // still waiting on the user to answer the system prompt
            @unknown default:
                self.finish(.failed)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        Task { @MainActor in
            self.finish(.success(coordinate))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            Log.app.error("LocationProvider: \(error, privacy: .public)")
            self.finish(.failed)
        }
    }

    private func finish(_ result: Result) {
        completion?(result)
        completion = nil
    }
}
