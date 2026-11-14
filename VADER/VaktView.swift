import SwiftUI
import UserNotifications

private enum WatchPalette {
    static let cyan = Color(red: 0.04, green: 0.78, blue: 0.98)
    static let muted = Color(red: 0.69, green: 0.78, blue: 0.88)
    static let panel = Color(red: 0.015, green: 0.075, blue: 0.13).opacity(0.94)
    static let line = Color(red: 0.18, green: 0.52, blue: 0.72).opacity(0.48)
}

private struct WatchItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let active: Bool
    let detail: String
    let level: String
    let tint: Color
}

struct VaktDashboard: View {
    @State private var selectedWatch: WatchItem?
    @AppStorage("Regnvakt.smhi.active") private var smhiActive = false
    @AppStorage("Regnvakt.smhi.summary") private var smhiSummary = "Hämtar officiella varningar från SMHI…"
    @AppStorage("Regnvakt.smhi.level") private var smhiLevel = ""
    @AppStorage("Regnvakt.smhi.updated") private var smhiUpdated = ""
    let weather: WeatherSnapshot
    let days: [DayForecast]
    let hours: [HourForecast]

    private var watches: [WatchItem] {
        let upcoming = hours
        let conditions = upcoming.map { $0.condition.lowercased() }
        let rain = upcoming.contains { hour in
            let condition = hour.condition.lowercased()
            let isRain = condition.contains("regn") || condition.contains("duggregn") || condition.contains("skur")
            return isRain && (hour.precipitationChance >= 40 || hour.precipitation >= 0.3)
        }
        let snow = upcoming.contains { hour in
            hour.condition.localizedCaseInsensitiveContains("snö")
                && (hour.precipitationChance >= 40 || hour.precipitation >= 0.2)
        }
        let thunder = conditions.contains { $0.contains("åska") }
        let maxGust = max(weather.windGust, upcoming.map(\.gust).max() ?? days.first?.gust ?? 0)
        let maxWind = max(weather.wind, upcoming.map(\.wind).max() ?? 0)
        let wind = maxGust >= 17 || maxWind >= 11
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

        let frostHour = upcoming.first { hour in
            guard let date = dateFormatter.date(from: hour.id) else { return false }
            let localHour = Calendar.current.component(.hour, from: date)
            let overnight = localHour >= 18 || localHour < 9
            return hour.temperature <= (overnight ? 1 : 0)
        }
        let wetNearFreeze = upcoming.enumerated().first { index, hour in
            guard hour.temperature <= 1 else { return false }
            let condition = hour.condition.lowercased()
            let isWetCondition = condition.contains("regn") || condition.contains("dugg") ||
                condition.contains("skur") || condition.contains("snö") || condition.contains("underkylt")
            let wetNow = hour.precipitation >= 0.2 || (hour.precipitationChance >= 50 && isWetCondition)
            let recentWet = upcoming[..<index].suffix(3).contains { previous in
                let previousCondition = previous.condition.lowercased()
                let previousWetCondition = previousCondition.contains("regn") || previousCondition.contains("dugg") ||
                    previousCondition.contains("skur") || previousCondition.contains("snö") ||
                    previousCondition.contains("underkylt")
                return previous.precipitation >= 0.2 ||
                    (previous.precipitationChance >= 50 && previousWetCondition)
            }
            return wetNow || recentWet || condition.contains("underkylt")
        }?.element
        let frost = frostHour != nil || wetNearFreeze != nil
        let precipitationTitle = snow ? "SNÖVAKTEN" : "REGNVAKTEN"
        let firstPrecipitation = upcoming.first { hour in
            let condition = hour.condition.lowercased()
            let isSnow = condition.contains("snö")
            let isRain = condition.contains("regn") || condition.contains("duggregn") || condition.contains("skur")
            return (isSnow && (hour.precipitationChance >= 40 || hour.precipitation >= 0.2))
                || (isRain && (hour.precipitationChance >= 40 || hour.precipitation >= 0.3))
        }
        let precipitationDetail = firstPrecipitation.map { "\($0.condition) väntas kl. \($0.time)" }
            ?? (snow && rain ? "Snö och regn når aviseringsgränsen i timprognosen"
                : snow ? "Snöfall når aviseringsgränsen i timprognosen"
                : rain ? "Regn når aviseringsgränsen i timprognosen"
                : "Ingen nederbörd når aviseringsgränsen kommande timmar")
        return [
            WatchItem(id: "precipitation", title: precipitationTitle, subtitle: "Nederbörd · regn · snö · duggregn", symbol: snow ? "cloud.snow.fill" : "cloud.rain.fill", active: rain || snow, detail: precipitationDetail, level: rain || snow ? "BEVAKAR" : "LUGNT", tint: WatchPalette.cyan),
            WatchItem(id: "thunder", title: "ÅSKVAKTEN", subtitle: "Åska · blixtar · åskrisk", symbol: "cloud.bolt.rain.fill", active: thunder, detail: thunder ? "Åska förekommer i prognosen" : "Ingen åska identifierad i prognosen", level: thunder ? "RISK I PROGNOS" : "LUGNT", tint: Color.orange),
            WatchItem(id: "wind", title: "VINDVAKTEN", subtitle: "Vindstyrka · hårda vindbyar", symbol: "wind", active: wind, detail: String(format: "Vind upp till %.1f m/s • byvind %.1f m/s", maxWind, maxGust), level: wind ? "FÖRHÖJD VIND" : "LUGNT", tint: Color(red: 0.54, green: 0.72, blue: 1.0)),
            WatchItem(id: "frost", title: "FROSTVAKTEN", subtitle: "Frostbildning · temperatur · separat halkrisk", symbol: "thermometer.snowflake", active: frost, detail: wetNearFreeze.map { "Fukt/nederbörd och cirka \($0.temperature)° omkring kl. \($0.time) – risk för halka" } ?? frostHour.map { "Frostrisk: cirka \($0.temperature)° kl. \($0.time). Frost kan bildas även utan nederbörd." } ?? "Ingen tydlig frostrisk i timprognosen", level: wetNearFreeze != nil ? "HALKRISK" : frost ? "FROSTRISK" : "LUGNT", tint: Color.cyan),
            WatchItem(id: "official", title: "SMHI:S VÄDERVARNINGAR", subtitle: "Officiella vädervarningar för Gävleborgs län", symbol: "exclamationmark.triangle.fill", active: smhiActive, detail: smhiSummary + (smhiUpdated.isEmpty ? "" : " • Uppdaterad " + smhiUpdated), level: smhiActive ? (smhiLevel.isEmpty ? "AKTIV VARNING" : smhiLevel + " VARNING") : "INGEN AKTIV VARNING", tint: Color.yellow)
        ]
    }

