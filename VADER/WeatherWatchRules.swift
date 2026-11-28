import Foundation

enum WeatherWatchRules {
    static let forecastHorizonHours: TimeInterval = 8
    static let notificationHorizonHours: TimeInterval = 24
    static let windGustThreshold = 15.0

    /// Stable forecast identity distinguishes the repeated local hour at the autumn clock change.
    static func forecastHourIdentifier(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
        formatter.dateFormat = "yyyyMMddHHmmXXX"
        return formatter.string(from: date)
    }

    static func forecastHorizon(from date: Date) -> Date {
        date.addingTimeInterval(forecastHorizonHours * 60 * 60)
    }

    static func notificationForecastHorizon(from date: Date) -> Date {
        date.addingTimeInterval(notificationHorizonHours * 60 * 60)
    }

    /// A response may update a watch only if no later enable/disable action
    /// has replaced the generation captured when its request began.
    static func isCurrentMonitoringGeneration(expected: String?, current: String?) -> Bool {
        expected == current
    }

    /// Determines whether an event can claim the first-alert slot for its risk
    /// type. Routine alerts need their configured lead time. Safety-critical
    /// forecast events may still claim the slot after the lead time has passed;
    /// the notification scheduler arms them for the forecast event time.
    static func canScheduleForecastEvent(
        eventDate: Date,
        safetyCritical: Bool,
        leadMinutes: Int,
        now: Date,
        quietHours: String,
        minimumLeadTime: TimeInterval = 30
    ) -> Bool {
        let plannedFireDate = eventDate.addingTimeInterval(-Double(max(0, leadMinutes)) * 60)
        let safetyEventPastLeadTime = safetyCritical &&
            plannedFireDate <= now.addingTimeInterval(max(0, minimumLeadTime))
        let fireDate = plannedFireDate
        guard safetyEventPastLeadTime || fireDate > now.addingTimeInterval(max(0, minimumLeadTime)) else {
            return false
        }
        return safetyCritical || !isQuietTime(fireDate, setting: quietHours)
    }

    static func isQuietTime(_ date: Date, setting: String) -> Bool {
        guard setting != "none" else { return false }
        let parts = setting.split(separator: "–").compactMap { Int($0) }
        guard parts.count == 2,
              (0...23).contains(parts[0]),
              (0...23).contains(parts[1]),
              parts[0] != parts[1] else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
        let hour = calendar.component(.hour, from: date)
        let start = parts[0], end = parts[1]
        return start < end ? (hour >= start && hour < end) : (hour >= start || hour < end)
    }
}
