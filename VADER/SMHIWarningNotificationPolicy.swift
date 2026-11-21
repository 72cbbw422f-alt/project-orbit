import Foundation

enum SMHIWarningNotificationPolicy {
    /// Returns warnings that became active since the last successful baseline.
    /// A missing baseline deliberately returns no notifications: existing active
    /// warnings remain visible in the feed but are not replayed on first launch.
    static func newlyActiveSignatures(
        current: Set<String>,
        previous: Set<String>,
        hasBaseline: Bool
    ) -> Set<String> {
        guard hasBaseline else { return [] }
        return current.subtracting(previous)
    }
}
