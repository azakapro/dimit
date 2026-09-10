import XCTest
@testable import Dimit

final class CityListTests: XCTestCase {
    // CLAUDE.md §3.8's literal list: "Tashkent, Samarkand, Bukhara,
    // Namangan, Andijan, Fergana, Nukus, Moscow, Almaty, Bishkek, Dushanbe,
    // Istanbul, London, New York."
    func test_containsEveryCityNamedInTheSpec() {
        let ids = Set(CityList.all.map(\.id))
        let required = ["tashkent", "samarkand", "bukhara", "namangan", "andijan", "fergana",
                         "nukus", "moscow", "almaty", "bishkek", "dushanbe", "istanbul", "london", "new_york"]
        for id in required {
            XCTAssertTrue(ids.contains(id), "missing city: \(id)")
        }
    }

    func test_everyCoordinate_isWithinValidRange() {
        for city in CityList.all {
            XCTAssertTrue((-90...90).contains(city.coordinate.latitude), "\(city.id) latitude out of range")
            XCTAssertTrue((-180...180).contains(city.coordinate.longitude), "\(city.id) longitude out of range")
        }
    }

    // Tashkent is the one CLAUDE.md pins a reference date/value against
    // (§3.8, §8) — worth a direct check that it matches the coordinate the
    // SolarCalculator tests were written against.
    func test_tashkentCoordinate_matchesTheOneUsedInSolarCalculatorTests() {
        let tashkent = try! XCTUnwrap(CityList.city(id: "tashkent"))
        XCTAssertEqual(tashkent.coordinate.latitude, 41.2995, accuracy: 0.001)
        XCTAssertEqual(tashkent.coordinate.longitude, 69.2401, accuracy: 0.001)
    }

    func test_ids_areAllUnique() {
        let ids = CityList.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func test_cityLookup_byID() {
        XCTAssertEqual(CityList.city(id: "london")?.id, "london")
        XCTAssertNil(CityList.city(id: "atlantis"))
    }

    // West-of-Greenwich cities are the one place a longitude sign error
    // would slip past every UZ/Central-Asia test above.
    func test_londonAndNewYork_haveNegativeLongitude() {
        XCTAssertLessThan(try! XCTUnwrap(CityList.city(id: "london")).coordinate.longitude, 0)
        XCTAssertLessThan(try! XCTUnwrap(CityList.city(id: "new_york")).coordinate.longitude, 0)
    }

    // `nearest` names a device location offline, because reverse geocoding
    // would be a network call the app is not allowed to make (CLAUDE.md
    // §4.3). It only ever produces a *label*, so the risk it carries is
    // naming the wrong place — which these pin.

    func test_nearest_namesTheCityYouAreActuallyIn() {
        // A synthetic point near Tashkent, away from the bundled city centre.
        // Regresses the device-location case that used to show "Using manual
        // coordinates" and name nothing, without storing anyone's location.
        let reported = Coordinate(latitude: 41.31, longitude: 69.26)
        XCTAssertEqual(CityList.nearest(to: reported)?.id, "tashkent")
    }

    func test_nearest_picksTheClosestWhenSeveralAreInRange() {
        // Fergana valley: Fergana, Andijan and Namangan sit within ~80 km of
        // each other, so this is where an "any city in range" bug would show.
        for city in CityList.all where ["fergana", "andijan", "namangan"].contains(city.id) {
            XCTAssertEqual(CityList.nearest(to: city.coordinate)?.id, city.id, "at \(city.id)'s own coordinates")
        }
    }

    func test_nearest_returnsNothingWhenTheListHasNowhereClose() {
        // Mid-Pacific. Naming the "nearest" city here would be a lie, and
        // the caller shows the raw coordinates instead.
        XCTAssertNil(CityList.nearest(to: Coordinate(latitude: 0, longitude: -160)))
    }

    func test_nearest_isNotFooledByLongitudeWrapAroundOrIdenticalPoints() {
        // asin's argument is clamped in the haversine; without that, a point
        // identical to a city's own coordinate can produce NaN and lose the
        // comparison silently.
        let tashkent = CityList.city(id: "tashkent")!
        XCTAssertEqual(CityList.nearest(to: tashkent.coordinate)?.id, "tashkent")
        // Just west of the antimeridian: nothing in the list is near, and the
        // maths must not wrap it onto London or Tokyo.
        XCTAssertNil(CityList.nearest(to: Coordinate(latitude: 0, longitude: 179.9)))
    }

    func test_everyCityHasPlausibleCoordinatesAndAUniqueID() {
        var seen = Set<String>()
        for city in CityList.all {
            XCTAssertTrue(seen.insert(city.id).inserted, "duplicate city id: \(city.id)")
            XCTAssertTrue((-90...90).contains(city.coordinate.latitude), "\(city.id) latitude")
            XCTAssertTrue((-180...180).contains(city.coordinate.longitude), "\(city.id) longitude")
        }
        XCTAssertGreaterThan(CityList.all.count, 25, "the list was expanded so manual coordinates could be removed")
    }
}
