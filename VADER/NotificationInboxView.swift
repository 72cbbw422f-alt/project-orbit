import SwiftUI
import CoreLocation
import UserNotifications

struct SMHIWarning: Identifiable {
    let id: String
    let title: String
    let level: String
    let area: String
    let start: String
    let end: String
    let description: String
    let advice: String
    var color: Color {
        switch level.lowercased() {
        case let value where value.contains("röd"): return .red
        case let value where value.contains("orange"): return .orange
        case let value where value.contains("gul"): return .yellow
        default: return .cyan
        }
    }
}

private actor SMHIWarningNotificationGate {
    static let shared = SMHIWarningNotificationGate()
    private var scheduled = Set<String>()
    private var inFlight = Set<String>()

    private let persistenceKey = "Regnvakt.smhi.warningSignatures.v1"
    private let notificationEpochKey = "Regnvakt.smhi.notificationEpoch.v1"

    func prepare(current: Set<String>, persisted: Set<String>) {
        // Merge persisted claims instead of replacing actor state. A slower,
        // overlapping refresh must never erase a claim committed by a faster one.
        scheduled.formUnion(persisted.intersection(current))
        // Do not discard in-flight claims based on a possibly stale response.
    }

    func clearScheduled(ifEpoch epoch: String) {
        guard UserDefaults.standard.string(forKey: notificationEpochKey) == epoch else { return }
        scheduled.removeAll()
        UserDefaults.standard.removeObject(forKey: persistenceKey)
    }

    func claim(_ signature: String) -> Bool {
        guard !scheduled.contains(signature), !inFlight.contains(signature) else { return false }
        inFlight.insert(signature)
        return true
    }

    func finish(_ signature: String, accepted: Bool) -> Set<String> {
        inFlight.remove(signature)
        if accepted { scheduled.insert(signature) }
        UserDefaults.standard.set(Array(scheduled), forKey: persistenceKey)
        return scheduled
    }
}

enum SMHIWarningService {
    static let endpoint = URL(string: "https://opendata-download-warnings.smhi.se/ibww/api/version/1/warning.json")!

    static func warnings(at coordinate: CLLocationCoordinate2D) async throws -> [SMHIWarning] {
        try await fetchWarnings(filterCoordinates: [coordinate])
    }

    static func warnings(at coordinates: [CLLocationCoordinate2D]) async throws -> [SMHIWarning] {
        try await fetchWarnings(filterCoordinates: coordinates)
    }

    static func nationwideWarnings() async throws -> [SMHIWarning] {
        try await fetchWarnings(filterCoordinates: nil, includeUpcoming: false)
    }

