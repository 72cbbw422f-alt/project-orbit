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

enum WeatherNotificationBudget {
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
