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


    func testRoutineEventTooCloseToScheduleDoesNotConsumeRiskType() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(WeatherWatchRules.canScheduleForecastEvent(
            eventDate: now.addingTimeInterval(10 * 60),
            safetyCritical: false,
            leadMinutes: 30,
            now: now,
            quietHours: "none"
        ))
    }

    func testLaterRoutineEventCanBeScheduledAfterEarlierEventWasTooClose() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(WeatherWatchRules.canScheduleForecastEvent(
            eventDate: now.addingTimeInterval(3 * 60 * 60),
            safetyCritical: false,
            leadMinutes: 30,
            now: now,
            quietHours: "none"
        ))
    }

    func testRoutineEventDuringQuietHoursDoesNotConsumeRiskType() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 20, minute: 0))!
        let event = calendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 23, minute: 0))!
        XCTAssertFalse(WeatherWatchRules.canScheduleForecastEvent(
            eventDate: event,
            safetyCritical: false,
            leadMinutes: 30,
            now: now,
            quietHours: "22–07"
        ))
    }

    func testSafetyCriticalEventCanBeScheduledImmediatelyDuringQuietHours() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 23, minute: 0))!
        XCTAssertTrue(WeatherWatchRules.canScheduleForecastEvent(
            eventDate: now.addingTimeInterval(10 * 60),
            safetyCritical: true,
            leadMinutes: 30,
            now: now,
            quietHours: "22–07"
        ))
    }

    func testRoutineEventAtMinimumLeadBoundaryIsRejected() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(WeatherWatchRules.canScheduleForecastEvent(
            eventDate: now.addingTimeInterval(30 * 60 + 30),
            safetyCritical: false,
            leadMinutes: 30,
            now: now,
            quietHours: "none",
            minimumLeadTime: 30
        ))
    }

    func testRoutineEventOutsideCrossMidnightQuietHoursIsAllowed() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 12, minute: 0))!
        let event = calendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 18, minute: 0))!
        XCTAssertTrue(WeatherWatchRules.canScheduleForecastEvent(
            eventDate: event,
            safetyCritical: false,
            leadMinutes: 30,
            now: now,
            quietHours: "22–07"
        ))
    }

    func testFutureSafetyCriticalEventIsNotDeliveredImmediatelyWhenLeadTimeHasPassed() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let event = now.addingTimeInterval(10 * 60)
        XCTAssertFalse(WeatherNotificationBudget.shouldDeliverImmediately(
            alreadyImmediate: false,
            safetyCritical: true,
            eventDate: event,
            leadMinutes: 30,
            now: now
        ))
    }

    func testSafetyCriticalEventRemainsScheduledWhenLeadTimeIsInFuture() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let event = now.addingTimeInterval(90 * 60)
        XCTAssertFalse(WeatherNotificationBudget.shouldDeliverImmediately(
            alreadyImmediate: false,
            safetyCritical: true,
            eventDate: event,
            leadMinutes: 30,
            now: now
        ))
    }

    func testRoutineForecastEventIsNotPromotedToImmediate() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(WeatherNotificationBudget.shouldDeliverImmediately(
            alreadyImmediate: false,
            safetyCritical: false,
            eventDate: now.addingTimeInterval(10 * 60),
            leadMinutes: 30,
            now: now
        ))
    }

    func testExplicitImmediateEventStaysImmediate() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(WeatherNotificationBudget.shouldDeliverImmediately(
            alreadyImmediate: true,
            safetyCritical: true,
            eventDate: now,
            leadMinutes: 30,
            now: now
        ))
    }

    func testCandidateMetadataPrioritizesImmediateFrostThenSafetyThenForecast() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let immediate = WeatherNotificationBudget.makeCandidate(
            identifier: "immediate", locationID: "north", fireDate: now,
            isImmediateFrost: true, isSafetyCritical: true,
            isPreservedPendingCurrentFrost: false
        )
        let safety = WeatherNotificationBudget.makeCandidate(
            identifier: "ice", locationID: "south", fireDate: now,
            isImmediateFrost: false, isSafetyCritical: true,
            isPreservedPendingCurrentFrost: false
        )
        let ordinary = WeatherNotificationBudget.makeCandidate(
            identifier: "rain", locationID: "east", fireDate: now,
            isImmediateFrost: false, isSafetyCritical: false,
            isPreservedPendingCurrentFrost: false
        )

        XCTAssertEqual(immediate.priority, .immediateFrost)
        XCTAssertEqual(safety.priority, .safetyCritical)
        XCTAssertEqual(ordinary.priority, .forecast)
    }

    func testCandidateMetadataPreservesPendingCurrentFrostFlag() {
        let candidate = WeatherNotificationBudget.makeCandidate(
            identifier: "current-frost", locationID: "north", fireDate: Date(),
            isImmediateFrost: true, isSafetyCritical: true,
            isPreservedPendingCurrentFrost: true
        )
        XCTAssertTrue(candidate.isPreservedPendingCurrentFrost)
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

    func testPendingSnapshotCapacityExcludesForecastAndCountsExternalNamespaces() {
        let pending = [
            "regnvakt.weather.north.rain.20261121",
            "smhi.warning.one",
            "smhi.warning.two",
            "unrelated.calendar.alert",
            "another.app.alert"
        ]
        XCTAssertEqual(
            WeatherNotificationBudget.availableForecastCapacity(pendingIdentifiers: pending),
            40
        )
    }

    func testPendingSnapshotCapacityClampsAtZeroWhenExternalQueueIsFull() {
        let pending = (0..<60).map { "external.\($0)" }
        XCTAssertEqual(
            WeatherNotificationBudget.availableForecastCapacity(pendingIdentifiers: pending),
            0
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

    func testGlobalSelectionSharesCapacityAcrossLocationsAndExternalNamespaces() {
        let pendingSnapshot = [
            "smhi.warning.one",
            "smhi.warning.two",
            "calendar.reminder.one",
            "regnvakt.weather.old-place.rain.20261121"
        ]
        let capacity = WeatherNotificationBudget.availableForecastCapacity(
            pendingIdentifiers: pendingSnapshot
        )
        XCTAssertEqual(capacity, 41)

        let candidates = [
            candidate("north-rain", location: "north", minutes: 1),
            candidate("south-rain", location: "south", minutes: 2),
            candidate("east-ice", location: "east", priority: .safetyCritical, minutes: 30),
            candidate("west-current-frost", location: "west", priority: .immediateFrost, minutes: 60)
        ]
        XCTAssertEqual(
            WeatherNotificationBudget.select(candidates: candidates, capacity: 2),
            ["west-current-frost", "east-ice"]
        )
    }

    func testDeliveredImmediateFrostDaysAreRestoredOnlyForRegisteredLocations() {
        let earlier = Date(timeIntervalSince1970: 1_800_000_000)
        let later = earlier.addingTimeInterval(24 * 60 * 60)
        let alerts = [
            DeliveredCurrentFrostAlert(identifier: "regnvakt.weather.north.frost.current.today", alertDay: earlier, isImmediate: true),
            DeliveredCurrentFrostAlert(identifier: "regnvakt.weather.north.frost.current.tomorrow", alertDay: later, isImmediate: true),
            DeliveredCurrentFrostAlert(identifier: "regnvakt.weather.south.frost.current.today", alertDay: earlier, isImmediate: false),
            DeliveredCurrentFrostAlert(identifier: "regnvakt.weather.removed.frost.current.today", alertDay: later, isImmediate: true),
            DeliveredCurrentFrostAlert(identifier: "smhi.warning.north.frost.current.today", alertDay: later, isImmediate: true),
            DeliveredCurrentFrostAlert(identifier: "regnvakt.weather.north.rain.today", alertDay: later, isImmediate: true)
        ]
        XCTAssertEqual(
            WeatherNotificationBudget.latestDeliveredCurrentFrostDays(
                alerts: alerts,
                registeredLocationIDs: ["north", "south"]
            ),
            ["north": later]
        )
    }

    func testDeliveredCurrentFrostWithoutAlertDayDoesNotCreateDeduplicationMarker() {
        let alerts = [
            DeliveredCurrentFrostAlert(identifier: "regnvakt.weather.north.frost.current.today", alertDay: nil, isImmediate: true)
        ]
        XCTAssertTrue(
            WeatherNotificationBudget.latestDeliveredCurrentFrostDays(
                alerts: alerts,
                registeredLocationIDs: ["north"]
            ).isEmpty
        )
    }

    func testFullForecastCleanupSelectsOnlyRegnvaktNamespace() {
        let identifiers = [
            "regnvakt.weather.north.rain.today",
            "regnvakt.weather.south.frost.tomorrow",
            "smhi.warning.active",
            "calendar.reminder.active",
            "other.app.notification"
        ]

        XCTAssertEqual(
            WeatherNotificationBudget.forecastIdentifiers(in: identifiers),
            [
                "regnvakt.weather.north.rain.today",
                "regnvakt.weather.south.frost.tomorrow"
            ]
        )
    }

    func testLocationCleanupMatchesOnlyExactRegnvaktForecastNamespace() {
        let identifiers = [
            "regnvakt.weather.60.0000_10.0000.frost.current.today",
            "regnvakt.weather.60.0000_100.0000.frost.current.today",
            "regnvakt.weather.61.0000_10.0000.rain.tomorrow",
            "smhi.warning.60.10",
            "other.app.60.10"
        ]

        XCTAssertEqual(
            WeatherNotificationBudget.forecastIdentifiers(
                for: "60.0000,10.0000",
                in: identifiers
            ),
            ["regnvakt.weather.60.0000_10.0000.frost.current.today"]
        )
    }

    func testPreservedCurrentFrostRequiresAnEnabledWatchAndRegisteredLocation() {
        let pending = [
            "regnvakt.weather.north.frost.current.today",
            "regnvakt.weather.south.frost.current.today",
            "regnvakt.weather.removed.frost.current.today",
            "smhi.warning.frost.current.today",
            "regnvakt.weather.north.rain.today"
        ]
        let registered = Set(["north", "south"])

        XCTAssertEqual(
            WeatherNotificationBudget.preservedPendingCurrentFrostIdentifiers(
                pendingIdentifiers: pending,
                registeredLocationIDs: registered,
                isEnabled: true
            ),
            Set([
                "regnvakt.weather.north.frost.current.today",
                "regnvakt.weather.south.frost.current.today"
            ])
        )
    }

    func testDisabledFrostWatchPreservesNoPendingCurrentFrostRequests() {
        XCTAssertTrue(
            WeatherNotificationBudget.preservedPendingCurrentFrostIdentifiers(
                pendingIdentifiers: ["regnvakt.weather.north.frost.current.today"],
                registeredLocationIDs: ["north"],
                isEnabled: false
            ).isEmpty
        )
    }

    func testSelectionCapacityReservesPendingFrostMissingFromFreshCandidates() {
        let preserved = Set([
            "regnvakt.weather.north.frost.current.today",
            "regnvakt.weather.south.frost.current.today"
        ])
        let candidateIDs = Set(["regnvakt.weather.east.rain.tomorrow"])

        XCTAssertEqual(
            WeatherNotificationBudget.selectionCapacity(
                availableCapacity: 3,
                preservedPendingIdentifiers: preserved,
                candidateIdentifiers: candidateIDs
            ),
            1
        )
    }

    func testSelectionCapacityDoesNotDoubleCountPreservedFrostCandidates() {
        let preserved = Set(["frost-north", "frost-south"])
        let candidateIDs = Set(["frost-north", "frost-south", "rain"])

        XCTAssertEqual(
            WeatherNotificationBudget.selectionCapacity(
                availableCapacity: 2,
                preservedPendingIdentifiers: preserved,
                candidateIdentifiers: candidateIDs
            ),
            2
        )
    }

    func testSelectionCapacityClampsAtZeroWhenPreservedFrostExceedsCapacity() {
        XCTAssertEqual(
            WeatherNotificationBudget.selectionCapacity(
                availableCapacity: 1,
                preservedPendingIdentifiers: ["frost-north", "frost-south"],
                candidateIdentifiers: []
            ),
            0
        )
    }

    func testGlobalSelectionPreservesPendingCurrentFrostAcrossLocations() {
        let pendingSnapshot = [
            "regnvakt.weather.north.frost.current.20261121",
            "regnvakt.weather.south.frost.current.20261121",
            "smhi.warning.one"
        ]
        let pending = Set(pendingSnapshot)
        let candidates = [
            WeatherNotificationBudget.makeCandidate(
                identifier: "regnvakt.weather.north.frost.current.20261121",
                locationID: "north",
                fireDate: Date(timeIntervalSince1970: 10),
                isImmediateFrost: true,
                isSafetyCritical: true,
                isPreservedPendingCurrentFrost: pending.contains("regnvakt.weather.north.frost.current.20261121")
            ),
            WeatherNotificationBudget.makeCandidate(
                identifier: "regnvakt.weather.south.frost.current.20261121",
                locationID: "south",
                fireDate: Date(timeIntervalSince1970: 20),
                isImmediateFrost: true,
                isSafetyCritical: true,
                isPreservedPendingCurrentFrost: pending.contains("regnvakt.weather.south.frost.current.20261121")
            ),
            candidate("ordinary", location: "west")
        ]
        XCTAssertEqual(
            WeatherNotificationBudget.select(candidates: candidates, capacity: 0),
            [
                "regnvakt.weather.north.frost.current.20261121",
                "regnvakt.weather.south.frost.current.20261121"
            ]
        )
    }

    func testReconciliationPlanReplacesOnlyForecastNamespace() {
        let plan = WeatherNotificationReconciliationPlan.make(
            selectedIdentifiers: [
                "regnvakt.weather.north.rain.new",
                "regnvakt.weather.south.ice.new",
                "smhi.warning.new",
                "other.app.new"
            ],
            pendingIdentifiers: [
                "regnvakt.weather.north.rain.old",
                "regnvakt.weather.south.frost.current.today",
                "smhi.warning.active",
                "calendar.reminder.active"
            ],
            deliveredIdentifiers: [],
            preservedPendingIdentifiers: ["regnvakt.weather.south.frost.current.today"]
        )

        XCTAssertEqual(plan.preservedPendingIdentifiers, ["regnvakt.weather.south.frost.current.today"])
        XCTAssertEqual(plan.pendingIdentifiersToRemove, ["regnvakt.weather.north.rain.old"])
        XCTAssertEqual(plan.identifiersToAdd, [
            "regnvakt.weather.north.rain.new",
            "regnvakt.weather.south.ice.new"
        ])
    }

    func testReconciliationPlanReaddsStableIDsButKeepsPreservedFrost() {
        let stableRain = "regnvakt.weather.north.rain.20261121"
        let currentFrost = "regnvakt.weather.north.frost.current.20261121"
        let plan = WeatherNotificationReconciliationPlan.make(
            selectedIdentifiers: [stableRain, currentFrost, stableRain],
            pendingIdentifiers: [stableRain, currentFrost],
            deliveredIdentifiers: [],
            preservedPendingIdentifiers: [currentFrost]
        )

        XCTAssertEqual(plan.preservedPendingIdentifiers, [currentFrost])
        XCTAssertEqual(plan.pendingIdentifiersToRemove, [stableRain])
        XCTAssertEqual(plan.identifiersToAdd, [stableRain])
    }

    func testReconciliationPlanPreservesOnlyPendingCurrentFrostIdentifiers() {
        let pendingFrost = "regnvakt.weather.north.frost.current.today"
        let staleFrost = "regnvakt.weather.south.frost.current.today"
        let ordinary = "regnvakt.weather.north.rain.old"
        let plan = WeatherNotificationReconciliationPlan.make(
            selectedIdentifiers: [],
            pendingIdentifiers: [pendingFrost, ordinary],
            deliveredIdentifiers: [],
            preservedPendingIdentifiers: [pendingFrost, staleFrost]
        )

        XCTAssertEqual(plan.preservedPendingIdentifiers, [pendingFrost])
        XCTAssertEqual(plan.pendingIdentifiersToRemove, [ordinary])
        XCTAssertTrue(plan.identifiersToAdd.isEmpty)
    }

    func testReconciliationPlanDoesNotPreserveDeliveredFrostIdentifier() {
        let frost = "regnvakt.weather.north.frost.current.today"
        let plan = WeatherNotificationReconciliationPlan.make(
            selectedIdentifiers: [],
            pendingIdentifiers: [],
            deliveredIdentifiers: [frost],
            preservedPendingIdentifiers: [frost]
        )

        XCTAssertTrue(plan.preservedPendingIdentifiers.isEmpty)
        XCTAssertTrue(plan.pendingIdentifiersToRemove.isEmpty)
        XCTAssertTrue(plan.identifiersToAdd.isEmpty)
    }

    func testReconciliationPlanNeverReaddsDeliveredOrForeignIdentifiers() {
        let plan = WeatherNotificationReconciliationPlan.make(
            selectedIdentifiers: [
                "regnvakt.weather.north.rain.delivered",
                "regnvakt.weather.north.ice.new",
                "smhi.warning.foreign"
            ],
            pendingIdentifiers: [
                "regnvakt.weather.north.rain.pending",
                "smhi.warning.pending"
            ],
            deliveredIdentifiers: ["regnvakt.weather.north.rain.delivered"],
            preservedPendingIdentifiers: []
        )

        XCTAssertEqual(plan.pendingIdentifiersToRemove, ["regnvakt.weather.north.rain.pending"])
        XCTAssertEqual(plan.identifiersToAdd, ["regnvakt.weather.north.ice.new"])
    }

    func testLatestDeliveredCurrentFrostDaysUsesNewestImmediateAlertPerRegisteredLocation() {
        let oldDay = Date(timeIntervalSince1970: 1_800_000_000)
        let newDay = oldDay.addingTimeInterval(24 * 60 * 60)
        let alerts = [
            DeliveredCurrentFrostAlert(
                identifier: "regnvakt.weather.north.frost.current.old",
                alertDay: oldDay,
                isImmediate: true
            ),
            DeliveredCurrentFrostAlert(
                identifier: "regnvakt.weather.north.frost.current.new",
                alertDay: newDay,
                isImmediate: true
            ),
            DeliveredCurrentFrostAlert(
                identifier: "regnvakt.weather.north.frost.current.forecast",
                alertDay: newDay.addingTimeInterval(24 * 60 * 60),
                isImmediate: false
            ),
            DeliveredCurrentFrostAlert(
                identifier: "regnvakt.weather.removed.frost.current.new",
                alertDay: newDay,
                isImmediate: true
            ),
            DeliveredCurrentFrostAlert(
                identifier: "regnvakt.weather.south.frost.current.unknown",
                alertDay: nil,
                isImmediate: true
            ),
            DeliveredCurrentFrostAlert(
                identifier: "smhi.warning.north.frost.current.new",
                alertDay: newDay,
                isImmediate: true
            )
        ]

        XCTAssertEqual(
            WeatherNotificationBudget.latestDeliveredCurrentFrostDays(
                alerts: alerts,
                registeredLocationIDs: ["north", "south"]
            ),
            ["north": newDay]
        )
    }

    func testPreservablePendingForecastRequiresFreshMetadataFutureEventAndEnabledWatch() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let valid = PendingForecastAlert(
            identifier: "regnvakt.weather.north.rain.valid", locationID: "north", watch: "rain",
            generatedAt: now.addingTimeInterval(-3 * 60 * 60),
            eventDate: now.addingTimeInterval(2 * 60 * 60),
            fireDate: now.addingTimeInterval(90 * 60)
        )
        let alerts = [
            valid,
            PendingForecastAlert(identifier: "expired", locationID: "north", watch: "rain",
                generatedAt: now.addingTimeInterval(-5 * 60 * 60), eventDate: now.addingTimeInterval(2 * 60 * 60), fireDate: now.addingTimeInterval(90 * 60)),
            PendingForecastAlert(identifier: "event-passed", locationID: "north", watch: "rain",
                generatedAt: now.addingTimeInterval(-60), eventDate: now, fireDate: now.addingTimeInterval(30)),
            PendingForecastAlert(identifier: "trigger-passed", locationID: "north", watch: "rain",
                generatedAt: now.addingTimeInterval(-60), eventDate: now.addingTimeInterval(60), fireDate: now),
            PendingForecastAlert(identifier: "wrong-location", locationID: "removed", watch: "rain",
                generatedAt: now.addingTimeInterval(-60), eventDate: now.addingTimeInterval(60), fireDate: now.addingTimeInterval(30)),
            PendingForecastAlert(identifier: "disabled-watch", locationID: "north", watch: "snow",
                generatedAt: now.addingTimeInterval(-60), eventDate: now.addingTimeInterval(60), fireDate: now.addingTimeInterval(30)),
            PendingForecastAlert(identifier: "future-snapshot", locationID: "north", watch: "rain",
                generatedAt: now.addingTimeInterval(60), eventDate: now.addingTimeInterval(120), fireDate: now.addingTimeInterval(90))
        ]

        XCTAssertEqual(
            WeatherNotificationBudget.preservablePendingForecastIdentifiers(
                alerts: alerts, registeredLocationIDs: ["north"], enabledWatchTypes: ["rain"], now: now
            ),
            [valid.identifier]
        )
    }

    func testPreservablePendingForecastRejectsSnapshotAtMaximumAgeBoundaryPlusOneSecond() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let alert = PendingForecastAlert(
            identifier: "old", locationID: "north", watch: "rain",
            generatedAt: now.addingTimeInterval(-(4 * 60 * 60 + 1)),
            eventDate: now.addingTimeInterval(60), fireDate: now.addingTimeInterval(30)
        )
        XCTAssertTrue(WeatherNotificationBudget.preservablePendingForecastIdentifiers(
            alerts: [alert], registeredLocationIDs: ["north"], enabledWatchTypes: ["rain"], now: now
        ).isEmpty)
    }

}
