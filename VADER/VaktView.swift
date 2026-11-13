import SwiftUI

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
    let weather: WeatherSnapshot
    let days: [DayForecast]
    let hours: [HourForecast]

    private var watches: [WatchItem] {
        let upcoming = hours
        let conditions = upcoming.map { $0.condition.lowercased() }
        let rain = conditions.contains { $0.contains("regn") || $0.contains("duggregn") || $0.contains("skur") }
        let snow = conditions.contains { $0.contains("snö") }
        let thunder = conditions.contains { $0.contains("åska") }
        let maxGust = max(weather.windGust, upcoming.map(\.gust).max() ?? days.first?.gust ?? 0)
        let wind = maxGust >= 14
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
        let firstPrecipitation = upcoming.first { $0.condition.localizedCaseInsensitiveContains("regn") || $0.condition.localizedCaseInsensitiveContains("snö") || $0.condition.localizedCaseInsensitiveContains("skur") }
        let precipitationDetail = firstPrecipitation.map { "\($0.condition) väntas kl. \($0.time)" } ?? (snow && rain ? "Snö och regn finns i timprognosen" : snow ? "Snöfall finns i timprognosen" : rain ? "Regn finns i timprognosen" : "Ingen nederbörd identifierad kommande timmar")
        return [
            WatchItem(id: "precipitation", title: precipitationTitle, subtitle: "Nederbörd · regn · snö · duggregn", symbol: snow ? "cloud.snow.fill" : "cloud.rain.fill", active: rain || snow, detail: precipitationDetail, level: rain || snow ? "BEVAKAR" : "LUGNT", tint: WatchPalette.cyan),
            WatchItem(id: "thunder", title: "ÅSKVAKTEN", subtitle: "Åska · blixtar · åskrisk", symbol: "cloud.bolt.rain.fill", active: thunder, detail: thunder ? "Åska förekommer i prognosen" : "Ingen åska identifierad i prognosen", level: thunder ? "RISK I PROGNOS" : "LUGNT", tint: Color.orange),
            WatchItem(id: "wind", title: "VINDVAKTEN", subtitle: "Vindstyrka · hårda vindbyar", symbol: "wind", active: wind, detail: String(format: "Högsta prognostiserade byvind %.1f m/s", maxGust), level: wind ? "FÖRHÖJD VIND" : "LUGNT", tint: Color(red: 0.54, green: 0.72, blue: 1.0)),
            WatchItem(id: "frost", title: "FROSTVAKTEN", subtitle: "Frostnatt · minusgrader · halkrisk", symbol: "thermometer.snowflake", active: frost, detail: wetNearFreeze.map { "Fukt/nederbörd och cirka \($0.temperature)° omkring kl. \($0.time) – risk för halka" } ?? frostHour.map { "Temperaturen väntas nå \($0.temperature)° omkring kl. \($0.time)" } ?? "Ingen tydlig frostrisk i timprognosen", level: wetNearFreeze != nil ? "HALKRISK" : frost ? "FROSTRISK" : "LUGNT", tint: Color.cyan),
            WatchItem(id: "official", title: "SMHI:S VÄDERVARNINGAR", subtitle: "Gul · orange · röd varning", symbol: "exclamationmark.triangle.fill", active: false, detail: "Officiella SMHI-varningar hämtas när prognosen uppdateras.", level: "SMHI ANSLUTET", tint: Color.yellow)
        ]
    }

    private var activeWatches: [WatchItem] { watches.filter(\.active) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("VÄDERVAKTER").font(.system(size: 27, weight: .black, design: .rounded)).foregroundStyle(.white)
                        Text("BEVAKNING FÖR \(weather.place.uppercased())").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(WatchPalette.muted)
                    }
                    Spacer()
                    Image(systemName: "shield.lefthalf.filled").font(.system(size: 29)).foregroundStyle(WatchPalette.cyan)
                }
                HStack(spacing: 8) {
                    Circle().fill(activeWatches.isEmpty ? Color.green : Color.orange).frame(width: 7, height: 7)
                    Text(activeWatches.isEmpty ? "Inga förhöjda risker i prognosen" : "\(activeWatches.count) aktiva bevakningar i prognosen")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                    Spacer()
                    Text("PROGNOSBASERAT").font(.system(size: 8, weight: .heavy)).tracking(0.7).foregroundStyle(WatchPalette.cyan)
                }.padding(12).background(WatchPalette.panel, in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(WatchPalette.line, lineWidth: 1))

                ForEach(watches) { watch in
                    watchCard(watch)
                }

                Text("Väderprognosen visar vilka bevakningar som är aktiva. SMHI-varningar är officiella och visas separat när de berör vald plats.")
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(WatchPalette.muted).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 3)
                Text("PROGNOS: OPEN-METEO  •  VARNINGAR: SMHI").font(.system(size: 8, weight: .bold)).tracking(0.7).foregroundStyle(WatchPalette.muted.opacity(0.7)).frame(maxWidth: .infinity).padding(.top, 3).padding(.bottom, 20)
            }
            .padding(.horizontal, 14).padding(.top, 22)
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
                Text(watch.subtitle).font(.system(size: 9, weight: .medium)).foregroundStyle(WatchPalette.muted).lineLimit(2)
                Text(watch.detail).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.88)).lineLimit(2)
                HStack(spacing: 5) { Circle().fill(watch.active ? watch.tint : WatchPalette.muted.opacity(0.55)).frame(width: 6, height: 6).shadow(color: watch.active ? watch.tint : .clear, radius: watch.active ? 6 : 0); Text(watch.level) }.font(.system(size: 8, weight: .heavy)).tracking(0.6).foregroundStyle(watch.active ? watch.tint : WatchPalette.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(10).background(WatchPalette.panel, in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(watch.active ? watch.tint.opacity(0.9) : WatchPalette.line, lineWidth: watch.active ? 1.6 : 1))
        .shadow(color: watch.active ? watch.tint.opacity(0.20) : .black.opacity(0.2), radius: watch.active ? 13 : 10, y: 5)
    }
}

