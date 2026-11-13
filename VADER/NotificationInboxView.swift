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

enum SMHIWarningService {
    static let endpoint = URL(string: "https://opendata-download-warnings.smhi.se/ibww/api/version/1/warning.json")!

    static func warnings(at coordinate: CLLocationCoordinate2D) async throws -> [SMHIWarning] {
        try await fetchWarnings(filterCoordinate: coordinate)
    }

    static func nationwideWarnings() async throws -> [SMHIWarning] {
        try await fetchWarnings(filterCoordinate: nil)
    }

    private static func fetchWarnings(filterCoordinate coordinate: CLLocationCoordinate2D?) async throws -> [SMHIWarning] {
        var request = URLRequest(url: endpoint)
        request.cachePolicy = .reloadRevalidatingCacheData
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        guard let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
        var result: [SMHIWarning] = []
        for item in items {
            let warningID = String(describing: item["id"] ?? UUID().uuidString)
            let event = item["event"] as? [String: Any] ?? [:]
            let eventName = (event["sv"] as? String) ?? "Vädervarning"
            let areas = item["warningAreas"] as? [[String: Any]] ?? []
            for area in areas {
                guard let geometryRoot = area["area"] as? [String: Any],
                      let geometry = geometryRoot["geometry"] as? [String: Any],
                      let type = geometry["type"] as? String,
                      let coordinates = geometry["coordinates"] else { continue }
                if let coordinate, !contains(coordinate, geometryType: type, coordinates: coordinates) { continue }
                let levelObject = area["warningLevel"] as? [String: Any] ?? [:]
                let level = levelObject["sv"] as? String ?? "Meddelande"
                let areaName = (area["areaName"] as? [String: Any])?["sv"] as? String ?? "Berört område"
                let eventDescription = (area["eventDescription"] as? [String: Any])?["sv"] as? String ?? eventName
                let details = area["descriptions"] as? [[String: Any]] ?? (item["descriptions"] as? [[String: Any]] ?? [])
                func text(for code: String) -> String {
                    guard let entry = details.first(where: { (($0["title"] as? [String: Any])?["code"] as? String) == code }) else { return "" }
                    return (entry["text"] as? [String: Any])?["sv"] as? String ?? ""
                }
                let start = area["approximateStart"] as? String ?? ""
                let end = area["approximateEnd"] as? String ?? ""
                let published = area["published"] as? String ?? ""
                let startDate = ISO8601DateFormatter().date(from: start) ?? .distantPast
                if !end.isEmpty, let endDate = ISO8601DateFormatter().date(from: end), endDate < Date() { continue }
                if startDate > Date().addingTimeInterval(4 * 24 * 3600) { continue }
                result.append(SMHIWarning(id: warningID + "-" + String(describing: area["id"] ?? "area"),
                    title: eventDescription.isEmpty ? eventName : eventDescription, level: level, area: areaName,
                    start: start, end: end, description: text(for: "INCIDENT"), advice: text(for: "AFFECT")))
                _ = published
            }
        }
        return result.sorted { rank($0.level) > rank($1.level) }
    }