    private static func fetchWarnings(
        filterCoordinates filterCoordinates: [CLLocationCoordinate2D]?,
        includeUpcoming: Bool = true
    ) async throws -> [SMHIWarning] {
        var request = URLRequest(url: endpoint)
        request.cachePolicy = .reloadRevalidatingCacheData
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        guard let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
        var result: [SMHIWarning] = []
        for item in items {
            let event = item["event"] as? [String: Any] ?? [:]
            let eventName = (event["sv"] as? String) ?? "Vädervarning"
            let warningID = String(describing: item["id"] ?? eventName)
            let areas = item["warningAreas"] as? [[String: Any]] ?? []
            for area in areas {
                // SMHI warning-area "area" is a GeoJSON Feature; the polygon
                // geometry and coordinates are nested inside that feature.
                guard let feature = area["area"] as? [String: Any],
                      let geometry = feature["geometry"] as? [String: Any],
                      let type = geometry["type"] as? String,
                      let coordinates = geometry["coordinates"] else { continue }
                let featureProperties = feature["properties"] as? [String: Any] ?? [:]
                let areaName = (area["areaName"] as? [String: Any])?["sv"] as? String ?? "Berört område"
                let areaCode = featureProperties["code"] as? String ?? ""
                // The GeoJSON area code is the authoritative geographic type.
                // Affected-area IDs are not a safe way to classify all Swedish
                // sea districts (for example, Skagerrak has a different ID range).
                let isMarineArea = areaCode == "SWE_SEA_DISTRICTS" ||
                    areaName.localizedCaseInsensitiveContains("Bottenhavet") ||
                    areaName.localizedCaseInsensitiveContains("Bottenviken") ||
                    areaName.localizedCaseInsensitiveContains("Skagerrak") ||
                    areaName.localizedCaseInsensitiveContains("Kattegatt") ||
                    areaName.localizedCaseInsensitiveContains("Östersjön") ||
                    areaName.localizedCaseInsensitiveContains("Kvarken") ||
                    areaName.localizedCaseInsensitiveContains("Ålands hav") ||
                    areaName.localizedCaseInsensitiveContains("Rigabukten")
                if let filterCoordinates, !filterCoordinates.contains(where: { coordinate in
                    contains(coordinate, geometryType: type, coordinates: coordinates)
                        || isWithinDistance(
                            coordinate,
                            geometryType: type,
                            coordinates: coordinates,
                            maximumDistanceMeters: isMarineArea ? 75_000 : 5_000
                        )
                }) {
                    continue
                }
                let levelObject = area["warningLevel"] as? [String: Any] ?? [:]
                let level = levelObject["sv"] as? String ?? "Meddelande"
                let levelCode = (levelObject["code"] as? String ?? "").uppercased()
                // SMHI also publishes information messages. They are not yellow,
                // orange or red weather warnings and must not be presented as such.
                guard ["YELLOW", "ORANGE", "RED"].contains(levelCode) ||
                      ["gul", "orange", "röd", "rod"].contains(level.lowercased()) else { continue }
                let eventDescription = (area["eventDescription"] as? [String: Any])?["sv"] as? String ?? eventName
                let details = area["descriptions"] as? [[String: Any]] ?? (item["descriptions"] as? [[String: Any]] ?? [])
                func text(for code: String) -> String {
                    guard let entry = details.first(where: { (($0["title"] as? [String: Any])?["code"] as? String) == code }) else { return "" }
                    return (entry["text"] as? [String: Any])?["sv"] as? String ?? ""
                }
                // SMHI's pushNotice controls SMHI's own push channel only.
                // Regnvakt must still display and notify for valid warnings when it is false.
                let start = area["approximateStart"] as? String ?? ""
                let end = area["approximateEnd"] as? String ?? ""
                let startDate = parseSMHIDate(start) ?? .distantPast
                let now = Date()
                if !end.isEmpty, let endDate = parseSMHIDate(end), endDate < now { continue }
                if includeUpcoming {
                    if startDate > now.addingTimeInterval(4 * 24 * 3600) { continue }
                } else if startDate > now {
                    // The national overview is explicitly an active-warning view.
                    continue
                }
                let whereText = text(for: "WHERE").trimmingCharacters(in: .whitespacesAndNewlines)
                let displayArea = whereText.isEmpty ? areaName : whereText
                let areaID = String(describing: area["id"] ?? "\(displayArea)-\(start)")
                result.append(SMHIWarning(id: warningID + "-" + areaID,
                    title: eventDescription.isEmpty ? eventName : eventDescription, level: level, area: displayArea,
                    start: start, end: end, description: text(for: "INCIDENT"), advice: text(for: "AFFECT")))
            }
        }
        return result.sorted { rank($0.level) > rank($1.level) }
    }

    private static let notificationEpochKey = "Regnvakt.smhi.notificationEpoch.v1"
    private static let warningSignaturesKey = "Regnvakt.smhi.warningSignatures.v1"

    static func notificationsReenabled() {
        // Invalidate any asynchronous cleanup that began during the previous opt-out.
        UserDefaults.standard.set(UUID().uuidString, forKey: notificationEpochKey)
    }