struct ActiveWatchSummary: View {
    let weather: WeatherSnapshot
    let days: [DayForecast]
    let hours: [HourForecast]

    private var activeTitles: [(String, String)] {
        let text = hours.map { $0.condition.lowercased() }.joined(separator: " ")
        var result: [(String, String)] = []
        if text.contains("snö") { result.append(("SNÖVAKTEN", "cloud.snow.fill")) }
        else if text.contains("regn") || text.contains("skur") || text.contains("duggregn") { result.append(("REGNVAKTEN", "cloud.rain.fill")) }
        if text.contains("åska") { result.append(("ÅSKVAKTEN", "cloud.bolt.rain.fill")) }
        let gust = max(weather.windGust, hours.map(\.gust).max() ?? days.first?.gust ?? 0)
        if gust >= 14 { result.append(("VINDVAKTEN", "wind")) }
        return result
    }

    var body: some View {
        if !activeTitles.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("AKTIVA VÄDERVAKTER", systemImage: "shield.lefthalf.filled")
                        .font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                    Spacer()
                    Text("\(activeTitles.count) AKTIVA").font(.system(size: 8, weight: .heavy)).foregroundStyle(WatchPalette.cyan)
                }
                HStack(spacing: 7) {
                    ForEach(Array(activeTitles.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 5) {
                            Image(systemName: item.1).foregroundStyle(WatchPalette.cyan)
                            Text(item.0).foregroundStyle(.white)
                        }.font(.system(size: 8, weight: .heavy)).padding(.horizontal, 9).padding(.vertical, 8)
                            .background(.white.opacity(0.06), in: Capsule())
                            .overlay(Capsule().stroke(WatchPalette.line, lineWidth: 1))
                    }
                    Spacer(minLength: 0)
                }
            }.padding(11).background(WatchPalette.panel, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(WatchPalette.line, lineWidth: 1))
        }
    }
}