    private var activeWatches: [WatchItem] { watches.filter(\.active) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("VÄDERVAKTER").font(.system(size: 28, weight: .black, design: .rounded)).foregroundStyle(.white)
                        Text("BEVAKNING FÖR \(weather.place.uppercased())").font(.system(size: 13, weight: .bold)).tracking(1).foregroundStyle(WatchPalette.muted)
                    }
                    Spacer()
                    Image(systemName: "shield.lefthalf.filled").font(.system(size: 29)).foregroundStyle(WatchPalette.cyan)
                }
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(activeWatches.isEmpty ? "Inga förhöjda risker" : "Risker i prognosen")
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        Text("Väderläge för \(weather.place)")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(WatchPalette.muted)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(activeWatches.count) \(activeWatches.count == 1 ? "aktiv" : "aktiva")")
                            .font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(activeWatches.isEmpty ? WatchPalette.muted : WatchPalette.cyan)
                        Text("PROGNOS")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.8).foregroundStyle(WatchPalette.cyan.opacity(0.85))
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 13)
                .background(WatchPalette.panel, in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(WatchPalette.line, lineWidth: 1))

                ForEach(watches) { watch in
                    watchCard(watch)
                }

                Text("Väderprognosen visar vilka bevakningar som är aktiva. SMHI-varningar är officiella och visas separat när de berör vald plats.")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(WatchPalette.muted).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 3)
                Text("PROGNOS: OPEN-METEO  •  VARNINGAR: SMHI").font(.system(size: 14, weight: .bold)).tracking(0.7).foregroundStyle(WatchPalette.muted.opacity(0.7)).frame(maxWidth: .infinity).padding(.top, 3).padding(.bottom, 20)
            }
            .padding(.horizontal, 14).padding(.top, 22)
        }
        .sheet(item: $selectedWatch) { watch in
            WatchDetailSheet(watch: watch, hours: hours)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(red: 0.008, green: 0.025, blue: 0.055))
                .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder private func watchCard(_ watch: WatchItem) -> some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 15).fill(watch.tint.opacity(0.12))
                Image(systemName: watch.symbol).font(.system(size: 34, weight: .medium)).symbolRenderingMode(.hierarchical).foregroundStyle(watch.tint).shadow(color: watch.tint.opacity(0.4), radius: 10)
            }.frame(width: 76, height: 82)
            VStack(alignment: .leading, spacing: 5) {
                Text(watch.title).font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                Text(watch.subtitle).font(.system(size: 14, weight: .medium)).foregroundStyle(WatchPalette.muted).lineLimit(2)
                Text(watch.detail).font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.88)).lineLimit(2)
                HStack(spacing: 5) { Circle().fill(watch.active ? watch.tint : WatchPalette.muted.opacity(0.55)).frame(width: 6, height: 6).shadow(color: watch.active ? watch.tint : .clear, radius: watch.active ? 6 : 0); Text(watch.level) }.font(.system(size: 13, weight: .heavy)).tracking(0.6).foregroundStyle(watch.active ? watch.tint : WatchPalette.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(10).background(WatchPalette.panel, in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(watch.active ? watch.tint.opacity(0.9) : WatchPalette.line, lineWidth: watch.active ? 1.6 : 1))
        .shadow(color: watch.active ? watch.tint.opacity(0.20) : .black.opacity(0.2), radius: watch.active ? 13 : 10, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: 19))
        .onTapGesture { selectedWatch = watch }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private struct WatchDetailSheet: View {
    let watch: WatchItem
    let hours: [HourForecast]
    @Environment(\.dismiss) private var dismiss
    @State private var notificationStatus = "Kontrollerar schemalagda aviseringar…"
    @State private var testStatus = ""

    private var relevantHours: [HourForecast] {
        if watch.id == "frost" { return hours.filter { $0.temperature <= 1 } }
        if watch.id == "precipitation" { return hours.filter { let c = $0.condition.lowercased(); return c.contains("regn") || c.contains("snö") || c.contains("dugg") || c.contains("skur") } }
        if watch.id == "wind" { return hours.filter { $0.gust >= 17 || $0.wind >= 11 } }
        if watch.id == "thunder" { return hours.filter { $0.condition.localizedCaseInsensitiveContains("åska") } }
        return hours.filter {
            let c = $0.condition.lowercased()
            return c.contains("regn") || c.contains("snö") || c.contains("dugg") || c.contains("skur")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: watch.symbol).font(.system(size: 30, weight: .medium))
                            .foregroundStyle(watch.tint).frame(width: 62, height: 62)
                            .background(watch.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(watch.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(.white)
                            Text(watch.level).font(.system(size: 13, weight: .heavy)).tracking(1).foregroundStyle(watch.tint)
                        }
                        Spacer()
                    }
                    Text(watch.detail).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(WatchPalette.panel, in: RoundedRectangle(cornerRadius: 15))
                    VStack(alignment: .leading, spacing: 9) {
                        Text("KOMMANDE PROGNOSPUNKTER").font(.system(size: 13, weight: .heavy)).tracking(1).foregroundStyle(WatchPalette.cyan)
                        if relevantHours.isEmpty {
                            Text("Inga relevanta händelser hittades i den hämtade timprognosen.").font(.system(size: 15)).foregroundStyle(WatchPalette.muted)
                        } else {
                            ForEach(relevantHours.prefix(12)) { hour in
                                HStack {
                                    Text(hour.time).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                                    Spacer()
                                    Text("\(hour.temperature)°").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                    Text(hour.condition).font(.system(size: 16)).foregroundStyle(WatchPalette.muted)
                                    if watch.id == "frost" {
                                        Text(String(format: "%.1f mm", hour.precipitation)).font(.system(size: 14, weight: .medium)).foregroundStyle(WatchPalette.muted)
                                    }
                                }
                                .padding(.vertical, 5)
                                Divider().overlay(WatchPalette.line)
                            }
                        }
                    }
                    .padding(13).background(WatchPalette.panel, in: RoundedRectangle(cornerRadius: 15))
                    VStack(alignment: .leading, spacing: 7) {
                        Text("LOKALA AVISERINGAR").font(.system(size: 13, weight: .heavy)).tracking(1).foregroundStyle(WatchPalette.cyan)
                        Text(notificationStatus).font(.system(size: 14, weight: .medium)).foregroundStyle(WatchPalette.muted)
                        Button(action: sendTestNotification) {
                            Label("Skicka testavisering om 5 sekunder", systemImage: "bell.badge")
                                .font(.system(size: 13, weight: .bold)).frame(maxWidth: .infinity).padding(12)
                                .background(WatchPalette.cyan.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(WatchPalette.cyan)
                        }.buttonStyle(.plain)
                        if !testStatus.isEmpty { Text(testStatus).font(.system(size: 16)).foregroundStyle(WatchPalette.muted) }
                        Text("Antalet visar väntande notiser i iOS, inte en garanti för att de visas vid exakt tid. Fokus och iOS-inställningar kan påverka leveransen.")
                            .font(.system(size: 16)).foregroundStyle(WatchPalette.muted.opacity(0.85))
                    }
                    .padding(13).background(WatchPalette.panel, in: RoundedRectangle(cornerRadius: 15))
                }.padding(16)
            }
            .navigationTitle("Bevakningsdetaljer").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Stäng") { dismiss() }.foregroundStyle(WatchPalette.cyan) } }
            .task { await loadPendingNotifications() }
        }
    }

    @MainActor private func loadPendingNotifications() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional || settings.authorizationStatus == .ephemeral
        guard allowed else { notificationStatus = "Notisbehörighet saknas eller är avstängd i iPhone."; return }
        let pending = await center.pendingNotificationRequests()
        let matching = pending.filter { request in
            if watch.id == "frost" {
                return request.identifier.hasPrefix("regnvakt.weather.frost.") || request.identifier.hasPrefix("regnvakt.weather.ice.")
            }
            if watch.id == "precipitation" {
                return request.identifier.hasPrefix("regnvakt.weather.rain.") || request.identifier.hasPrefix("regnvakt.weather.snow.")
            }
            return request.identifier.hasPrefix("regnvakt.weather.\(watch.id).")
        }
        notificationStatus = matching.isEmpty ? "Inga väntande aviseringar för den här vakten just nu." : "\(matching.count) väntande avisering(ar) i iOS."
    }

    private func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Regnvakt – test av \(watch.title.lowercased())"
        content.body = "Testavisering. iPhones lokala notiskanal fungerar."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "regnvakt.test.\(watch.id).\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            DispatchQueue.main.async {
                testStatus = error == nil ? "Testavisering schemalagd. Den ska visas om cirka 5 sekunder." : "Kunde inte schemalägga testaviseringen: \(error!.localizedDescription)"
            }
        }
    }
}