    static func clearPendingNotifications() {
        let defaults = UserDefaults.standard
        let epoch = UUID().uuidString
        defaults.set(epoch, forKey: notificationEpochKey)
        defaults.removeObject(forKey: warningSignaturesKey)

        let center = UNUserNotificationCenter.current()
        Task {
            await SMHIWarningNotificationGate.shared.clearScheduled(ifEpoch: epoch)
            let requests = await center.pendingNotificationRequests()
            guard defaults.string(forKey: notificationEpochKey) == epoch else { return }
            let ids = requests.map(\.identifier).filter { $0.hasPrefix("smhi.") }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    static func checkAndNotify(at coordinate: CLLocationCoordinate2D) async {
        await checkAndNotify(at: [coordinate])
    }

    static func checkAndNotify(at coordinates: [CLLocationCoordinate2D]) async {
        let defaults = UserDefaults.standard
        let notificationEpoch = defaults.string(forKey: notificationEpochKey) ?? ""

        // One SMHI payload is evaluated against every active monitored place.
        // This avoids repeated requests and prevents one place's empty result
        // from overwriting a warning found for another place.
        do {
            let current = try await warnings(at: coordinates)
            let now = Date()
            // SMHI may publish a warning several hours before it starts.
            // Keep upcoming items visible in the warning feed, but never mark
            // them active or fire an immediate "active warning" notification.
            let active = current.filter { warning in
                (parseSMHIDate(warning.start) ?? .distantPast) <= now
            }
            let upcoming = current.filter { warning in
                guard let start = parseSMHIDate(warning.start) else { return false }
                return start > now
            }
            defaults.set(!active.isEmpty, forKey: "Regnvakt.smhi.active")
            let activeSummary = active.prefix(2).map { "\($0.title) – \($0.area)" }
            let upcomingSummary = upcoming.prefix(2).map { "Kommande: \($0.title) – \($0.area)" }
            let summary = (activeSummary + upcomingSummary).joined(separator: " • ")
            defaults.set(summary.isEmpty ? "Inga aktiva eller kommande SMHI-varningar nära din plats" : summary,
                         forKey: "Regnvakt.smhi.summary")
            defaults.set(active.first?.level.uppercased() ?? upcoming.first?.level.uppercased() ?? "",
                         forKey: "Regnvakt.smhi.level")

            let updateFormatter = DateFormatter()
            updateFormatter.locale = Locale(identifier: "sv_SE")
            updateFormatter.timeZone = .current
            updateFormatter.dateFormat = "HH:mm"
            defaults.set(updateFormatter.string(from: Date()), forKey: "Regnvakt.smhi.updated")

            // Refresh the national overview independently of notification permissions.
            // A user who disables push alerts must still see current nationwide warnings.
            do {
                let national = try await nationwideWarnings()
                let nationalSignatures = Set(national.map { $0.id + "|" + $0.level + "|" + $0.title })
                let nationalKey = "Regnvakt.smhi.nationalSignatures.v1"
                let previousNational = Set(defaults.stringArray(forKey: nationalKey) ?? [])
                if nationalSignatures.contains(where: { !previousNational.contains($0) }) {
                    defaults.set(true, forKey: "Regnvakt.smhi.hasNewNationalWarnings")
                }
                defaults.set(Array(nationalSignatures), forKey: nationalKey)
            } catch {
                // Preserve the last successful nationwide snapshot/signatures.
            }

            // Notification delivery is a separate concern. Never mark a warning
            // as handled until iOS confirms that the request was accepted.
            guard (defaults.object(forKey: "Regnvakt.notifications.enabled") as? Bool ?? true),
                  (defaults.object(forKey: "Regnvakt.notifications.smhi") as? Bool ?? true),
                  (defaults.string(forKey: notificationEpochKey) ?? "") == notificationEpoch else { return }

            let center = UNUserNotificationCenter.current()
            let authorization = await center.notificationSettings()
            guard authorization.authorizationStatus == .authorized ||
                  authorization.authorizationStatus == .provisional ||
                  authorization.authorizationStatus == .ephemeral else { return }

            let key = "Regnvakt.smhi.warningSignatures.v1"
            let currentSignatures = Set(active.map { $0.id + "|" + $0.level + "|" + $0.title + "|" + $0.start })
            let persistedSignatures = Set(defaults.stringArray(forKey: key) ?? [])
            // The actor serializes claims across overlapping refreshes. A warning
            // is claimed before awaiting UNUserNotificationCenter.add, preventing
            // two concurrent checks from scheduling the same active warning.
            await SMHIWarningNotificationGate.shared.prepare(
                current: currentSignatures,
                persisted: persistedSignatures
            )
            // SMHI notifications are an eight-request reserve inside the app's
            // local-notification headroom. Severity is sorted red, orange, yellow;
            // lower-priority active warnings remain visible and can be notified
            // on a later refresh as higher-priority requests clear.
            let prioritizedActive = active.sorted {
                let left = rank($0.level), right = rank($1.level)
                if left != right { return left > right }
                let leftStart = parseSMHIDate($0.start) ?? .distantPast
                let rightStart = parseSMHIDate($1.start) ?? .distantPast
                if leftStart != rightStart { return leftStart < rightStart }
                return $0.id < $1.id
            }
            let activeNotificationIDs = Set(active.map { warning in
                let safeID = warning.id.replacingOccurrences(
                    of: "[^A-Za-z0-9.-]", with: "-", options: .regularExpression
                )
                return "smhi.\(safeID).\(warning.level)"
            })
            let allPendingRequests = await center.pendingNotificationRequests()
            let pendingSMHIRequests = allPendingRequests.filter { $0.identifier.hasPrefix("smhi.") }
            // Remove queued alerts that no longer affect any currently monitored
            // coordinate, including warnings that ended or belonged to a removed place.
            let staleSMHIIDs = pendingSMHIRequests
                .filter { !activeNotificationIDs.contains($0.identifier) }
                .map(\.identifier)
            if !staleSMHIIDs.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: staleSMHIIDs)
            }
            let currentPendingSMHIRequests = pendingSMHIRequests.filter {
                activeNotificationIDs.contains($0.identifier)
            }
            let pendingSMHIIDs = Set(currentPendingSMHIRequests.map(\.identifier))
            let availableSMHISlots = max(0, 8 - currentPendingSMHIRequests.count)
            var queuedSMHIWarnings = 0
            for warning in prioritizedActive {
                let signature = warning.id + "|" + warning.level + "|" + warning.title + "|" + warning.start
                let safeID = warning.id.replacingOccurrences(
                    of: "[^A-Za-z0-9.-]", with: "-", options: .regularExpression
                )
                let identifier = "smhi.\(safeID).\(warning.level)"

                // Recover a request accepted by iOS just before an app interruption.
                if pendingSMHIIDs.contains(identifier) {
                    if await SMHIWarningNotificationGate.shared.claim(signature) {
                        _ = await SMHIWarningNotificationGate.shared.finish(signature, accepted: true)
                    }
                    continue
                }
                guard queuedSMHIWarnings < availableSMHISlots else { break }
                guard await SMHIWarningNotificationGate.shared.claim(signature) else { continue }

                let content = UNMutableNotificationContent()
                content.title = "SMHI: \(warning.level)"
                content.body = "\(warning.title) – \(warning.area)"
                content.sound = .default
                content.userInfo = ["watch": "smhi", "warningID": warning.id, "area": warning.area]
                let request = UNNotificationRequest(
                    identifier: identifier,
                    content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
                )
                do {
                    try await center.add(request)
                    let stillEnabled = (defaults.object(forKey: "Regnvakt.notifications.enabled") as? Bool ?? true)
                        && (defaults.object(forKey: "Regnvakt.notifications.smhi") as? Bool ?? true)
                        && (defaults.string(forKey: notificationEpochKey) ?? "") == notificationEpoch
                    guard stillEnabled else {
                        center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
                        _ = await SMHIWarningNotificationGate.shared.finish(signature, accepted: false)
                        continue
                    }
                    _ = await SMHIWarningNotificationGate.shared.finish(signature, accepted: true)
                    queuedSMHIWarnings += 1
                    defaults.set(true, forKey: "Regnvakt.notifications.hasUnread")
                } catch {
                    _ = await SMHIWarningNotificationGate.shared.finish(signature, accepted: false)
                    // Leave the signature uncommitted so the next check retries.
                }
            }

        } catch {
            defaults.set("Kunde inte uppdatera SMHI – senast kända status visas",
                         forKey: "Regnvakt.smhi.summary")
            // Preserve previous active state and signatures on fetch failure.
        }
    }
    private static func rank(_ level: String) -> Int {
        let value = level.lowercased()
        if value.contains("röd") { return 3 }; if value.contains("orange") { return 2 }; if value.contains("gul") { return 1 }; return 0
    }

