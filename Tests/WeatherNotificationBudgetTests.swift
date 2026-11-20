import XCTest

final class WeatherNotificationBudgetTests: XCTestCase {
    private func candidate(
        _ id: String,
        location: String = "place",
        priority: WeatherNotificationPriority = .forecast,
        minutes: TimeInterval = 0,
        preserved: Bool = false
    ) -> WeatherNotificationCandidate {
        WeatherNotificationCandidate(
            identifier: id,
            locationID: location,
            fireDate: Date(timeIntervalSince1970: minutes * 60),
            priority: priority,
            isPreservedPendingCurrentFrost: preserved
        )
    }

    func testCapacityBoundariesNeverExceedCapacity() {
        let items = (0..<80).map { candidate("n\($0)", location: "p\($0 % 57)", minutes: Double($0)) }
        for capacity in [0, 1, 8, 52] {
            XCTAssertLessThanOrEqual(
                WeatherNotificationBudget.select(candidates: items, capacity: capacity).count,
                capacity
            )
        }
        XCTAssertEqual(WeatherNotificationBudget.select(candidates: items, capacity: 52).count, 52)
        XCTAssertEqual(WeatherNotificationBudget.select(candidates: items, capacity: 1).count, 1)
        XCTAssertTrue(WeatherNotificationBudget.select(candidates: items, capacity: 0).isEmpty)
    }

    func testImmediateFrostAndSafetyAlertsOutrankEarlierOrdinaryAlertsAcrossPlaces() {
        let items = [
            candidate("ordinary", location: "south", minutes: 1),
            candidate("ice", location: "north", priority: .safetyCritical, minutes: 30),
            candidate("now", location: "east", priority: .immediateFrost, minutes: 60)
        ]
        XCTAssertEqual(
            WeatherNotificationBudget.select(candidates: items, capacity: 2),
            ["now", "ice"]
        )
    }

    func testPreservedCurrentFrostConsumesCapacityAndIsNeverDisplaced() {
        let items = [
            candidate("existing-frost", location: "north", priority: .immediateFrost, preserved: true),
            candidate("new-immediate", location: "south", priority: .immediateFrost),
            candidate("ordinary", location: "west")
        ]
        XCTAssertEqual(
            WeatherNotificationBudget.select(candidates: items, capacity: 2),
            ["existing-frost", "new-immediate"]
        )
        XCTAssertEqual(
            WeatherNotificationBudget.select(candidates: items, capacity: 0),
            ["existing-frost"]
        )
    }

    func testDeliveredIdentifiersAreNotSelectedAgain() {
        let items = [candidate("already-delivered"), candidate("new")]
        XCTAssertEqual(
            WeatherNotificationBudget.select(
                candidates: items,
                capacity: 8,
                deliveredIdentifiers: ["already-delivered"]
            ),
            ["new"]
        )
    }

    func testDuplicateIdentifiersAreSelectedOnlyOnce() {
        let items = [
            candidate("same", location: "z", minutes: 10),
            candidate("same", location: "a", priority: .safetyCritical, minutes: 0),
            candidate("other")
        ]
        XCTAssertEqual(
            WeatherNotificationBudget.select(candidates: items, capacity: 8).filter { $0 == "same" }.count,
            1
        )
    }

    func testSelectionIsDeterministicForEqualPriorityAndTime() {
        let items = [
            candidate("b", location: "b"),
            candidate("a", location: "a"),
            candidate("c", location: "c")
        ]
        XCTAssertEqual(
            WeatherNotificationBudget.select(candidates: items, capacity: 3),
            ["a", "b", "c"]
        )
    }
}
