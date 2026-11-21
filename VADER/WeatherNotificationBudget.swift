import Foundation

/// Pure, deterministic selection for the future global weather-notification
/// reconciliation. Capacity is supplied by the caller after accounting for
/// SMHI and unrelated pending notifications.
enum WeatherNotificationPriority: Int, Comparable {
    case immediateFrost = 0
    case safetyCritical = 1
    case forecast = 2

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct WeatherNotificationCandidate {
    let identifier: String
    let locationID: String
    let fireDate: Date
    let priority: WeatherNotificationPriority
    let isPreservedPendingCurrentFrost: Bool
}


struct WeatherNotificationPendingCounts: Equatable {
    let smhi: Int
    let unrelated: Int
}

enum WeatherNotificationBudget {
    /// Builds the pure priority metadata shared by request construction and
    /// global selection. Immediate frost is always ranked above other safety
    /// alerts; ordinary forecast alerts remain last.
    static func makeCandidate(
        identifier: String,
        locationID: String,
        fireDate: Date,
        isImmediateFrost: Bool,
        isSafetyCritical: Bool,
        isPreservedPendingCurrentFrost: Bool
    ) -> WeatherNotificationCandidate {
        let priority: WeatherNotificationPriority
        if isImmediateFrost {
            priority = .immediateFrost
        } else if isSafetyCritical {
            priority = .safetyCritical
        } else {
            priority = .forecast
        }
        return WeatherNotificationCandidate(
            identifier: identifier,
            locationID: locationID,
            fireDate: fireDate,
            priority: priority,
            isPreservedPendingCurrentFrost: isPreservedPendingCurrentFrost
        )
    }

    /// Conservative Regnvakt app policy, not an iOS platform limit.
    /// The reserve is additional headroom after counting already-pending
    /// SMHI and unrelated notifications.
    static let totalPendingBudget = 52
    static let reservedHeadroom = 8

    /// Temporary safety guard for the legacy per-location scheduler.
    /// This prevents the old minimum-one rule from exceeding the app's
    /// forecast allocation when more than 44 locations are monitored.
    /// It is not a substitute for global candidate selection.
    static func interimPerPlaceLimit(registryCount: Int) -> Int {
        guard registryCount > 0 else { return 0 }
        let baseForecastCapacity = availableForecastCapacity(
            totalBudget: totalPendingBudget,
            reservedHeadroom: reservedHeadroom,
            pendingSMHI: 0,
            pendingUnrelated: 0
        )
        return min(8, baseForecastCapacity / registryCount)
    }

    /// Classifies one pending-notification snapshot. Forecast-owned requests are
    /// deliberately excluded because reconciliation replaces that namespace;
    /// SMHI and every other owner continue consuming shared pending capacity.
    static func countExternalPendingRequests(
        identifiers: [String],
        forecastPrefix: String = "regnvakt.weather.",
        smhiPrefix: String = "smhi."
    ) -> WeatherNotificationPendingCounts {
        var smhi = 0
        var unrelated = 0
        for identifier in identifiers {
            if identifier.hasPrefix(forecastPrefix) {
                continue
            } else if identifier.hasPrefix(smhiPrefix) {
                smhi += 1
            } else {
                unrelated += 1
            }
        }
        return WeatherNotificationPendingCounts(smhi: smhi, unrelated: unrelated)
    }

    /// Calculates how many new forecast requests may be added under the app's
    /// conservative budget. The reserve is headroom in addition to requests
    /// already pending in the SMHI and unrelated namespaces.
    static func availableForecastCapacity(
        totalBudget: Int,
        reservedHeadroom: Int,
        pendingSMHI: Int,
        pendingUnrelated: Int
    ) -> Int {
        max(
            0,
            max(0, totalBudget) -
                max(0, reservedHeadroom) -
                max(0, pendingSMHI) -
                max(0, pendingUnrelated)
        )
    }

    /// Derives the global forecast allocation from one pending-request snapshot.
    /// Forecast-owned identifiers are excluded because reconciliation replaces them;
    /// SMHI and unrelated pending requests reduce the available capacity.
    static func availableForecastCapacity(pendingIdentifiers: [String]) -> Int {
        let external = countExternalPendingRequests(identifiers: pendingIdentifiers)
        return availableForecastCapacity(
            totalBudget: totalPendingBudget,
            reservedHeadroom: reservedHeadroom,
            pendingSMHI: external.smhi,
            pendingUnrelated: external.unrelated
        )
    }