    private static func contains(_ point: CLLocationCoordinate2D, geometryType: String, coordinates: Any) -> Bool {
        guard let raw = coordinates as? [Any] else { return false }
        let polygons: [[[[Double]]]]
        if geometryType == "Polygon" {
            let rings = raw.compactMap { $0 as? [[Double]] }
            polygons = [rings]
        } else if geometryType == "MultiPolygon" {
            polygons = raw.compactMap { polygon in
                guard let parts = polygon as? [Any] else { return nil }
                return parts.compactMap { $0 as? [[Double]] }
            }
        } else { return false }
        return polygons.contains { polygon in
            guard let outer = polygon.first, pointInRing(point, ring: outer) else { return false }
            // GeoJSON interior rings are holes, not part of the warning area.
            return !polygon.dropFirst().contains { pointInRing(point, ring: $0) }
        }
    }

    // Marine warning polygons can sit well offshore from the coast and SMHI's
    // location-based warning presentation includes nearby coastal communities.
    // Apply a 75 km coastal catchment to sea districts nationwide; land warning
    // polygons retain a 5 km GPS/border tolerance to avoid broad false positives.
    private static func isWithinDistance(
        _ point: CLLocationCoordinate2D,
        geometryType: String,
        coordinates: Any,
        maximumDistanceMeters: Double
    ) -> Bool {
        guard let raw = coordinates as? [Any] else { return false }
        // Only each polygon's exterior ring defines its boundary. Interior
        // rings are holes and must not create a false nearby-warning match.
        let outerRings: [[[Double]]]
        if geometryType == "Polygon" {
            guard let outer = raw.first as? [[Double]] else { return false }
            outerRings = [outer]
        } else if geometryType == "MultiPolygon" {
            outerRings = raw.compactMap { polygon in
                guard let parts = polygon as? [Any],
                      let outer = parts.first as? [[Double]] else { return nil }
                return outer
            }
        } else {
            return false
        }

        let latitudeScale = 110_540.0
        let longitudeScale = 111_320.0 * cos(point.latitude * .pi / 180)
        let px = point.longitude * longitudeScale
        let py = point.latitude * latitudeScale

        for ring in outerRings where ring.count >= 2 {
            for index in ring.indices {
                let next = (index + 1) % ring.count
                guard ring[index].count >= 2, ring[next].count >= 2 else { continue }
                let ax = ring[index][0] * longitudeScale
                let ay = ring[index][1] * latitudeScale
                let bx = ring[next][0] * longitudeScale
                let by = ring[next][1] * latitudeScale
                let dx = bx - ax
                let dy = by - ay
                let lengthSquared = dx * dx + dy * dy
                let projection = lengthSquared == 0 ? 0 : max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / lengthSquared))
                let nearestX = ax + projection * dx
                let nearestY = ay + projection * dy
                let distance = hypot(px - nearestX, py - nearestY)
                if distance <= maximumDistanceMeters { return true }
            }
        }
        return false
    }

    private static func pointInRing(_ point: CLLocationCoordinate2D, ring: [[Double]]) -> Bool {
        guard ring.count >= 3 else { return false }
        var inside = false
        var j = ring.count - 1
        for i in ring.indices {
            let xi = ring[i].count > 1 ? ring[i][0] : 0
            let yi = ring[i].count > 1 ? ring[i][1] : 0
            let xj = ring[j].count > 1 ? ring[j][0] : 0
            let yj = ring[j].count > 1 ? ring[j][1] : 0
            if ((yi > point.latitude) != (yj > point.latitude)) &&
                (point.longitude < (xj - xi) * (point.latitude - yi) / ((yj - yi) == 0 ? 0.0000001 : (yj - yi)) + xi) { inside.toggle() }
            j = i
        }
        return inside
    }
}

