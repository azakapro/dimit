import Foundation

/// CLAUDE.md §3.8: the fallback when the user hasn't granted (or hasn't
/// been asked for) their real location — "a user-chosen city from a
/// bundled list with lat/lon." Coordinates are city-centre and only need
/// to be accurate to within a few km for sunrise/sunset purposes (a
/// difference invisible against the ±3 min tolerance CLAUDE.md already
/// allows the solar algorithm itself).
struct City: Identifiable, Equatable {
    let id: String
    let titleKey: LocalizedStringResource
    let coordinate: Coordinate
}

enum CityList {
    /// UZ-first order, per CLAUDE.md's own list ordering — Tashkent and the
    /// other domestic cities before the regional/international ones.
    static let all: [City] = [
        City(id: "tashkent", titleKey: "schedule.city.tashkent", coordinate: Coordinate(latitude: 41.2995, longitude: 69.2401)),
        City(id: "samarkand", titleKey: "schedule.city.samarkand", coordinate: Coordinate(latitude: 39.6270, longitude: 66.9750)),
        City(id: "bukhara", titleKey: "schedule.city.bukhara", coordinate: Coordinate(latitude: 39.7747, longitude: 64.4286)),
        City(id: "namangan", titleKey: "schedule.city.namangan", coordinate: Coordinate(latitude: 40.9983, longitude: 71.6726)),
        City(id: "andijan", titleKey: "schedule.city.andijan", coordinate: Coordinate(latitude: 40.7821, longitude: 72.3442)),
        City(id: "fergana", titleKey: "schedule.city.fergana", coordinate: Coordinate(latitude: 40.3864, longitude: 71.7864)),
        City(id: "nukus", titleKey: "schedule.city.nukus", coordinate: Coordinate(latitude: 42.4531, longitude: 59.6103)),
        City(id: "moscow", titleKey: "schedule.city.moscow", coordinate: Coordinate(latitude: 55.7558, longitude: 37.6173)),
        City(id: "almaty", titleKey: "schedule.city.almaty", coordinate: Coordinate(latitude: 43.2220, longitude: 76.8512)),
        City(id: "bishkek", titleKey: "schedule.city.bishkek", coordinate: Coordinate(latitude: 42.8746, longitude: 74.5698)),
        City(id: "dushanbe", titleKey: "schedule.city.dushanbe", coordinate: Coordinate(latitude: 38.5598, longitude: 68.7870)),
        City(id: "qarshi", titleKey: "schedule.city.qarshi", coordinate: Coordinate(latitude: 38.8606, longitude: 65.7891)),
        City(id: "termez", titleKey: "schedule.city.termez", coordinate: Coordinate(latitude: 37.2242, longitude: 67.2783)),
        City(id: "urgench", titleKey: "schedule.city.urgench", coordinate: Coordinate(latitude: 41.5500, longitude: 60.6333)),
        City(id: "jizzakh", titleKey: "schedule.city.jizzakh", coordinate: Coordinate(latitude: 40.1158, longitude: 67.8422)),
        City(id: "navoiy", titleKey: "schedule.city.navoiy", coordinate: Coordinate(latitude: 40.0844, longitude: 65.3792)),
        City(id: "gulistan", titleKey: "schedule.city.gulistan", coordinate: Coordinate(latitude: 40.4897, longitude: 68.7842)),
        City(id: "istanbul", titleKey: "schedule.city.istanbul", coordinate: Coordinate(latitude: 41.0082, longitude: 28.9784)),
        City(id: "ankara", titleKey: "schedule.city.ankara", coordinate: Coordinate(latitude: 39.9334, longitude: 32.8597)),
        City(id: "dubai", titleKey: "schedule.city.dubai", coordinate: Coordinate(latitude: 25.2048, longitude: 55.2708)),
        City(id: "astana", titleKey: "schedule.city.astana", coordinate: Coordinate(latitude: 51.1694, longitude: 71.4491)),
        City(id: "ashgabat", titleKey: "schedule.city.ashgabat", coordinate: Coordinate(latitude: 37.9601, longitude: 58.3261)),
        City(id: "baku", titleKey: "schedule.city.baku", coordinate: Coordinate(latitude: 40.4093, longitude: 49.8671)),
        City(id: "saint_petersburg", titleKey: "schedule.city.saint_petersburg", coordinate: Coordinate(latitude: 59.9311, longitude: 30.3609)),
        City(id: "kyiv", titleKey: "schedule.city.kyiv", coordinate: Coordinate(latitude: 50.4501, longitude: 30.5234)),
        City(id: "seoul", titleKey: "schedule.city.seoul", coordinate: Coordinate(latitude: 37.5665, longitude: 126.9780)),
        City(id: "tokyo", titleKey: "schedule.city.tokyo", coordinate: Coordinate(latitude: 35.6762, longitude: 139.6503)),
        City(id: "delhi", titleKey: "schedule.city.delhi", coordinate: Coordinate(latitude: 28.6139, longitude: 77.2090)),
        City(id: "london", titleKey: "schedule.city.london", coordinate: Coordinate(latitude: 51.5074, longitude: -0.1278)),
        City(id: "berlin", titleKey: "schedule.city.berlin", coordinate: Coordinate(latitude: 52.5200, longitude: 13.4050)),
        City(id: "paris", titleKey: "schedule.city.paris", coordinate: Coordinate(latitude: 48.8566, longitude: 2.3522)),
        City(id: "new_york", titleKey: "schedule.city.new_york", coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060)),
        City(id: "los_angeles", titleKey: "schedule.city.los_angeles", coordinate: Coordinate(latitude: 34.0522, longitude: -118.2437)),
    ]

    static func city(id: String) -> City? {
        all.first { $0.id == id }
    }

    /// The city in this list nearest `coordinate`, when one is close enough
    /// to be worth naming.
    ///
    /// This exists purely to *describe* a location the device reported:
    /// after "Use my location" the app knew exactly where it was and could
    /// only say "Using manual coordinates", which is both wrong and useless
    /// ("it is not showing your city after you use that feature").
    ///
    /// Naming it offline, from this list, rather than reverse-geocoding:
    /// `CLGeocoder` is a network request, and CLAUDE.md §1.2/§4.3 allow the
    /// app exactly one of those, for Sparkle, on the user's own opt-in.
    /// A city name in Settings is not worth spending that.
    ///
    /// The schedule itself always computes from the real coordinates, never
    /// from the city this returns, so a wrong guess changes a label and
    /// nothing else. 75 km keeps the label honest: past that the nearest
    /// listed city is a different place, and the caller shows the numbers
    /// instead.
    static func nearest(to coordinate: Coordinate, withinKm limit: Double = 75) -> City? {
        all.map { ($0, distanceKm(coordinate, $0.coordinate)) }
            .filter { $0.1 <= limit }
            .min { $0.1 < $1.1 }?
            .0
    }

    /// Great-circle distance (haversine). `asin`'s argument is clamped: for
    /// two points at the same coordinate, floating-point error can push it a
    /// hair above 1 and turn the whole expression into `nan`.
    private static func distanceKm(_ a: Coordinate, _ b: Coordinate) -> Double {
        let earthRadiusKm = 6371.0
        let radians = Double.pi / 180
        let dLat = (b.latitude - a.latitude) * radians
        let dLon = (b.longitude - a.longitude) * radians
        let lat1 = a.latitude * radians
        let lat2 = b.latitude * radians
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusKm * asin(min(1, sqrt(h)))
    }
}
