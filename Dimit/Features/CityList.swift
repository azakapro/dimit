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
        City(id: "istanbul", titleKey: "schedule.city.istanbul", coordinate: Coordinate(latitude: 41.0082, longitude: 28.9784)),
        City(id: "london", titleKey: "schedule.city.london", coordinate: Coordinate(latitude: 51.5074, longitude: -0.1278)),
        City(id: "new_york", titleKey: "schedule.city.new_york", coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060)),
    ]

    static func city(id: String) -> City? {
        all.first { $0.id == id }
    }
}
