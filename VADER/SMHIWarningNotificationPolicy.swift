import Foundation

enum SMHIWarningNotificationPolicy {
    /// Returns true only for the newest SMHI location-snapshot check.
    static func isCurrentCheck(_ generation: String, storedGeneration: String?) -> Bool {
        storedGeneration == generation
    }

    static func newlyActiveSignatures(current: Set<String>, previous: Set<String>, hasBaseline: Bool) -> Set<String> {
        guard hasBaseline else { return [] }
        return current.subtracting(previous)
    }

    /// Parses SMHI timestamps consistently. Timezone-less values are Swedish local time.
    static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = standard.date(from: value) { return date }
        let local = DateFormatter()
        local.locale = Locale(identifier: "sv_SE")
        local.timeZone = TimeZone(identifier: "Europe/Stockholm")
        local.calendar = Calendar(identifier: .gregorian)
        local.isLenient = false
        local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return local.date(from: value)
    }

    static func shouldPresentInForeground(
        level: String, scheduledAt: TimeInterval, start: String, end: String,
        now: Date, maximumAge: TimeInterval = 10 * 60
    ) -> Bool {
        let normalizedLevel = level.lowercased()
        let recognizedLevel = normalizedLevel.contains("gul") || normalizedLevel.contains("orange")
            || normalizedLevel.contains("röd") || normalizedLevel.contains("rod")
        guard recognizedLevel else { return false }
        let age = now.timeIntervalSince1970 - scheduledAt
        guard age >= 0, age <= maximumAge,
              let startDate = parseDate(start), startDate <= now else { return false }
        guard end.isEmpty || (parseDate(end).map { $0 >= now } ?? false) else { return false }
        return true
    }
}
