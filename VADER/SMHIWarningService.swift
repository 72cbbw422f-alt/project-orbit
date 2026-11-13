import Foundation
import CoreLocation
import UserNotifications

/// Reads SMHI's official impact-based warning feed. Location matching is county-level,
/// based on the warning feed's affectedAreas metadata.
enum SMHIWarningService {
    private static let feedURL = URL(string: "https://opendata-download-warnings.smhi.se/ibww/api/version/1/warning.json")!
    private static let previousKey = "Regnvakt.smhi.previous.v1"
    private static let activeKey = "Regnvakt.smhi.active"
    private static let summaryKey = "Regnvakt.smhi.summary"
    private static let levelKey = "Regnvakt.smhi.level"
    private static let updatedKey = "Regnvakt.smhi.updated"

    static func checkAndNotify(at coordinate: CLLocationCoordinate2D, county: String? = nil) async {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "Regnvakt.notifications.smhi") as? Bool ?? true else {
            clearPendingNotifications()
            defaults.set(false, forKey: activeKey)
            defaults.set("SMHI-varningar är avstängda", forKey: summaryKey)
            defaults.set("AV", forKey: levelKey)
            return
        }

        do {
            var request = URLRequest(url: feedURL)
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            guard let records = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw URLError(.cannotParseResponse)
            }

            let countyName = county ?? ""
            let now = Date()
            var matches: [[String: Any]] = []
            for record in records {
                guard let areas = record["warningAreas"] as? [[String: Any]] else { continue }
                for area in areas {
                    let affected = area["affectedAreas"] as? [[String: Any]] ?? []
                    let regionMatch = !countyName.isEmpty && affected.contains {
                        normalized(($0["sv"] as? String) ?? "").contains(normalized(countyName)) ||
                        normalized(countyName).contains(normalized(($0["sv"] as? String) ?? ""))
                    }
                    guard regionMatch else { continue }
                    let start = parseDate(area["approximateStart"] as? String)
                    let end = parseDate(area["approximateEnd"] as? String)
                    if let end, end < now { continue }
                    if let start, start > now.addingTimeInterval(4 * 24 * 3600) { continue }
                    var item = area
                    item["event"] = record["event"]
                    item["id"] = area["id"] ?? record["id"]
                    matches.append(item)
                }
            }

            let active = !matches.isEmpty
            let highest = matches.map { (($0["warningLevel"] as? [String: Any])?["code"] as? String) ?? "MESSAGE" }
                .sorted { severity($0) > severity($1) }.first ?? ""
            let summary = matches.prefix(3).map { area -> String in
                let event = (area["eventDescription"] as? [String: Any])?["sv"] as? String ?? "Vädervarning"
                let place = (area["areaName"] as? [String: Any])?["sv"] as? String ?? countyName
                return "\(event) – \(place)"
            }.joined(separator: " • ")

            defaults.set(active, forKey: activeKey)
            defaults.set(active ? summary : "Inga aktiva SMHI-varningar för \(countyName)", forKey: summaryKey)
            defaults.set(levelLabel(highest), forKey: levelKey)
            defaults.set(ISO8601DateFormatter().string(from: now), forKey: updatedKey)

            let old = defaults.dictionary(forKey: previousKey) as? [String: String] ?? [:]
            var current: [String: String] = [:]
            for area in matches {
                let id = String(describing: area["id"] ?? UUID().uuidString)
                let event = (area["eventDescription"] as? [String: Any])?["sv"] as? String ?? "Vädervarning"
                let level = (area["warningLevel"] as? [String: Any])?["code"] as? String ?? "MESSAGE"
                let place = (area["areaName"] as? [String: Any])?["sv"] as? String ?? countyName
                let descriptions = area["descriptions"] as? [[String: Any]] ?? []
                let bodyText = descriptions.compactMap { ($0["text"] as? [String: Any])?["sv"] as? String }.joined(separator: "\n")
                let signature = [event, level, place, bodyText,
                                 area["approximateStart"] as? String ?? "",
                                 area["approximateEnd"] as? String ?? ""].joined(separator: "|")
                current[id] = signature
                if old[id] != signature {
                    let content = UNMutableNotificationContent()
                    content.title = "SMHI: \(levelLabel(level)) varning"
                    content.body = "\(event) – \(place). \(bodyText.prefix(220))"
                    content.sound = .default
                    content.userInfo = ["source": "SMHI", "warningID": id, "level": level]
                    let notification = UNNotificationRequest(
                        identifier: "smhi.warning.\(id)",
                        content: content,
                        trigger: nil
                    )
                    try await UNUserNotificationCenter.current().add(notification)
                }
            }
            defaults.set(current, forKey: previousKey)

            // Remove notifications for warnings that SMHI has withdrawn or ended.
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            let obsolete = pending.filter { $0.identifier.hasPrefix("smhi.warning.") &&
                current[String($0.identifier.dropFirst("smhi.warning.".count))] == nil
            }.map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: obsolete)
        } catch {
            // Keep last known status, but mark it stale rather than falsely showing "no warnings".
            defaults.set("Kunde inte uppdatera SMHI – senast kända status visas", forKey: summaryKey)
        }
    }

    static func clearPendingNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix("smhi.warning.") }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
        UserDefaults.standard.removeObject(forKey: previousKey)
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: value)
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "sv_SE"))
            .replacingOccurrences(of: " län", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func severity(_ code: String) -> Int {
        switch code.uppercased() {
        case "RED": return 4
        case "ORANGE": return 3
        case "YELLOW": return 2
        default: return 1
        }
    }

    private static func levelLabel(_ code: String) -> String {
        switch code.uppercased() {
        case "RED": return "RÖD"
        case "ORANGE": return "ORANGE"
        case "YELLOW": return "GUL"
        case "MESSAGE": return "MEDDELANDE"
        default: return "OKÄND NIVÅ"
        }
    }
}