    /// Reserves shared capacity for already-pending current-frost requests
    /// that are not represented in the freshly generated candidate pool.
    /// Those requests are preserved by the reconciliation plan and must still
    /// consume budget so new alerts cannot overfill the app's queue policy.
    static func selectionCapacity(
        availableCapacity: Int,
        preservedPendingIdentifiers: Set<String>,
        candidateIdentifiers: Set<String>
    ) -> Int {
        let unrepresentedPreserved = preservedPendingIdentifiers.subtracting(candidateIdentifiers).count
        return max(0, max(0, availableCapacity) - unrepresentedPreserved)
    }

    /// Returns stable identifiers in delivery priority order.
    ///
    /// Existing pending current-frost requests are retained even if they
    /// already exceed the supplied capacity: this selector must never silently
    /// cancel an already armed safety alert to satisfy a forecast budget.
    /// Delivered identifiers are excluded unless they are also explicitly
    /// preserved pending requests (a defensive guard for inconsistent input).
    static func select(
        candidates: [WeatherNotificationCandidate],
        capacity: Int,
        deliveredIdentifiers: Set<String> = []
    ) -> [String] {
        let ordered = candidates.sorted(by: comesBefore)
        var seen = Set<String>()
        var preserved: [WeatherNotificationCandidate] = []
        var eligible: [WeatherNotificationCandidate] = []

        for candidate in ordered {
            guard !candidate.identifier.isEmpty,
                  seen.insert(candidate.identifier).inserted else { continue }
            if candidate.isPreservedPendingCurrentFrost {
                preserved.append(candidate)
            } else if !deliveredIdentifiers.contains(candidate.identifier) {
                eligible.append(candidate)
            }
        }

        let remainingCapacity = max(0, capacity - preserved.count)
        return (preserved + eligible.prefix(remainingCapacity)).map(\.identifier)
    }

    private static func comesBefore(
        _ lhs: WeatherNotificationCandidate,
        _ rhs: WeatherNotificationCandidate
    ) -> Bool {
        if lhs.isPreservedPendingCurrentFrost != rhs.isPreservedPendingCurrentFrost {
            return lhs.isPreservedPendingCurrentFrost
        }
        if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
        if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
        if lhs.locationID != rhs.locationID { return lhs.locationID < rhs.locationID }
        return lhs.identifier < rhs.identifier
    }
}

/// Pure reconciliation plan for a single global notification-center snapshot.
/// Non-preserved forecast requests are replaced so refreshed wording and
/// trigger dates take effect; preserved current-frost requests remain untouched.
struct WeatherNotificationReconciliationPlan: Equatable {
    let preservedPendingIdentifiers: [String]
    let pendingIdentifiersToRemove: [String]
    let identifiersToAdd: [String]

    static func make(
        selectedIdentifiers: [String],
        pendingIdentifiers: [String],
        deliveredIdentifiers: Set<String>,
        preservedPendingIdentifiers: Set<String>,
        forecastPrefix: String = "regnvakt.weather."
    ) -> WeatherNotificationReconciliationPlan {
        let pendingForecast = Set(pendingIdentifiers.filter { $0.hasPrefix(forecastPrefix) })
        let preserved = pendingForecast.intersection(preservedPendingIdentifiers).sorted()
        let preservedSet = Set(preserved)
        let toRemove = pendingForecast.subtracting(preservedSet).sorted()

        var seen = Set<String>()
        let toAdd = selectedIdentifiers.filter { identifier in
            identifier.hasPrefix(forecastPrefix) &&
                !preservedSet.contains(identifier) &&
                !deliveredIdentifiers.contains(identifier) &&
                seen.insert(identifier).inserted
        }

        return WeatherNotificationReconciliationPlan(
            preservedPendingIdentifiers: preserved,
            pendingIdentifiersToRemove: toRemove,
            identifiersToAdd: toAdd
        )
    }
}