struct ActiveWatchSummary: View {
    let weather: WeatherSnapshot
    let days: [DayForecast]
    let hours: [HourForecast]
    @AppStorage("Regnvakt.smhi.active") private var smhiActive = false

    private var activeTitles: [(String, String)] {
        let text = hours.map { $0.condition.lowercased() }.joined(separator: " ")
        var result: [(String, String)] = []
        let snowRisk = hours.contains { $0.condition.localizedCaseInsensitiveContains("snö") && ($0.precipitationChance >= 40 || $0.precipitation >= 0.2) }
        let rainRisk = hours.contains {
            let condition = $0.condition.lowercased()
            let isRain = condition.contains("regn") || condition.contains("duggregn") || condition.contains("skur")
            return isRain && ($0.precipitationChance >= 40 || $0.precipitation >= 0.3)
        }
        if snowRisk { result.append(("SNÖVAKTEN", "cloud.snow.fill")) }
        else if rainRisk { result.append(("REGNVAKTEN", "cloud.rain.fill")) }
        if text.contains("åska") { result.append(("ÅSKVAKTEN", "cloud.bolt.rain.fill")) }

        let gust = max(weather.windGust, hours.map(\.gust).max() ?? days.first?.gust ?? 0)
        if gust >= 17 || max(weather.wind, hours.map(\.wind).max() ?? 0) >= 11 {
            result.append(("VINDVAKTEN", "wind"))
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let nowHour = Calendar.current.component(.hour, from: Date())
        let currentThreshold = (nowHour >= 18 || nowHour < 9) ? 1 : 0
        let currentFrost = weather.temperature <= currentThreshold
        let forecastFrost = hours.contains { hour in
            guard let date = formatter.date(from: hour.id) else { return false }
            let hourOfDay = Calendar.current.component(.hour, from: date)
            let threshold = (hourOfDay >= 18 || hourOfDay < 9) ? 1 : 0
            return hour.temperature <= threshold
        }
        if currentFrost || forecastFrost {
            result.append(("FROSTVAKTEN", "thermometer.snowflake"))
        }
        if smhiActive { result.append(("SMHI-VARNING", "exclamationmark.triangle.fill")) }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("VÄDERVAKTER", systemImage: "shield.lefthalf.filled")
                    .font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                Spacer()
                Text("\(activeTitles.count) \(activeTitles.count == 1 ? "aktiv" : "aktiva")")
                    .font(.system(size: 13, weight: .heavy)).foregroundStyle(WatchPalette.cyan)
            }
            if activeTitles.isEmpty {
                Text("Inga förhöjda risker i prognosen just nu. Vädervakterna är igång.")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(WatchPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 7) {
                    ForEach(Array(activeTitles.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 6) {
                            Image(systemName: item.1).foregroundStyle(WatchPalette.cyan)
                            Text(item.0).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.78)
                            Spacer(minLength: 0)
                        }
                        .font(.system(size: 11, weight: .heavy))
                        .padding(.horizontal, 9).padding(.vertical, 9)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(WatchPalette.line, lineWidth: 1))
                    }
                }
            }
        }
        .padding(12)
        .background(WatchPalette.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(WatchPalette.line, lineWidth: 1))
    }
}