    static func checkAndNotify(at coordinate: CLLocationCoordinate2D) async {
        guard (UserDefaults.standard.object(forKey: "Regnvakt.notifications.enabled") as? Bool ?? true),
              (UserDefaults.standard.object(forKey: "Regnvakt.notifications.smhi") as? Bool ?? true) else { return }
        do {
            let current = try await warnings(at: coordinate)
            let national = try await nationwideWarnings()
            let signatures = Set(current.map { $0.id + "|" + $0.level + "|" + $0.title })
            let nationalSignatures = Set(national.map { $0.id + "|" + $0.level + "|" + $0.title })
            let nationalKey = "Regnvakt.smhi.nationalSignatures.v1"
            if let previousNational = UserDefaults.standard.stringArray(forKey: nationalKey) {
                let oldNational = Set(previousNational)
                if nationalSignatures.contains(where: { !oldNational.contains($0) }) {
                    UserDefaults.standard.set(true, forKey: "Regnvakt.smhi.hasNewNationalWarnings")
                }
            }
            UserDefaults.standard.set(Array(nationalSignatures), forKey: nationalKey)
            let key = "Regnvakt.smhi.warningSignatures.v1"
            if let previous = UserDefaults.standard.stringArray(forKey: key) {
                let old = Set(previous)
                for warning in current where !old.contains(warning.id + "|" + warning.level + "|" + warning.title) {
                    let content = UNMutableNotificationContent()
                    content.title = "SMHI: \(warning.level)"
                    content.body = "\(warning.title) – \(warning.area)"
                    content.sound = .default
                    let request = UNNotificationRequest(identifier: "smhi-\(warning.id)-\(warning.level)", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
                    try? await UNUserNotificationCenter.current().add(request)
                }
            }
            UserDefaults.standard.set(Array(signatures), forKey: key)
        } catch { }
    }
    private static func rank(_ level: String) -> Int {
        let value = level.lowercased()
        if value.contains("röd") { return 3 }; if value.contains("orange") { return 2 }; if value.contains("gul") { return 1 }; return 0
    }

    private static func contains(_ point: CLLocationCoordinate2D, geometryType: String, coordinates: Any) -> Bool {
        guard let raw = coordinates as? [Any] else { return false }
        let polygons: [[[Double]]]
        if geometryType == "Polygon" {
            guard let ring = raw.first as? [[Double]] else { return false }
            polygons = [ring]
        } else if geometryType == "MultiPolygon" {
            polygons = raw.compactMap { polygon in
                guard let first = polygon as? [Any], let ring = first.first as? [[Double]] else { return nil }; return ring
            }
        } else { return false }
        return polygons.contains { pointInRing(point, ring: $0) }
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

struct NotificationInboxView: View {
    let coordinate: CLLocationCoordinate2D?
    let place: String
    @Environment(\.dismiss) private var dismiss
    @State private var warnings: [SMHIWarning] = []
    @State private var delivered: [UNNotification] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    private let cyan = Color(red: 0.04, green: 0.78, blue: 0.98)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AVISERINGAR").font(.system(size: 24, weight: .black, design: .rounded)).foregroundStyle(.white)
                        Text("Väderhändelser och officiella SMHI-varningar för \(place). Källan anges alltid.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                    }
                    HStack { Text("SMHI-VARNINGAR").font(.system(size: 10, weight: .heavy)).tracking(1).foregroundStyle(cyan); Spacer(); Button("Uppdatera") { Task { await load() } }.font(.system(size: 11, weight: .bold)).foregroundStyle(cyan) }
                    if isLoading { ProgressView().tint(cyan).frame(maxWidth: .infinity).padding() }
                    if let errorMessage { Text(errorMessage).font(.system(size: 12)).foregroundStyle(.orange) }
                    if !isLoading && warnings.isEmpty && errorMessage == nil {
                        emptyCard("Inga aktiva SMHI-varningar för den här positionen.", icon: "checkmark.shield.fill")
                    }
                    ForEach(warnings) { warning in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack { Text(warning.level.uppercased()).font(.system(size: 9, weight: .black)).tracking(0.8).foregroundStyle(warning.color); Spacer(); Text("SMHI").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.6)) }
                            Text(warning.title).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                            Label(warning.area, systemImage: "mappin.and.ellipse").font(.system(size: 11, weight: .semibold)).foregroundStyle(cyan)
                            if !warning.description.isEmpty { Text(warning.description).font(.system(size: 11)).foregroundStyle(.white.opacity(0.85)) }
                            if !warning.advice.isEmpty { Divider().overlay(.white.opacity(0.15)); Text("ATT TÄNKA PÅ").font(.system(size: 9, weight: .heavy)).foregroundStyle(cyan); Text(warning.advice).font(.system(size: 11)).foregroundStyle(.white.opacity(0.8)) }
                            if !warning.start.isEmpty { Text("Start: \(warning.start)").font(.system(size: 9)).foregroundStyle(.white.opacity(0.55)) }
                        }.padding(13).background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(warning.color.opacity(0.5), lineWidth: 1))
                    }
                    Text("SENASTE AVISERINGAR").font(.system(size: 10, weight: .heavy)).tracking(1).foregroundStyle(cyan).padding(.top, 4)
                    if delivered.isEmpty { emptyCard("Inga levererade aviseringar ännu.", icon: "bell") }
                    ForEach(delivered, id: \.request.identifier) { item in
                        VStack(alignment: .leading, spacing: 4) { Text(item.request.content.title).font(.system(size: 13, weight: .bold)).foregroundStyle(.white); Text(item.request.content.body).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)); Text(item.date, style: .date).font(.system(size: 9)).foregroundStyle(.white.opacity(0.45)) }.padding(11).frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                    }
                    Text("Varningsdata från SMHI:s öppna API. SMHI:s varningstext återges utan ändring.").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5)).padding(.top, 5)
                }.padding(16)
            }.background(Color(red: 0.008, green: 0.025, blue: 0.055))
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Klar") { dismiss() }.foregroundStyle(cyan) } }
            .task { await load() }
        }.preferredColorScheme(.dark)
    }

    private func emptyCard(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.7)).frame(maxWidth: .infinity, alignment: .leading).padding(13).background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 13))
    }

    @MainActor private func load() async {
        isLoading = true; errorMessage = nil
        if let coordinate {
            do { warnings = try await SMHIWarningService.warnings(at: coordinate) }
            catch { errorMessage = "Kunde inte hämta SMHI-varningar. Kontrollera anslutningen och försök igen." }
        } else { errorMessage = "Väntar på en giltig position från vädertjänsten." }
        delivered = await UNUserNotificationCenter.current().deliveredNotifications().sorted { $0.date > $1.date }
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
                        Text("SVERIGE JUST NU").font(.system(size: 10, weight: .heavy)).tracking(1.4).foregroundStyle(cyan)
                        Text("SMHI-varningar").font(.system(size: 27, weight: .black, design: .rounded)).foregroundStyle(.white)
                        Text("Aktiva vädervarningar i hela Sverige").font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                    }
                    HStack(spacing: 8) {
                        levelCount("Gula", count: yellowCount, color: .yellow)
                        levelCount("Orange", count: orangeCount, color: .orange)
                        levelCount("Röda", count: redCount, color: .red)
                    }
                    HStack {
                        Text("AKTIVA VARNINGAR").font(.system(size: 10, weight: .heavy)).tracking(1).foregroundStyle(cyan)
                        Spacer()
                        Button { Task { await load() } } label: {
                            Label("Uppdatera", systemImage: "arrow.clockwise").font(.system(size: 11, weight: .bold))
                        }.foregroundStyle(cyan)
                    }
                    if isLoading { ProgressView().tint(cyan).frame(maxWidth: .infinity).padding() }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "wifi.exclamationmark").font(.system(size: 12)).foregroundStyle(.orange)
                    }
                    if !isLoading && warnings.isEmpty && errorMessage == nil {
                        Label("Inga aktiva SMHI-varningar i Sverige just nu.", systemImage: "checkmark.shield.fill")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(.green)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(15)
                            .background(Color.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))
                    }
                    ForEach(warnings) { warning in
                        warningCard(warning)
                    }
                    if let lastUpdated {
                        Text("Senast hämtad " + lastUpdated.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                    }
                    Text("Källa: SMHI:s öppna varnings-API. Översikten visar aktiva varningar nationellt och uppdateras när du hämtar information.")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.48))
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
            Text(title).font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.75))
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
                Text(warning.level.uppercased()).font(.system(size: 9, weight: .black)).tracking(0.9).foregroundStyle(warning.color)
                Spacer()
                Text("SMHI").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.5))
            }
            Text(warning.title).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Label(warning.area, systemImage: "mappin.and.ellipse").font(.system(size: 11, weight: .semibold)).foregroundStyle(cyan)
            if !warning.description.isEmpty { Text(warning.description).font(.system(size: 11)).foregroundStyle(.white.opacity(0.83)) }
            if !warning.advice.isEmpty {
                Divider().overlay(.white.opacity(0.14))
                Text("ATT TÄNKA PÅ").font(.system(size: 9, weight: .heavy)).foregroundStyle(cyan)
                Text(warning.advice).font(.system(size: 11)).foregroundStyle(.white.opacity(0.78))
            }
            if !warning.start.isEmpty {
                Text("Start: " + warning.start).font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
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
