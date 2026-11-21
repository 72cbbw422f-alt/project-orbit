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
    private var inFlight = [String: UUID]()
    private var currentEpoch = ""

    private let persistenceKey = "Regnvakt.smhi.warningSignatures.v1"
    private let notificationEpochKey = "Regnvakt.smhi.notificationEpoch.v1"

    func prepare(current: Set<String>, persisted: Set<String>, epoch: String, generation: String) {
        let defaults = UserDefaults.standard
        guard (defaults.string(forKey: notificationEpochKey) ?? "") == epoch,
              SMHIWarningNotificationPolicy.isCurrentCheck(
                generation,
                storedGeneration: defaults.string(forKey: "Regnvakt.smhi.checkGeneration.v1")
              ) else { return }
        if currentEpoch != epoch {
            scheduled.removeAll()
            inFlight.removeAll()
            currentEpoch = epoch
        }
        // Keep only recent signatures in memory and on disk. This bounds
        // long-lived state without allowing an overlapping, stale refresh to
        // erase a newer successful claim.
        let cutoff = Date().addingTimeInterval(-90 * 24 * 60 * 60)
        scheduled = Set(scheduled.filter { signatureIsRecent($0, cutoff: cutoff) })
        let recentPersisted = persisted.filter { signatureIsRecent($0, cutoff: cutoff) }
        scheduled.formUnion(recentPersisted.intersection(current))
        UserDefaults.standard.set(Array(scheduled), forKey: persistenceKey)
        // Do not discard in-flight claims based on a possibly stale response.
    }

    private func signatureIsRecent(_ signature: String, cutoff: Date) -> Bool {
        guard let startValue = signature.split(separator: "|", omittingEmptySubsequences: false).last,
              let startDate = SMHIWarningNotificationPolicy.parseDate(String(startValue)) else {
            // Retain unknown legacy signatures rather than risk re-notifying.
            return true
        }
        return startDate >= cutoff
    }

    func clearScheduled(ifEpoch epoch: String) {
        guard UserDefaults.standard.string(forKey: notificationEpochKey) == epoch else { return }
        scheduled.removeAll()
        inFlight.removeAll()
        currentEpoch = epoch
        UserDefaults.standard.removeObject(forKey: persistenceKey)
    }

    func newlyActiveSignatures(current: Set<String>, epoch: String, generation: String) -> Set<String> {
        let defaults = UserDefaults.standard
        guard (defaults.string(forKey: notificationEpochKey) ?? "") == epoch,
              SMHIWarningNotificationPolicy.isCurrentCheck(
                generation,
                storedGeneration: defaults.string(forKey: "Regnvakt.smhi.checkGeneration.v1")
              ) else { return [] }

        let baselineKey = "Regnvakt.smhi.activeWarningBaseline.v1"
        let previousValues = defaults.stringArray(forKey: baselineKey)
        let transition = SMHIWarningNotificationPolicy.activeWarningTransition(
            current: current,
            previous: Set(previousValues ?? []),
            hasBaseline: previousValues != nil
        )
        // Persist only currently active signatures. Newly active signatures
        // remain eligible until a pending request or accepted add records them.
        defaults.set(Array(transition.retainedBaseline).sorted(), forKey: baselineKey)
        return transition.newlyActive
    }

    func recordBaselineSignature(_ signature: String, epoch: String, generation: String) {
        let defaults = UserDefaults.standard
        guard (defaults.string(forKey: notificationEpochKey) ?? "") == epoch,
              SMHIWarningNotificationPolicy.isCurrentCheck(
                generation,
                storedGeneration: defaults.string(forKey: "Regnvakt.smhi.checkGeneration.v1")
              ) else { return }
        let baselineKey = "Regnvakt.smhi.activeWarningBaseline.v1"
        var baseline = Set(defaults.stringArray(forKey: baselineKey) ?? [])
        baseline.insert(signature)
        defaults.set(Array(baseline).sorted(), forKey: baselineKey)
    }

    func claim(_ signature: String, epoch: String) -> UUID? {
        guard (UserDefaults.standard.string(forKey: notificationEpochKey) ?? "") == epoch,
              !scheduled.contains(signature), inFlight[signature] == nil else { return nil }
        let token = UUID()
        inFlight[signature] = token
        return token
    }

    func finish(_ signature: String, token: UUID, epoch: String, accepted: Bool) -> Set<String> {
        guard inFlight[signature] == token else { return scheduled }
        inFlight.removeValue(forKey: signature)
        guard (UserDefaults.standard.string(forKey: notificationEpochKey) ?? "") == epoch else { return scheduled }
        if accepted { scheduled.insert(signature) }
        let cutoff = Date().addingTimeInterval(-90 * 24 * 60 * 60)
        scheduled = scheduled.filter { signatureIsRecent($0, cutoff: cutoff) }
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
        filterCoordinates: [CLLocationCoordinate2D]?,
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
                    areaName.localizedCaseInsensitiveContains("Rigabukten") ||
                    areaName.localizedCaseInsensitiveContains("Skärgårdshavet") ||
                    areaName.localizedCaseInsensitiveContains("Finska Viken") ||
                    areaName.localizedCaseInsensitiveContains("Bälten") ||
                    areaName.localizedCaseInsensitiveContains("Öresund") ||
                    areaName.localizedCaseInsensitiveContains("Vänern")
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
                // Never promote a warning with an absent or malformed start
                // timestamp to an active warning via a distantPast fallback.
                guard let startDate = SMHIWarningNotificationPolicy.parseDate(start) else { continue }
                let now = Date()
                // A supplied end timestamp must also be valid. Otherwise a
                // malformed end could leave an expired warning active forever.
                if !end.isEmpty {
                    guard let endDate = SMHIWarningNotificationPolicy.parseDate(end), endDate >= now else { continue }
                }
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
        // A malformed or repeated payload area must not create duplicate
        // rows for the same SMHI warning-area identity.
        let uniqueByID = Dictionary(result.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return uniqueByID.values.sorted {
            let leftRank = rank($0.level), rightRank = rank($1.level)
            if leftRank != rightRank { return leftRank > rightRank }
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.id < $1.id
        }
    }

    private static let notificationEpochKey = "Regnvakt.smhi.notificationEpoch.v1"
    private static let warningSignaturesKey = "Regnvakt.smhi.warningSignatures.v1"
    private static let checkGenerationKey = "Regnvakt.smhi.checkGeneration.v1"

    /// Starts a new location snapshot evaluation and invalidates older responses.
    static func beginCheck() -> String {
        let generation = UUID().uuidString
        UserDefaults.standard.set(generation, forKey: checkGenerationKey)
        return generation
    }

    static func isCurrentCheck(_ generation: String, storedGeneration: String?) -> Bool {
        SMHIWarningNotificationPolicy.isCurrentCheck(generation, storedGeneration: storedGeneration)
    }

    private static func isCurrentCheck(_ generation: String) -> Bool {
        isCurrentCheck(
            generation,
            storedGeneration: UserDefaults.standard.string(forKey: checkGenerationKey)
        )
    }

    static func notificationsReenabled() {
        // Invalidate any asynchronous cleanup that began during the previous opt-out.
        let epoch = UUID().uuidString
        UserDefaults.standard.set(epoch, forKey: notificationEpochKey)
        UserDefaults.standard.removeObject(forKey: warningSignaturesKey)
        // Reset in-memory deduplication too. If an old request is still pending,
        // the next refresh will recognize it by identifier instead of duplicating it.
        Task {
            await SMHIWarningNotificationGate.shared.clearScheduled(ifEpoch: epoch)
        }
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
        let generation = beginCheck()
        await checkAndNotify(at: [coordinate], generation: generation)
    }

    static func checkAndNotify(at coordinates: [CLLocationCoordinate2D], generation: String) async {
        let defaults = UserDefaults.standard
        let notificationEpoch = defaults.string(forKey: notificationEpochKey) ?? ""
        guard isCurrentCheck(generation) else { return }

        // One SMHI payload is evaluated against every active monitored place.
        // This avoids repeated requests and prevents one place's empty result
        // from overwriting a warning found for another place.
        do {
            let current = try await warnings(at: coordinates)
            guard isCurrentCheck(generation) else { return }
            let now = Date()
            // SMHI may publish a warning several hours before it starts.
            // Keep upcoming items visible in the warning feed, but never mark
            // them active or fire an immediate "active warning" notification.
            let active = current.filter { warning in
                guard let start = SMHIWarningNotificationPolicy.parseDate(warning.start) else { return false }
                return start <= now
            }
            let upcoming = current.filter { warning in
                guard let start = SMHIWarningNotificationPolicy.parseDate(warning.start) else { return false }
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
                guard isCurrentCheck(generation) else { return }
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
            guard isCurrentCheck(generation) else { return }
            guard authorization.authorizationStatus == .authorized ||
                  authorization.authorizationStatus == .provisional ||
                  authorization.authorizationStatus == .ephemeral else { return }

            let key = "Regnvakt.smhi.warningSignatures.v1"
            let currentSignatures = Set(active.map { $0.id + "|" + $0.level + "|" + $0.title + "|" + $0.start })
            let persistedSignatures = Set(defaults.stringArray(forKey: key) ?? [])
            // The actor serializes claims across overlapping refreshes. A warning
            // is claimed before awaiting UNUserNotificationCenter.add, preventing
            // two concurrent checks from scheduling the same active warning.
            let newlyActiveSignatures = await SMHIWarningNotificationGate.shared.newlyActiveSignatures(
                current: currentSignatures,
                epoch: notificationEpoch,
                generation: generation
            )
            guard isCurrentCheck(generation) else { return }
            await SMHIWarningNotificationGate.shared.prepare(
                current: currentSignatures,
                persisted: persistedSignatures,
                epoch: notificationEpoch,
                generation: generation
            )
            guard isCurrentCheck(generation) else { return }
            // Existing active warnings are retained in the feed, but only a
            // warning newly observed since the baseline can create a new alert.
            // This prevents app activation from replaying an old active warning.
            let newlyActive = active.filter {
                currentSignatures.contains($0.id + "|" + $0.level + "|" + $0.title + "|" + $0.start)
                    && newlyActiveSignatures.contains($0.id + "|" + $0.level + "|" + $0.title + "|" + $0.start)
            }
            // SMHI notifications are an eight-request reserve inside the app's
            // local-notification headroom. Severity is sorted red, orange, yellow;
            // lower-priority active warnings remain visible and can be notified
            // on a later refresh as higher-priority requests clear.
            let prioritizedActive = newlyActive.sorted {
                let left = rank($0.level), right = rank($1.level)
                if left != right { return left > right }
                let leftStart = SMHIWarningNotificationPolicy.parseDate($0.start) ?? .distantPast
                let rightStart = SMHIWarningNotificationPolicy.parseDate($1.start) ?? .distantPast
                if leftStart != rightStart { return leftStart < rightStart }
                return $0.id < $1.id
            }
            let activeNotificationIDs = Set(active.map {
                notificationIdentifier(for: $0, epoch: notificationEpoch)
            })
            let allPendingRequests = await center.pendingNotificationRequests()
            guard isCurrentCheck(generation),
                  (defaults.string(forKey: notificationEpochKey) ?? "") == notificationEpoch else { return }
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
                guard isCurrentCheck(generation),
                      (defaults.string(forKey: notificationEpochKey) ?? "") == notificationEpoch else { return }
                let signature = warning.id + "|" + warning.level + "|" + warning.title + "|" + warning.start
                let identifier = notificationIdentifier(for: warning, epoch: notificationEpoch)

                // Recover a request accepted by iOS just before an app interruption.
                if pendingSMHIIDs.contains(identifier) {
                    await SMHIWarningNotificationGate.shared.recordBaselineSignature(signature, epoch: notificationEpoch, generation: generation)
                    if let claimToken = await SMHIWarningNotificationGate.shared.claim(signature, epoch: notificationEpoch) {
                        _ = await SMHIWarningNotificationGate.shared.finish(signature, token: claimToken, epoch: notificationEpoch, accepted: true)
                    }
                    continue
                }
                guard queuedSMHIWarnings < availableSMHISlots else { break }
                guard let claimToken = await SMHIWarningNotificationGate.shared.claim(signature, epoch: notificationEpoch) else { continue }

                let content = UNMutableNotificationContent()
                content.title = "SMHI: \(warning.level)"
                content.body = "\(warning.title) – \(warning.area)"
                content.sound = .default
                content.userInfo = ["watch": "smhi", "warningID": warning.id, "area": warning.area, "level": warning.level, "start": warning.start, "end": warning.end, "scheduledAt": Date().timeIntervalSince1970]
                let request = UNNotificationRequest(
                    identifier: identifier,
                    content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
                )
                do {
                    try await center.add(request)
                    guard isCurrentCheck(generation) else {
                        center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
                        _ = await SMHIWarningNotificationGate.shared.finish(signature, token: claimToken, epoch: notificationEpoch, accepted: false)
                        return
                    }
                    let stillEnabled = (defaults.object(forKey: "Regnvakt.notifications.enabled") as? Bool ?? true)
                        && (defaults.object(forKey: "Regnvakt.notifications.smhi") as? Bool ?? true)
                        && (defaults.string(forKey: notificationEpochKey) ?? "") == notificationEpoch
                    guard stillEnabled else {
                        center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
                        _ = await SMHIWarningNotificationGate.shared.finish(signature, token: claimToken, epoch: notificationEpoch, accepted: false)
                        continue
                    }
                    _ = await SMHIWarningNotificationGate.shared.finish(signature, token: claimToken, epoch: notificationEpoch, accepted: true)
                    await SMHIWarningNotificationGate.shared.recordBaselineSignature(signature, epoch: notificationEpoch, generation: generation)
                    queuedSMHIWarnings += 1
                    defaults.set(true, forKey: "Regnvakt.notifications.hasUnread")
                } catch {
                    _ = await SMHIWarningNotificationGate.shared.finish(signature, token: claimToken, epoch: notificationEpoch, accepted: false)
                    // Leave the signature uncommitted so the next check retries.
                }
            }

        } catch {
            defaults.set("Kunde inte uppdatera SMHI – senast kända status visas",
                         forKey: "Regnvakt.smhi.summary")
            // Preserve previous active state and signatures on fetch failure.
        }
    }
    // Include the full warning signature in a deterministic, compact ID.
    // A title change must not be mistaken for an already-pending old notification.
    private static func notificationIdentifier(for warning: SMHIWarning, epoch: String) -> String {
        let signature = warning.id + "|" + warning.level + "|" + warning.title + "|" + warning.start
        let hash = signature.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
        }
        let hex = String(hash, radix: 16)
        let paddedHash = String(repeating: "0", count: max(0, 16 - hex.count)) + hex
        let safeEpoch = epoch.isEmpty ? "initial" : epoch
        return "smhi.\(paddedHash).\(safeEpoch)"
    }

    private static func rank(_ level: String) -> Int {
        let value = level.lowercased()
        if value.contains("röd") { return 3 }; if value.contains("orange") { return 2 }; if value.contains("gul") { return 1 }; return 0
    }

    // Parse GeoJSON coordinates strictly. A single malformed vertex must
    // invalidate its ring rather than silently becoming longitude/latitude 0.
    private static func validatedRing(_ raw: Any) -> [[Double]]? {
        guard let positions = raw as? [Any], positions.count >= 3 else { return nil }
        var ring: [[Double]] = []
        ring.reserveCapacity(positions.count)
        for position in positions {
            guard let values = position as? [Any], values.count >= 2,
                  let longitude = values[0] as? NSNumber,
                  let latitude = values[1] as? NSNumber else { return nil }
            let lon = longitude.doubleValue
            let lat = latitude.doubleValue
            guard lon.isFinite, lat.isFinite,
                  (-180.0...180.0).contains(lon),
                  (-90.0...90.0).contains(lat) else { return nil }
            ring.append([lon, lat])
        }
        return ring
    }

    private static func validatedPolygons(geometryType: String, coordinates: Any) -> [[[[Double]]]]? {
        guard let raw = coordinates as? [Any] else { return nil }
        let polygonValues: [[Any]]
        switch geometryType {
        case "Polygon":
            polygonValues = [raw]
        case "MultiPolygon":
            polygonValues = raw.compactMap { $0 as? [Any] }
            guard polygonValues.count == raw.count else { return nil }
        default:
            return nil
        }

        var polygons: [[[[Double]]]] = []
        polygons.reserveCapacity(polygonValues.count)
        for polygon in polygonValues {
            guard !polygon.isEmpty else { return nil }
            let rings = polygon.compactMap { validatedRing($0) }
            guard rings.count == polygon.count, !rings.isEmpty else { return nil }
            polygons.append(rings)
        }
        return polygons.isEmpty ? nil : polygons
    }

    private static func contains(_ point: CLLocationCoordinate2D, geometryType: String, coordinates: Any) -> Bool {
        guard let polygons = validatedPolygons(geometryType: geometryType, coordinates: coordinates) else {
            return false
        }
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
        guard let polygons = validatedPolygons(geometryType: geometryType, coordinates: coordinates) else {
            return false
        }
        // Only each polygon's exterior ring defines its boundary. Interior
        // rings are holes and must not create a false nearby-warning match.
        let outerRings = polygons.compactMap(\.first)

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
            let xi = ring[i][0]
            let yi = ring[i][1]
            let xj = ring[j][0]
            let yj = ring[j][1]
            if ((yi > point.latitude) != (yj > point.latitude)) &&
                (point.longitude < (xj - xi) * (point.latitude - yi) / ((yj - yi) == 0 ? 0.0000001 : (yj - yi)) + xi) { inside.toggle() }
            j = i
        }
        return inside
    }
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
                            if let startDate = SMHIWarningNotificationPolicy.parseDate(warning.start) {
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

    private func eventFingerprint(_ content: UNNotificationContent, fallbackDate: Date) -> String {
        let info = content.userInfo
        let watch = (info["watch"] as? String) ?? content.title
        let place = (info["place"] as? String) ?? ""
        if watch == "frost" || watch == "ice" {
            // Frost and ice alerts repeated across forecast refreshes describe
            // one safety episode per place and Swedish calendar day.
            let day = (info["alertDay"] as? Date) ?? fallbackDate
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
            let components = calendar.dateComponents([.year, .month, .day], from: day)
            return "\(watch)|\(place)|\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
        }
        if let stamp = info["forecastEventDate"] as? TimeInterval {
            // Forecast refreshes can recreate the same event with slightly
            // different timestamps and notification IDs. Use the displayed
            // event description as well as its local hour to collapse copies.
            let hour = Int(stamp / 3600)
            // Forecast refreshes may change probability/wording while describing
            // the same watch, place and event hour. Those are one inbox event.
            return "\(watch)|\(place)|\(hour)"
        }
        let normalizedBody = content.body
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return "\(watch)|\(place)|\(content.title.lowercased())|\(normalizedBody)"
    }

    @MainActor private func load() async {
        isLoading = true
        errorMessage = nil
        if let coordinate {
            do { warnings = try await SMHIWarningService.warnings(at: coordinate) }
            catch { errorMessage = "Kunde inte hämta SMHI-varningar. Kontrollera anslutningen och försök igen." }
        } else {
            errorMessage = "Väntar på en giltig position från vädertjänsten."
        }

        let center = UNUserNotificationCenter.current()
        let allDelivered = await center.deliveredNotifications().sorted { $0.date > $1.date }
        let allPending = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix("regnvakt.weather.") || $0.identifier.hasPrefix("smhi.") }
            .sorted {
                let a = ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
                    ?? ($0.trigger as? UNTimeIntervalNotificationTrigger).map { Date().addingTimeInterval($0.timeInterval) }
                    ?? .distantFuture
                let b = ($1.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
                    ?? ($1.trigger as? UNTimeIntervalNotificationTrigger).map { Date().addingTimeInterval($0.timeInterval) }
                    ?? .distantFuture
                return a < b
            }

        // A single semantic event can survive under different notification IDs
        // after a forecast refresh. Share one key set across delivered and
        // pending lists so the inbox never presents the same event twice.
        var seen = Set<String>()
        delivered = allDelivered.filter { item in
            let key = eventFingerprint(item.request.content, fallbackDate: item.date)
            return seen.insert(key).inserted
        }
        pending = allPending.filter { request in
            let fallback = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
                ?? (request.trigger as? UNTimeIntervalNotificationTrigger).map { Date().addingTimeInterval($0.timeInterval) }
                ?? Date()
            let key = eventFingerprint(request.content, fallbackDate: fallback)
            return seen.insert(key).inserted
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
                            if let startDate = SMHIWarningNotificationPolicy.parseDate(warning.start) {
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
