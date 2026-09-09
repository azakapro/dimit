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
}
