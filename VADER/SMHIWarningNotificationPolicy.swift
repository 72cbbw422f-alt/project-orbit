import Foundation

enum SMHIWarningNotificationPolicy {
    /// Returns true only for the newest SMHI location-snapshot check.
    static func isCurrentCheck(_ generation: String, storedGeneration: String?) -> Bool {
        storedGeneration == generation
    }

    /// Rejects stale asynchronous inbox refreshes after a newer load has started.
    static func isCurrentInboxLoad(_ generation: UUID, currentGeneration: UUID) -> Bool {
        generation == currentGeneration
    }

    /// Computes the notification transition and the baseline to persist.
    /// Ended warnings are removed; a later reappearance is treated as new.
    static func activeWarningTransition(
        current: Set<String>,
        previous: Set<String>,
        hasBaseline: Bool
    ) -> (newlyActive: Set<String>, retainedBaseline: Set<String>) {
        guard hasBaseline else { return ([], current) }
        // A newly active warning must stay outside the baseline until iOS
        // accepts its notification (or an existing pending request is recovered).
        // Otherwise warnings beyond the eight-request reserve are silently consumed.
        return (current.subtracting(previous), previous.intersection(current))
    }

    /// Gives each SMHI warning-area episode a stable inbox identity.
    /// Notification wording and severity may change while the underlying warning remains the same.
    static func smhiEventFingerprint(warningID: String?, start: String?) -> String? {
        guard let warningID, !warningID.isEmpty,
              let start, !start.isEmpty else { return nil }
        return "smhi|\(warningID)|\(start)"
    }

    /// Retains in-memory notification claims only while their warning remains active.
    /// This lets a warning be notified again if it ends and later reappears.
    static func retainedScheduledSignatures(scheduled: Set<String>, current: Set<String>) -> Set<String> {
        scheduled.intersection(current)
    }

    static func newlyActiveSignatures(current: Set<String>, previous: Set<String>, hasBaseline: Bool) -> Set<String> {
        activeWarningTransition(current: current, previous: previous, hasBaseline: hasBaseline).newlyActive
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