private func parseSMHIDate(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) { return date }
    let standard = ISO8601DateFormatter()
    standard.formatOptions = [.withInternetDateTime]
    if let date = standard.date(from: value) { return date }
    // Some SMHI payloads omit the timezone suffix; interpret those in Swedish local time.
    let local = DateFormatter()
    local.locale = Locale(identifier: "sv_SE")
    local.timeZone = TimeZone(identifier: "Europe/Stockholm")
    local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return local.date(from: value)
}

struct NotificationInboxView: View {
    let coordinate: CLLocationCoordinate2D?
    let place: String
    @Environment(\.dismiss) private var dismiss
    @State private var warnings: [SMHIWarning] = []
    @State private var delivered: [UNNotification] = []
    @State private var pending: [UNNotificationRequest] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    private let cyan = Color(red: 0.04, green: 0.78, blue: 0.98)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AVISERINGAR").font(.system(size: 29, weight: .black, design: .rounded)).foregroundStyle(.white)
                        Text("Väderhändelser och officiella SMHI-varningar för \(place). Källan anges alltid.").font(.system(size: 15)).foregroundStyle(.white.opacity(0.65))
                    }
                    HStack { Text("SMHI-VARNINGAR").font(.system(size: 16, weight: .heavy)).tracking(1).foregroundStyle(cyan); Spacer(); Button("Uppdatera") { Task { await load() } }.font(.system(size: 15, weight: .bold)).foregroundStyle(cyan) }
                    if isLoading { ProgressView().tint(cyan).frame(maxWidth: .infinity).padding() }
                    if let errorMessage { Text(errorMessage).font(.system(size: 15)).foregroundStyle(.orange) }
                    if !isLoading && warnings.isEmpty && errorMessage == nil {
                        emptyCard("Inga aktiva SMHI-varningar för den här positionen.", icon: "checkmark.shield.fill")
                    }
                    ForEach(warnings) { warning in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack { Text(warning.level.uppercased()).font(.system(size: 15, weight: .black)).tracking(0.8).foregroundStyle(warning.color); Spacer(); Text("SMHI").font(.system(size: 15, weight: .bold)).foregroundStyle(.white.opacity(0.6)) }
                            Text(warning.title).font(.system(size: 19, weight: .bold)).foregroundStyle(.white)
                            Label(warning.area, systemImage: "mappin.and.ellipse").font(.system(size: 15, weight: .semibold)).foregroundStyle(cyan)
                            if !warning.description.isEmpty { Text(warning.description).font(.system(size: 15)).foregroundStyle(.white.opacity(0.85)) }
                            if !warning.advice.isEmpty { Divider().overlay(.white.opacity(0.15)); Text("ATT TÄNKA PÅ").font(.system(size: 15, weight: .heavy)).foregroundStyle(cyan); Text(warning.advice).font(.system(size: 15)).foregroundStyle(.white.opacity(0.8)) }
                            if let startDate = parseSMHIDate(warning.start) {
                                Text("Start: " + startDate.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.65))
                            }
                        }.padding(13).background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(warning.color.opacity(0.5), lineWidth: 1))
                    }
                    Text("SCHEMALAGDA AVISERINGAR").font(.system(size: 16, weight: .heavy)).tracking(1).foregroundStyle(cyan).padding(.top, 4)
                    Text("Här visas aviseringar som iPhone har schemalagt. Direktaviseringar gäller risker som redan pågår. Förvarningar skickas före en möjlig väderhändelse och har därför en annan tid än själva händelsen.").font(.system(size: 16)).foregroundStyle(.white.opacity(0.65)).fixedSize(horizontal: false, vertical: true)
                    if pending.isEmpty { emptyCard("Inga kommande vädernotiser är schemalagda just nu.", icon: "calendar.badge.clock") }
                    ForEach(pending, id: \.identifier) { item in
                        let watch = (item.content.userInfo["watch"] as? String) ?? watchNameFromIdentifier(item.identifier)
                        let isImmediate = (item.content.userInfo["immediate"] as? Bool) ?? false
                        let fireDate = (item.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
                            ?? (item.trigger as? UNTimeIntervalNotificationTrigger).map { Date().addingTimeInterval($0.timeInterval) }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(watchName(from: watch)).font(.system(size: 16, weight: .heavy)).foregroundStyle(cyan)
                            Text(item.content.title).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                            Text(item.content.body).font(.system(size: 15)).foregroundStyle(.white.opacity(0.78))
                            if let fireDate {
                                Label {
                                    Text((isImmediate ? "Avisering: " : "Förvarning: ") + fireDate.formatted(
                                        .dateTime.day().month(.abbreviated).hour().minute()
                                            .locale(Locale(identifier: "sv_SE"))
                                    ))
                                    .font(.system(size: 14, weight: .semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.78)
                                    .allowsTightening(true)
                                } icon: {
                                    Image(systemName: "bell")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if let eventStamp = item.content.userInfo["forecastEventDate"] as? TimeInterval {
                                let eventDate = Date(timeIntervalSince1970: eventStamp)
                                Label("Möjlig väderhändelse: omkring " + eventDate.formatted(date: .omitted, time: .shortened), systemImage: "cloud.sun")
                                    .font(.system(size: 16, weight: .medium)).foregroundStyle(.white.opacity(0.65))
                            } else if item.identifier.hasPrefix("smhi.") {
                                Text("Officiell SMHI-varning").font(.system(size: 16, weight: .medium)).foregroundStyle(.white.opacity(0.65))
                            }
                        }.padding(11).frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                    }
                    HStack {
                        Text("SENASTE AVISERINGAR").font(.system(size: 16, weight: .heavy)).tracking(1).foregroundStyle(cyan)
                        Spacer()
                        if !delivered.isEmpty {
                            Button("Rensa alla") { clearDelivered() }
                                .font(.system(size: 16, weight: .bold)).foregroundStyle(.orange)
                        }
                    }.padding(.top, 4)
                    if delivered.isEmpty { emptyCard("Inga levererade aviseringar ännu.", icon: "bell") }
                    ForEach(delivered, id: \.request.identifier) { item in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.request.content.title).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                                Text(item.request.content.body).font(.system(size: 15)).foregroundStyle(.white.opacity(0.7))
                                Text(item.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 15)).foregroundStyle(.white.opacity(0.45))
                            }
                            Spacer(minLength: 4)
                            Button { removeDelivered(item) } label: {
                                Image(systemName: "trash").font(.system(size: 15, weight: .semibold)).foregroundStyle(.orange).padding(8)
                            }.buttonStyle(.plain)
                        }.padding(11).frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                    }
                    Text("Varningsdata från SMHI:s öppna API. SMHI:s varningstext återges utan ändring.").font(.system(size: 15)).foregroundStyle(.white.opacity(0.5)).padding(.top, 5)
                }.padding(16)
            }.background(Color(red: 0.008, green: 0.025, blue: 0.055))
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Klar") { dismiss() }.foregroundStyle(cyan) } }
            .task { await load() }
        }.preferredColorScheme(.dark)
    }

    private func watchName(from raw: String) -> String {
        switch raw.lowercased() {
        case "rain": return "REGNVAKTEN"
        case "snow": return "SNÖVAKTEN"
        case "wind": return "VINDVAKTEN"
        case "thunder": return "ÅSKVAKTEN"
        case "frost", "ice": return "FROSTVAKTEN"
        case "smhi": return "SMHI"
        default: return raw.uppercased()
        }
    }

    private func watchNameFromIdentifier(_ identifier: String) -> String {
        if identifier.hasPrefix("smhi.") { return "SMHI" }
        let parts = identifier.split(separator: ".")
        guard parts.count > 2 else { return "VÄDERVAKT" }
        return watchName(from: String(parts[2]))
    }

    private func removeDelivered(_ item: UNNotification) {
        let id = item.request.identifier
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        delivered.removeAll { $0.request.identifier == id }
    }

    private func clearDelivered() {
        let ids = delivered.map { $0.request.identifier }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        delivered.removeAll()
    }

    private func emptyCard(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon).font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.7)).frame(maxWidth: .infinity, alignment: .leading).padding(13).background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 13))
    }

    @MainActor private func load() async {
        isLoading = true; errorMessage = nil
        if let coordinate {
            do { warnings = try await SMHIWarningService.warnings(at: coordinate) }
            catch { errorMessage = "Kunde inte hämta SMHI-varningar. Kontrollera anslutningen och försök igen." }
        } else { errorMessage = "Väntar på en giltig position från vädertjänsten." }
        let center = UNUserNotificationCenter.current()
        delivered = await center.deliveredNotifications().sorted { $0.date > $1.date }
        pending = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix("regnvakt.weather.") || $0.identifier.hasPrefix("smhi.") }
            .sorted {
                let a = ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture
                let b = ($1.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture
                return a < b
            }
        isLoading = false
    }
}

