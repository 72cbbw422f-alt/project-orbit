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


    func testPendingRequestClassificationExcludesForecastNamespace() {
        let counts = WeatherNotificationBudget.countExternalPendingRequests(identifiers: [
            "regnvakt.weather.north.rain.20261120",
            "smhi.warning.123",
            "other.feature.notification",
            "regnvakt.weather.south.frost.20261120",
            "smhi.warning.456"
        ])
        XCTAssertEqual(counts, WeatherNotificationPendingCounts(smhi: 2, unrelated: 1))
    }

    func testPendingRequestClassificationHandlesEmptyAndUnknownNamespaces() {
        XCTAssertEqual(
            WeatherNotificationBudget.countExternalPendingRequests(identifiers: []),
            WeatherNotificationPendingCounts(smhi: 0, unrelated: 0)
        )
        XCTAssertEqual(
            WeatherNotificationBudget.countExternalPendingRequests(
                identifiers: ["", "another.app.alert"],
                forecastPrefix: "forecast.",
                smhiPrefix: "official."
            ),
            WeatherNotificationPendingCounts(smhi: 0, unrelated: 2)
        )
    }

    func testAvailableCapacityAccountsForSMHIAndUnrelatedRequests() {
        XCTAssertEqual(
            WeatherNotificationBudget.availableForecastCapacity(
                totalBudget: WeatherNotificationBudget.totalPendingBudget,
                reservedHeadroom: WeatherNotificationBudget.reservedHeadroom,
                pendingSMHI: 5,
                pendingUnrelated: 3
            ),
            36
        )
    }

    func testDocumentedAppPolicyProvidesExpectedInitialCapacity() {
        XCTAssertEqual(WeatherNotificationBudget.totalPendingBudget, 52)
        XCTAssertEqual(WeatherNotificationBudget.reservedHeadroom, 8)
        XCTAssertEqual(
            WeatherNotificationBudget.availableForecastCapacity(
                totalBudget: WeatherNotificationBudget.totalPendingBudget,
                reservedHeadroom: WeatherNotificationBudget.reservedHeadroom,
                pendingSMHI: 0,
                pendingUnrelated: 0
            ),
            44
        )
    }

    func testAvailableCapacityNeverBecomesNegative() {
        XCTAssertEqual(
            WeatherNotificationBudget.availableForecastCapacity(
                totalBudget: WeatherNotificationBudget.totalPendingBudget,
                reservedHeadroom: WeatherNotificationBudget.reservedHeadroom,
                pendingSMHI: 40,
                pendingUnrelated: 20
            ),
            0
        )
    }

    func testAvailableCapacityClampsInvalidNegativeInputs() {
        XCTAssertEqual(
            WeatherNotificationBudget.availableForecastCapacity(
                totalBudget: -1,
                reservedHeadroom: -2,
                pendingSMHI: -3,
                pendingUnrelated: -4
            ),
            0
        )
    }

    func testInterimPerPlaceLimitDoesNotForceOneRequestPerPlace() {
        XCTAssertEqual(WeatherNotificationBudget.interimPerPlaceLimit(registryCount: 1), 8)
        XCTAssertEqual(WeatherNotificationBudget.interimPerPlaceLimit(registryCount: 8), 5)
        XCTAssertEqual(WeatherNotificationBudget.interimPerPlaceLimit(registryCount: 44), 1)
        XCTAssertEqual(WeatherNotificationBudget.interimPerPlaceLimit(registryCount: 45), 0)
        XCTAssertEqual(WeatherNotificationBudget.interimPerPlaceLimit(registryCount: 52), 0)
        XCTAssertEqual(WeatherNotificationBudget.interimPerPlaceLimit(registryCount: 0), 0)
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

    func testMultiplePreservedCurrentFrostRequestsSurviveCapacityOverflow() {
        let items = [
            candidate("frost-north", location: "north", priority: .immediateFrost, preserved: true),
            candidate("frost-south", location: "south", priority: .immediateFrost, preserved: true),
            candidate("ordinary", location: "west")
        ]
        XCTAssertEqual(
            WeatherNotificationBudget.select(candidates: items, capacity: 0),
            ["frost-north", "frost-south"]
        )
    }

    func testEmptyIdentifiersAreIgnoredAndNegativeCapacityActsAsZero() {
        let items = [
            candidate("", priority: .immediateFrost),
            candidate("ordinary", priority: .forecast)
        ]
        XCTAssertTrue(WeatherNotificationBudget.select(candidates: items, capacity: -10).isEmpty)
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