struct NationalWarningsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var warnings: [SMHIWarning] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastUpdated: Date?
    private let cyan = Color(red: 0.04, green: 0.78, blue: 0.98)

    private var yellowCount: Int { warnings.filter { $0.level.localizedCaseInsensitiveContains("gul") }.count }
    private var orangeCount: Int { warnings.filter { $0.level.localizedCaseInsensitiveContains("orange") }.count }
    private var redCount: Int { warnings.filter { $0.level.localizedCaseInsensitiveContains("röd") }.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("SVERIGE JUST NU").font(.system(size: 16, weight: .heavy)).tracking(1.4).foregroundStyle(cyan)
                        Text("SMHI-varningar").font(.system(size: 27, weight: .black, design: .rounded)).foregroundStyle(.white)
                        Text("Aktiva vädervarningar i hela Sverige").font(.system(size: 15)).foregroundStyle(.white.opacity(0.65))
                    }
                    HStack(spacing: 8) {
                        levelCount("Gula", count: yellowCount, color: .yellow)
                        levelCount("Orange", count: orangeCount, color: .orange)
                        levelCount("Röda", count: redCount, color: .red)
                    }
                    HStack {
                        Text("AKTIVA VARNINGAR").font(.system(size: 16, weight: .heavy)).tracking(1).foregroundStyle(cyan)
                        Spacer()
                        Button { Task { await load() } } label: {
                            Label("Uppdatera", systemImage: "arrow.clockwise").font(.system(size: 15, weight: .bold))
                        }.foregroundStyle(cyan)
                    }
                    if isLoading { ProgressView().tint(cyan).frame(maxWidth: .infinity).padding() }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "wifi.exclamationmark").font(.system(size: 15)).foregroundStyle(.orange)
                    }
                    if !isLoading && warnings.isEmpty && errorMessage == nil {
                        Label("Inga aktiva SMHI-varningar i Sverige just nu.", systemImage: "checkmark.shield.fill")
                            .font(.system(size: 16, weight: .medium)).foregroundStyle(.green)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(15)
                            .background(Color.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))
                    }
                    ForEach(warnings) { warning in
                        warningCard(warning)
                    }
                    if let lastUpdated {
                        Text("Senast hämtad " + lastUpdated.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 16)).foregroundStyle(.white.opacity(0.45))
                    }
                    Text("Källa: SMHI:s öppna varnings-API. Översikten visar aktiva varningar nationellt och uppdateras när du hämtar information.")
                        .font(.system(size: 16)).foregroundStyle(.white.opacity(0.48))
                }.padding(16)
            }
            .background(Color(red: 0.008, green: 0.025, blue: 0.055))
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Klar") { dismiss() }.foregroundStyle(cyan) } }
            .task { await load() }
        }.preferredColorScheme(.dark)
    }

    private func levelCount(_ title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(count)").font(.system(size: 23, weight: .black, design: .rounded)).foregroundStyle(color)
            Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(.white.opacity(0.75))
        }.frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(color.opacity(0.3), lineWidth: 1))
    }

    private func warningCard(_ warning: SMHIWarning) -> some View {
        let lower = warning.title.lowercased()
        let symbol = lower.contains("vind") ? "wind" : lower.contains("snö") ? "cloud.snow.fill" :
            lower.contains("regn") || lower.contains("nederbörd") ? "cloud.rain.fill" :
            lower.contains("åska") ? "cloud.bolt.rain.fill" :
            lower.contains("is") || lower.contains("halka") ? "car.side.fill" :
            lower.contains("värme") ? "sun.max.fill" : "exclamationmark.triangle.fill"
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(warning.color)
                Text(warning.level.uppercased()).font(.system(size: 15, weight: .black)).tracking(0.9).foregroundStyle(warning.color)
                Spacer()
                Text("SMHI").font(.system(size: 15, weight: .bold)).foregroundStyle(.white.opacity(0.5))
            }
            Text(warning.title).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Label(warning.area, systemImage: "mappin.and.ellipse").font(.system(size: 15, weight: .semibold)).foregroundStyle(cyan)
            if !warning.description.isEmpty { Text(warning.description).font(.system(size: 15)).foregroundStyle(.white.opacity(0.83)) }
            if !warning.advice.isEmpty {
                Divider().overlay(.white.opacity(0.14))
                Text("ATT TÄNKA PÅ").font(.system(size: 15, weight: .heavy)).foregroundStyle(cyan)
                Text(warning.advice).font(.system(size: 15)).foregroundStyle(.white.opacity(0.78))
            }
            if !warning.start.isEmpty {
                            if let startDate = parseSMHIDate(warning.start) {
                Text("Start: " + startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.65))
            }
            }
        }.padding(14).background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(warning.color.opacity(0.5), lineWidth: 1))
    }

    @MainActor private func load() async {
        isLoading = true; errorMessage = nil
        do {
            warnings = try await SMHIWarningService.nationwideWarnings()
            lastUpdated = Date()
        } catch {
            errorMessage = "Kunde inte hämta Sveriges varningar. Kontrollera anslutningen och försök igen."
        }
        isLoading = false
    }
}
