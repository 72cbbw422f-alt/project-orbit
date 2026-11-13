import SwiftUI

private enum RTheme {
    static let bg = Color(red: 0.008, green: 0.025, blue: 0.055)
    static let cyan = Color(red: 0.04, green: 0.78, blue: 0.98)
    static let blue = Color(red: 0.02, green: 0.38, blue: 0.78)
    static let muted = Color(red: 0.69, green: 0.78, blue: 0.88)
    static let line = Color(red: 0.18, green: 0.52, blue: 0.72).opacity(0.48)
    static let panel = Color(red: 0.015, green: 0.075, blue: 0.13).opacity(0.91)
}

struct ContentView: View {
    @State private var selectedTab: WeatherTab = .weather
    @State private var showingSevenDayForecast = false
    @State private var showingWeatherDetails = false
    @State private var selectedForecastDay: DayForecast? = nil
    @State private var showingHourlyForecast = false
    @State private var showingPlaceSearch = false
    @StateObject private var weatherModel = WeatherViewModel()

    var body: some View {
        ZStack {
            // The root canvas and both background layers must occupy the complete
            // window. The scrollable content remains inside the safe area.
            RTheme.bg.ignoresSafeArea()
            RWeatherBackground(condition: weatherModel.snapshot?.condition ?? WeatherSnapshot.demo.condition)
                .ignoresSafeArea()
            Group {
                switch selectedTab {
                case .weather:
                    ReferenceWeatherHome(
                        weather: weatherModel.snapshot ?? .demo,
                        days: weatherModel.days,
                        hours: weatherModel.hours,
                        status: weatherModel.status,
                        isLive: weatherModel.snapshot != nil,
                        refresh: { weatherModel.refresh() },
                        showSevenDayForecast: { showingSevenDayForecast = true },
                        showWeatherDetails: { showingWeatherDetails = true },
                        showHourlyForecast: { showingHourlyForecast = true },
                        showPlaceSearch: { showingPlaceSearch = true }
                    )
                case .radar: RPlaceholder(title: "Radar", subtitle: "Nederbördsradar", icon: "dot.radiowaves.left.and.right")
                case .watch: VaktDashboard(weather: weatherModel.snapshot ?? .demo, days: weatherModel.days, hours: weatherModel.hours)
                case .places: SavedPlacesView(model: weatherModel, onAddPlace: { showingPlaceSearch = true }, onSelectPlace: { selectedTab = .weather })
                case .more: RPlaceholder(title: "Inställningar", subtitle: "Anpassa Regnvakt", icon: "gearshape.fill")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RTheme.bg.ignoresSafeArea())
        // Keep interactive content inside the iPhone safe area. Only the
        // background paints edge-to-edge; system status and home areas stay usable.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            RTabBar(selection: $selectedTab)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(LinearGradient(colors: [RTheme.bg.opacity(0), RTheme.bg.opacity(0.96)], startPoint: .top, endPoint: .bottom))
        }
        .sheet(isPresented: $showingSevenDayForecast) {
            SevenDayForecastDetail(days: weatherModel.days, place: weatherModel.snapshot?.place ?? "Din plats")
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(RTheme.bg)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showingWeatherDetails) {
            TodayWeatherDetails(weather: weatherModel.snapshot ?? .demo, days: weatherModel.days, hours: weatherModel.hours)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(RTheme.bg)
                .preferredColorScheme(.dark)
        }
        .sheet(item: $selectedForecastDay) { day in
            ForecastDayDetails(day: day, hours: weatherModel.hours, place: weatherModel.snapshot?.place ?? "Din plats")
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(RTheme.bg)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showingHourlyForecast) {
            HourlyForecastDetail(hours: weatherModel.hours, place: weatherModel.snapshot?.place ?? "Din plats")
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(RTheme.bg)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showingPlaceSearch) {
            PlaceSearchSheet(model: weatherModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(RTheme.bg)
                .preferredColorScheme(.dark)
        }
        .preferredColorScheme(.dark)
        .tint(RTheme.cyan)
    }
}

private struct ReferenceWeatherHome: View {
    let weather: WeatherSnapshot
    let days: [DayForecast]
    let hours: [HourForecast]
    let status: String
    let isLive: Bool
    let refresh: () -> Void
    let showSevenDayForecast: () -> Void
    let showWeatherDetails: () -> Void
    let showHourlyForecast: () -> Void
    let showPlaceSearch: () -> Void
    private let bars: [CGFloat] = [0.08,0.12,0.16,0.22,0.30,0.38,0.48,0.58,0.70,0.83,0.96,1.0,0.86,0.72,0.64,0.57,0.48,0.36,0.26,0.19,0.16,0.14,0.12,0.10]
    private var watchTitle: String {
        let condition = weather.condition.lowercased()
        if condition.contains("snö") { return "SNÖVAKTEN" }
        if condition.contains("regn") || condition.contains("duggregn") || condition.contains("underkylt regn") {
            return "REGNVAKTEN"
        }
        return "VÄDERVAKTEN"
    }

    private var watchSymbol: String {
        let condition = weather.condition.lowercased()
        if condition.contains("snö") { return "cloud.snow.fill" }
        if condition.contains("regn") || condition.contains("duggregn") { return "cloud.rain.fill" }
        return "cloud.fill"
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 11) {
                    brandHeader
                    locationHeader
                    currentConditions
                    mainCards(width: geo.size.width - 28)
                    precipitationCard
                    todayDetailsButton
                    moonMetric
                    daylightStrip
                    hourlyCard
                    sevenDayForecast
                    Text(isLive ? "VÄDERDATA: OPEN-METEO  •  PLATS: GPS" : "VÄNTAR PÅ GPS OCH LIVEVÄDER")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(1.1).foregroundStyle(.white.opacity(0.48))
                        .padding(.top, 1).padding(.bottom, 18)
                }
                .padding(.horizontal, 14)
                .padding(.top, 5)
            }
            .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .top)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var brandHeader: some View {
        HStack(spacing: 7) {
            Image(systemName: "umbrella.fill")
                .font(.system(size: 27, weight: .medium))
                .symbolRenderingMode(.palette)
                .foregroundStyle(RTheme.cyan, .white)
                .overlay(alignment: .top) {
                    HStack(spacing: 5) {
                        Circle().fill(RTheme.cyan).frame(width: 5,height: 5).offset(y:-5)
                        Circle().fill(RTheme.cyan).frame(width: 5,height: 5).offset(y:-9)
                        Circle().fill(RTheme.cyan).frame(width: 5,height: 5).offset(y:-5)
                    }
                }
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Regnvakt")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .italic().tracking(-0.7)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: true, vertical: false)
                    .lineLimit(1)
                Text("VÄDER • VARNINGAR • KOLL")
                    .font(.system(size: 6.5, weight: .heavy, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(RTheme.muted)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Spacer(minLength: 2)
            HStack(spacing: 5) {
                CircleIconButton(icon: "gearshape")
                CircleIconButton(icon: "bell.badge")
                CircleIconButton(icon: "ellipsis")
            }
        }
        .padding(.horizontal, 2)
        .padding(.top, 8)
        .padding(.bottom, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var locationHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Label(weather.place, systemImage: "location.fill")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(status)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(RTheme.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text("SENAST UPPDATERAD")
                    .font(.system(size: 7, weight: .bold)).tracking(0.7)
                    .foregroundStyle(RTheme.muted)
                HStack(spacing: 13) {
                    Button(action: showPlaceSearch) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(RTheme.cyan)
                    }.buttonStyle(.plain)
                    Button(action: refresh) {
                        Image(systemName: "location.circle")
                            .font(.system(size: 17, weight: .semibold)).foregroundStyle(RTheme.cyan)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var currentWeatherSymbol: String {
        let condition = weather.condition.lowercased()
        if condition.contains("snö") { return "cloud.snow.fill" }
        if condition.contains("dugg") || condition.contains("regn") { return "cloud.drizzle.fill" }
        if condition.contains("dimma") { return "cloud.fog.fill" }
        if condition.contains("åska") { return "cloud.bolt.rain.fill" }
        if condition.contains("moln") { return "cloud.fill" }
        return "cloud.sun.fill"
    }

    private var currentConditions: some View {
        HStack(spacing: 14) {
            Image(systemName: currentWeatherSymbol)
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color(red:0.82,green:0.91,blue:1), RTheme.cyan)
                .font(.system(size: 66))
                .shadow(color: RTheme.cyan.opacity(0.42), radius: 16)
                .frame(width: 84)
            Text("\(weather.temperature)°")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .tracking(-4).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 5) {
                Text(weather.condition)
                    .font(.system(size: 19, weight: .bold)).foregroundStyle(.white)
                    .lineLimit(2).minimumScaleFactor(0.78)
                Text("Känns som \(weather.feelsLike)°")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(RTheme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }

    private func mainCards(width: CGFloat) -> some View {
        let windWidth = max(128, width * 0.34)
        return HStack(alignment: .top, spacing: 9) {
            rainAlertCard
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            windCard
                .frame(width: windWidth, height: 190)
        }
        .frame(height: 190)
    }

    private var watchEvent: (title: String, detail: String, symbol: String, level: String, tint: Color) {
        guard !hours.isEmpty else {
            return ("Inväntar prognos", "Vädervakten analyserar kommande timmar när prognosen har hämtats.", "hourglass", "AVVAKTAR", RTheme.muted)
        }
        let precipitation = hours.first { $0.precipitationChance >= 40 || $0.precipitation >= 0.2 }
        let maxGust = max(weather.windGust, hours.map(\.gust).max() ?? 0)
        let coldest = hours.min { $0.temperature < $1.temperature }
        if let precipitation {
            let snow = precipitation.condition.localizedCaseInsensitiveContains("snö")
            let kind = snow ? "Snöfall" : "Regn"
            return ("\(kind) kan komma", "\(precipitation.condition) omkring kl. \(precipitation.time). Nederbördsrisk \(precipitation.precipitationChance)% enligt timprognosen.", snow ? "cloud.snow.fill" : "cloud.rain.fill", "HÅLL KOLL", Color.orange)
        }
        if maxGust >= 14 {
            return ("Kraftiga vindbyar", String(format: "Byvindar kan nå %.1f m/s under prognosperioden.", maxGust), "wind", "VINDRISK", Color.orange)
        }
        if let coldest, coldest.temperature <= 0 {
            return ("Risk för frost", "Temperaturen väntas nå \(coldest.temperature)° omkring kl. \(coldest.time).", "thermometer.snowflake", "FROSTRISK", Color.cyan)
        }
        return ("Inget särskilt väntas", "Ingen tydlig nederbörds- eller vindrisk identifierad de kommande timmarna.", "checkmark.shield.fill", "LUGNT JUST NU", Color.green)
    }

    private var rainAlertCard: some View {
        let event = watchEvent
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Label("VÄDERVAKTEN", systemImage: "shield.lefthalf.filled")
                    .font(.system(size: 9, weight: .heavy))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(LinearGradient(colors:[RTheme.blue,RTheme.cyan.opacity(0.72)],startPoint:.leading,endPoint:.trailing),in:Capsule())
                    .foregroundStyle(.white)
                Spacer(minLength: 1)
                HStack(spacing: 3) {
                    Circle().fill(isLive ? .green : .orange).frame(width:6,height:6)
                    Text(isLive ? "LIVE" : "DEMO").font(.system(size:7,weight:.heavy))
                }.foregroundStyle(isLive ? .green : .orange)
            }
            Text("Nästa väderhändelse")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.75)
            HStack(spacing: 7) {
                Image(systemName: event.symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(event.tint)
                Text(event.title)
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .tracking(-0.8).foregroundStyle(RTheme.cyan)
                    .lineLimit(2).minimumScaleFactor(0.68)
            }
            Text(event.detail)
                .font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.88))
                .lineLimit(3).fixedSize(horizontal:false,vertical:true)
            Spacer(minLength: 0)
            HStack {
                Label(event.level, systemImage: "eye.fill")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(event.tint)
                Spacer()
                Text("KOMMANDE TIMMAR")
                    .font(.system(size: 7, weight: .bold)).tracking(0.5)
                    .foregroundStyle(RTheme.muted)
            }
        }
        .padding(11)
        .background {
            RoundedRectangle(cornerRadius: 19)
                .fill(LinearGradient(colors:[Color(red:0.015,green:0.16,blue:0.27).opacity(0.98),Color(red:0.015,green:0.065,blue:0.13).opacity(0.96)],startPoint:.topLeading,endPoint:.bottomTrailing))
        }
        .overlay(alignment:.trailing) {
            Image(systemName: event.symbol)
                .font(.system(size:54))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(event.tint.opacity(0.10))
                .offset(x:2,y:-34)
                .allowsHitTesting(false)
        }
        .overlay(RoundedRectangle(cornerRadius:19).stroke(RTheme.line,lineWidth:1))
        .shadow(color:.black.opacity(0.28),radius:12,y:6)
    }

    private func miniRainStat(icon: String, title: String, value: String) -> some View {
        VStack(alignment:.leading,spacing:3) {
            Image(systemName:icon).font(.system(size:12,weight:.semibold)).foregroundStyle(RTheme.cyan)
            Text(title).font(.system(size:7,weight:.medium)).foregroundStyle(RTheme.muted).lineLimit(1)
            Text(value).font(.system(size:9,weight:.bold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }

    private var windCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Vind", systemImage: "wind")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)

            ZStack {
                Circle().fill(.white.opacity(0.025))
                Circle().stroke(.white.opacity(0.20), lineWidth: 1)
                ForEach(0..<24, id: \.self) { i in
                    Capsule()
                        .fill(.white.opacity(i.isMultiple(of: 2) ? 0.65 : 0.22))
                        .frame(width: 1, height: i.isMultiple(of: 2) ? 5 : 3)
                        .offset(y: -32)
                        .rotationEffect(.degrees(Double(i) * 15))
                }
                VStack {
                    Text("N")
                    Spacer()
                    Text("S")
                }
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.vertical, 4)
                HStack {
                    Text("V")
                    Spacer()
                    Text("Ö")
                }
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)

                Image(systemName: "arrow.up")
                    .font(.system(size: 23, weight: .black))
                    .foregroundStyle(RTheme.cyan)
                    .offset(y: -13)
                    .rotationEffect(.degrees(weather.windDirectionDegrees))
                    .shadow(color: RTheme.cyan.opacity(0.65), radius: 7)
                VStack(spacing: 1) {
                    Text(weather.windDirectionText)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("VINDRIKTNING")
                        .font(.system(size: 6, weight: .heavy))
                        .tracking(0.4)
                        .foregroundStyle(RTheme.muted)
                }
            }
            .frame(width: 76, height: 76)
            .frame(maxWidth: .infinity)

            windMeterRow(title: "Vind", value: weather.wind, maximum: 20, tint: RTheme.cyan)
            windMeterRow(title: "Byvind", value: weather.windGust, maximum: 25, tint: Color.orange)
        }
        .padding(8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RTheme.panel, in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(RTheme.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }

    private func windMeterRow(title: String, value: Double, maximum: Double, tint: Color) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(title)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(RTheme.muted)
                Spacer(minLength: 2)
                Text(String(format: "%.1f m/s", value))
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.10))
                    Capsule()
                        .fill(LinearGradient(colors: [tint.opacity(0.65), tint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * CGFloat(min(max(value / maximum, 0), 1)))
                }
            }
            .frame(height: 5)
        }
    }

    private var precipitationCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Nederbörd kommande timmar", systemImage: "cloud.drizzle.fill")
                .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
            if hours.isEmpty {
                Text("Nederbördsprognos saknas just nu.")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(RTheme.muted)
            } else {
                let forecast = Array(hours.prefix(8))
                let maximum = max(forecast.map(\.precipitation).max() ?? 0.1, 0.1)
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(forecast) { hour in
                        VStack(spacing: 5) {
                            Text(String(format: "%.1f", hour.precipitation))
                                .font(.system(size: 8, weight: .semibold)).foregroundStyle(RTheme.muted)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            GeometryReader { proxy in
                                VStack {
                                    Spacer(minLength: 0)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(LinearGradient(colors: [RTheme.cyan, RTheme.blue], startPoint: .top, endPoint: .bottom))
                                        .frame(height: max(3, proxy.size.height * CGFloat(hour.precipitation / maximum)))
                                }
                            }
                            .frame(height: 66)
                            Text(hour.time)
                                .font(.system(size: 8, weight: .medium)).foregroundStyle(RTheme.muted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Text("Prognostiserad nederbörd per timme, mm.")
                    .font(.system(size: 8)).foregroundStyle(RTheme.muted.opacity(0.85))
            }
        }.referencePanel()
    }

    private var sevenDayForecast: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("7-dagarsprognos", systemImage: "calendar")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                Spacer()
                Text("TRYCK PÅ EN DAG")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.7).foregroundStyle(RTheme.cyan)
            }
            if days.isEmpty {
                Text("Veckoprognosen visas när väderdata har hämtats.")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(RTheme.muted)
            } else {
                HStack(spacing: 5) {
                    ForEach(days.prefix(7)) { day in
                        Button { selectedForecastDay = day } label: {
                            VStack(spacing: 6) {
                                Text(day.day == "Idag" ? "Idag" : String(day.day.prefix(3)))
                                    .font(.system(size: 9, weight: .bold)).foregroundStyle(RTheme.muted)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                                Image(systemName: day.symbol).symbolRenderingMode(.palette)
                                    .foregroundStyle(Color(red:0.86,green:0.91,blue:1),RTheme.cyan)
                                    .font(.system(size: 20)).frame(height: 25)
                                Text("\(day.high)°")
                                    .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                Text("\(day.low)°")
                                    .font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(RTheme.muted)
                                Text("\(day.precipitationChance)%")
                                    .font(.system(size: 8, weight: .bold)).foregroundStyle(RTheme.cyan)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(RTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(RTheme.line.opacity(0.75), lineWidth: 1))
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }.referencePanel()
    }

    private func forecastDetail(icon: String, title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(RTheme.cyan)
            Text(title).font(.system(size: 7, weight: .medium)).foregroundStyle(RTheme.muted)
            Text(value).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
        }.frame(maxWidth: .infinity)
    }

    private var compactMetrics: some View {
        HStack(spacing: 7) {
            circularMetric(title:"Luftfuktighet",symbol:"humidity.fill",value:"\(weather.humidity)%",progress:Double(weather.humidity)/100,tint:RTheme.cyan)
            circularMetric(title:"Tryck",symbol:"gauge",value:weather.pressure > 0 ? String(format:"%.0f",weather.pressure) : "—",progress:0.62,tint:Color(red:0.42,green:0.72,blue:0.94),suffix:"hPa")
            moonMetric.frame(maxWidth: .infinity)
        }
        .frame(height: 142)
    }

    private func circularMetric(title:String,symbol:String,value:String,progress:Double,tint:Color,suffix:String?=nil)->some View {
        VStack(spacing:5) {
            HStack(spacing:3) {
                Image(systemName:symbol).foregroundStyle(tint)
                Text(title).foregroundStyle(.white)
            }.font(.system(size:8,weight:.semibold)).lineLimit(1).minimumScaleFactor(0.65)
            ZStack {
                Circle().trim(from:0.08,to:0.92).stroke(.white.opacity(0.14),style:StrokeStyle(lineWidth:5,lineCap:.round)).rotationEffect(.degrees(90))
                Circle().trim(from:0.08,to:0.08+0.84*min(max(progress,0),1)).stroke(tint,style:StrokeStyle(lineWidth:5,lineCap:.round)).rotationEffect(.degrees(90))
                VStack(spacing:0) {
                    Text(value).font(.system(size:15,weight:.bold,design:.rounded)).foregroundStyle(.white).minimumScaleFactor(0.7)
                    if let suffix { Text(suffix).font(.system(size:7,weight:.medium)).foregroundStyle(RTheme.muted) }
                }
            }.frame(width:55,height:55)
        }.frame(maxWidth:.infinity,maxHeight:.infinity).padding(6)
            .background(RTheme.panel,in:RoundedRectangle(cornerRadius:17))
            .overlay(RoundedRectangle(cornerRadius:17).stroke(RTheme.line.opacity(0.7),lineWidth:1))
    }

    private var moonPhaseInfo: (symbol: String, name: String, illumination: Int) {
        let reference = Date(timeIntervalSince1970: 947182440) // 2000-01-06 18:14 UTC
        let cycle = 29.530588853
        let days = Date().timeIntervalSince(reference) / 86400
        let phase = (days.truncatingRemainder(dividingBy: cycle) + cycle).truncatingRemainder(dividingBy: cycle) / cycle
        let illumination = Int(((1 - cos(phase * 2 * .pi)) / 2 * 100).rounded())
        let phases: [(Double, String, String)] = [
            (0.0625, "moonphase.new.moon", "Nymåne"),
            (0.1875, "moonphase.waxing.crescent", "Tilltagande skära"),
            (0.3125, "moonphase.first.quarter", "Första kvarteret"),
            (0.4375, "moonphase.waxing.gibbous", "Tilltagande måne"),
            (0.5625, "moonphase.full.moon", "Fullmåne"),
            (0.6875, "moonphase.waning.gibbous", "Avtagande måne"),
            (0.8125, "moonphase.last.quarter", "Sista kvarteret"),
            (0.9375, "moonphase.waning.crescent", "Avtagande skära"),
            (1.0, "moonphase.new.moon", "Nymåne")
        ]
        let phaseInfo = phases.first { phase < $0.0 } ?? phases[0]
        return (phaseInfo.1, phaseInfo.2, illumination)
    }

    private var moonMetric: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Label("SOLEN", systemImage: "sun.max.fill")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.orange)
                    .frame(height: 22, alignment: .leading)
                HStack(spacing: 8) {
                    Image(systemName: "sunrise.fill").font(.system(size: 22)).foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SOLUPPGÅNG").font(.system(size: 8, weight: .heavy)).foregroundStyle(RTheme.muted)
                        Text(weather.sunriseTime).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: "sunset.fill").font(.system(size: 22)).foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SOLNEDGÅNG").font(.system(size: 8, weight: .heavy)).foregroundStyle(RTheme.muted)
                        Text(weather.sunsetTime).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(RTheme.line).frame(width: 1, height: 124).padding(.top, 2)
            VStack(spacing: 5) {
                Label("MÅNEN", systemImage: "moon.fill")
                    .font(.system(size: 13, weight: .heavy)).foregroundStyle(RTheme.cyan)
                    .frame(height: 22, alignment: .center)
                Image(systemName: moonPhaseInfo.symbol)
                    .font(.system(size: 58)).symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(red: 0.86, green: 0.90, blue: 1))
                    .shadow(color: .white.opacity(0.28), radius: 7)
                Text("\(moonPhaseInfo.illumination)% belyst")
                    .font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text(moonPhaseInfo.name)
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(RTheme.muted)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 178)
        .background(RTheme.panel, in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(RTheme.line.opacity(0.8), lineWidth: 1))
    }

    private var daylightStrip: some View {
        HStack(spacing:8) {
            Image(systemName:"sun.max.fill").font(.system(size:17)).foregroundStyle(.yellow)
            VStack(alignment:.leading,spacing:2) {
                Text("Dagslängd").font(.system(size:11,weight:.semibold)).foregroundStyle(RTheme.muted)
                Text(weather.daylightMinutes > 0 ? String(format:"%d h %02d min",weather.daylightMinutes/60,weather.daylightMinutes%60) : "Beräknas")
                    .font(.system(size:16,weight:.bold,design:.rounded)).foregroundStyle(.white)
            }
            Spacer(minLength:3)
            if weather.daylightChangeMinutes != 0 {
                Image(systemName:weather.daylightChangeMinutes > 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size:12,weight:.heavy))
                    .foregroundStyle(weather.daylightChangeMinutes > 0 ? .green : .red)
                Text("\(abs(weather.daylightChangeMinutes)) min \(weather.daylightChangeMinutes > 0 ? "längre" : "kortare") än igår")
                    .font(.system(size:14,weight:.bold)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
            } else {
                Text("Jämfört med igår")
                    .font(.system(size:8,weight:.medium)).foregroundStyle(RTheme.muted)
            }
        }.padding(.horizontal,12).padding(.vertical,9)
            .background(RTheme.panel,in:Capsule())
            .overlay(Capsule().stroke(RTheme.line.opacity(0.7),lineWidth:1))
    }

    private var todayDetailsButton: some View {
        Button(action: showWeatherDetails) {
            HStack(spacing:10) {
                Image(systemName:"cloud.sun.rain.fill")
                    .font(.system(size:17,weight:.semibold)).foregroundStyle(RTheme.cyan)
                VStack(alignment:.leading,spacing:2) {
                    Text("Dagens väderfakta")
                        .font(.system(size:12,weight:.bold)).foregroundStyle(.white)
                                    }
                Spacer()
                Image(systemName:"chevron.right").font(.system(size:11,weight:.bold)).foregroundStyle(RTheme.cyan)
            }
            .padding(.horizontal,13).padding(.vertical,11)
            .background(RTheme.panel,in:RoundedRectangle(cornerRadius:15))
            .overlay(RoundedRectangle(cornerRadius:15).stroke(RTheme.line.opacity(0.8),lineWidth:1))
        }.buttonStyle(.plain)
    }

    private var hourlyCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("Kommande timmar", systemImage: "clock")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                Spacer()
                Button(action: showHourlyForecast) {
                    HStack(spacing: 4) {
                        Text("VISA MER")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(RTheme.cyan)
                }.buttonStyle(.plain)
            }
            if hours.isEmpty {
                Text("Timprognosen visas när väderdata har hämtats.")
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(RTheme.muted)
            } else {
                HStack(spacing: 0) {
                    ForEach(hours.prefix(8)) { hour in
                        VStack(spacing: 7) {
                            Text(hour.time).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                            Image(systemName: hour.symbol).symbolRenderingMode(.palette)
                                .foregroundStyle(Color(red: 0.82, green: 0.90, blue: 1), RTheme.cyan)
                                .font(.system(size: 22)).frame(height: 27)
                            Text("\(hour.precipitationChance)%").font(.system(size: 9, weight: .bold)).foregroundStyle(RTheme.cyan)
                            Text("\(hour.temperature)°").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        }.frame(maxWidth: .infinity)
                    }
                }
            }
        }.referencePanel()
    }
}

private struct TodayWeatherDetails: View {
    let weather: WeatherSnapshot
    let days: [DayForecast]
    let hours: [HourForecast]

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(red:0.10,green:0.10,blue:0.18), RTheme.bg, RTheme.bg], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 15) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(weather.place).font(.system(size:22,weight:.bold,design:.rounded)).foregroundStyle(.white)
                            Text("Dagens väderförhållanden").font(.system(size:12,weight:.medium)).foregroundStyle(RTheme.muted)
                        }.frame(maxWidth:.infinity,alignment:.leading)

                        HStack(spacing:14) {
                            Image(systemName: detailWeatherSymbol)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color(red:0.88,green:0.91,blue:1), RTheme.cyan)
                                .font(.system(size:58))
                            VStack(alignment:.leading,spacing:3) {
                                Text("\(weather.temperature)°").font(.system(size:48,weight:.bold,design:.rounded)).foregroundStyle(.white)
                                Text(weather.condition.uppercased()).font(.system(size:12,weight:.heavy)).tracking(1).foregroundStyle(RTheme.cyan)
                                Text("Känns som \(weather.feelsLike)°").font(.system(size:14,weight:.medium)).foregroundStyle(RTheme.muted)
                            }
                            Spacer(minLength:0)
                        }
                        .padding(17)
                        .background(LinearGradient(colors:[Color(red:0.13,green:0.19,blue:0.29),RTheme.panel],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:22))
                        .overlay(RoundedRectangle(cornerRadius:22).stroke(RTheme.line,lineWidth:1))

                        if !days.isEmpty {
                            Text("KOMMANDE 7 DAGAR").font(.system(size:9,weight:.heavy)).tracking(1.2).foregroundStyle(RTheme.cyan)
                            ScrollView(.horizontal,showsIndicators:false) {
                                HStack(spacing:8) {
                                    ForEach(days.prefix(7)) { day in
                                        VStack(spacing:7) {
                                            Text(day.day).font(.system(size:10,weight:.bold)).foregroundStyle(RTheme.muted)
                                            Image(systemName:day.symbol).symbolRenderingMode(.palette)
                                                .foregroundStyle(Color(red:0.88,green:0.91,blue:1),RTheme.cyan).font(.system(size:22))
                                            Text("\(day.high)°").font(.system(size:15,weight:.bold,design:.rounded)).foregroundStyle(.white)
                                            Text("\(day.low)°").font(.system(size:11,weight:.medium)).foregroundStyle(RTheme.muted)
                                            if day.precipitationChance > 0 {
                                                Text("\(day.precipitationChance)%").font(.system(size:9,weight:.bold)).foregroundStyle(RTheme.cyan)
                                            } else {
                                                Text("—").font(.system(size:9)).foregroundStyle(RTheme.muted)
                                            }
                                        }
                                        .frame(width:66)
                                        .padding(.vertical,11)
                                        .background(RTheme.panel,in:RoundedRectangle(cornerRadius:15))
                                        .overlay(RoundedRectangle(cornerRadius:15).stroke(RTheme.line.opacity(0.65),lineWidth:1))
                                    }
                                }
                            }
                        }

                        if !hours.isEmpty {
                            Text("TEMPERATUR UNDER DAGEN").font(.system(size:9,weight:.heavy)).tracking(1.1).foregroundStyle(RTheme.cyan)
                            temperatureChart
                        }

                        Text("VÄDER JUST NU").font(.system(size:9,weight:.heavy)).tracking(1.1).foregroundStyle(RTheme.cyan)
                        LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:9) {
                            detailMetric("Luftfuktighet","\(weather.humidity)%","humidity.fill")
                            detailMetric("Lufttryck",weather.pressure > 0 ? String(format:"%.0f hPa",weather.pressure) : "—","gauge")
                            detailMetric("UV-index","\(weather.uvIndex)","sun.max.fill")
                            detailMetric("Molnighet","\(weather.cloudCover)%","cloud.fill")
                            detailMetric("Daggpunkt",String(format:"%.1f°",weather.dewPoint),"thermometer.low")
                            detailMetric("Sikt",String(format:"%.1f km",weather.visibilityKm),"eye")
                        }

                        HStack(spacing:9) {
                            summaryTile(title:"NEDERBÖRD",value:String(format:"%.1f mm",weather.precipitationToday),subtitle:"Just nu",symbol:"drop.fill",tint:RTheme.cyan)
                            summaryTile(title:"VIND",value:String(format:"%.1f m/s",weather.wind),subtitle:"Byvind \(String(format:"%.1f",weather.windGust)) m/s",symbol:"wind",tint:Color(red:0.78,green:0.86,blue:1))
                        }
                        Text("VINDRIKTNING OCH STYRKA").font(.system(size:9,weight:.heavy)).tracking(1.1).foregroundStyle(RTheme.cyan)
                        HStack(spacing:10) {
                            Image(systemName:"location.north.circle.fill")
                                .font(.system(size:32)).rotationEffect(.degrees(weather.windDirectionDegrees))
                                .foregroundStyle(RTheme.cyan)
                            VStack(alignment:.leading,spacing:3) {
                                Text(weather.windDirectionText).font(.system(size:19,weight:.bold)).foregroundStyle(.white)
                                Text(String(format:"%.0f° • Medelvind %.1f m/s • Byvind %.1f m/s",weather.windDirectionDegrees,weather.wind,weather.windGust))
                                    .font(.system(size:10,weight:.medium)).foregroundStyle(RTheme.muted)
                            }
                            Spacer()
                        }.referencePanel()

                        Text("SOL OCH DAGSLJUS").font(.system(size:9,weight:.heavy)).tracking(1.1).foregroundStyle(RTheme.cyan)
                        VStack(spacing:10) {
                            HStack { Label("Soluppgång",systemImage:"sunrise.fill").foregroundStyle(.orange); Spacer(); Text(weather.sunriseTime).foregroundStyle(.white) }
                            HStack { Label("Solnedgång",systemImage:"sunset.fill").foregroundStyle(.orange); Spacer(); Text(weather.sunsetTime).foregroundStyle(.white) }
                            Divider().overlay(RTheme.line)
                            HStack { Label("Dagslängd",systemImage:"sun.max.fill").foregroundStyle(.yellow); Spacer(); Text(String(format:"%d h %02d min",weather.daylightMinutes/60,weather.daylightMinutes%60)).foregroundStyle(.white) }
                            HStack { Text("Förändring mot igår").foregroundStyle(RTheme.muted); Spacer(); Text("\(weather.daylightChangeMinutes > 0 ? "+" : "")\(weather.daylightChangeMinutes) min").foregroundStyle(weather.daylightChangeMinutes >= 0 ? .green : .red) }
                        }.font(.system(size:12,weight:.semibold)).referencePanel()

                        Text("VÄDER TIMME FÖR TIMME").font(.system(size:9,weight:.heavy)).tracking(1.1).foregroundStyle(RTheme.cyan)
                        VStack(spacing:0) {
                            ForEach(hours.prefix(24)) { hour in
                                HStack(spacing:9) {
                                    Text(hour.time).font(.system(size:11,weight:.bold)).foregroundStyle(.white).frame(width:38,alignment:.leading)
                                    Image(systemName:hour.symbol).font(.system(size:18)).foregroundStyle(RTheme.cyan).frame(width:25)
                                    Text("\(hour.temperature)°").font(.system(size:13,weight:.bold,design:.rounded)).foregroundStyle(.white).frame(width:34)
                                    VStack(alignment:.leading,spacing:2) {
                                        Text("Nederbördsrisk \(hour.precipitationChance)%").font(.system(size:9,weight:.semibold)).foregroundStyle(RTheme.cyan)
                                        Text(String(format:"Vind %.1f • By %.1f m/s",hour.wind,hour.gust)).font(.system(size:8)).foregroundStyle(RTheme.muted)
                                    }
                                    Spacer()
                                    Text(String(format:"%.1f mm",hour.precipitation)).font(.system(size:9,weight:.medium)).foregroundStyle(.white)
                                }.padding(.vertical,8)
                                if hour.id != hours.prefix(24).last?.id { Divider().overlay(RTheme.line) }
                            }
                        }.padding(.horizontal,12).referencePanel()
                    }.padding(16)
                }
            }
            .navigationTitle("Dagens väder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark,for:.navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Stäng") { dismiss() }.foregroundStyle(RTheme.cyan)
                }
            }
        }.preferredColorScheme(.dark)
    }

    private var detailWeatherSymbol: String {
        let condition = weather.condition.lowercased()
        if condition.contains("snö") { return "cloud.snow.fill" }
        if condition.contains("dugg") || condition.contains("regn") { return "cloud.drizzle.fill" }
        if condition.contains("dimma") { return "cloud.fog.fill" }
        if condition.contains("åska") { return "cloud.bolt.rain.fill" }
        if condition.contains("moln") { return "cloud.fill" }
        return "cloud.sun.fill"
    }

    private var temperatureChart: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {
                Label("Temperatur",systemImage:"thermometer").font(.system(size:11,weight:.semibold)).foregroundStyle(RTheme.muted)
                Spacer()
                Text("Nästa 24 timmar • °C").font(.system(size:9,weight:.medium)).foregroundStyle(RTheme.muted)
            }
            let values = Array(hours.prefix(24)).map { Double($0.temperature) }
            let low = floor((values.min() ?? 0) / 2) * 2
            let high = max(ceil((values.max() ?? 2) / 2) * 2, low + 2)
            HStack(spacing:7) {
                VStack {
                    ForEach((0...2).reversed(),id:\.self) { step in
                        Text(String(format:"%.0f°",low + (high-low)*Double(step)/2))
                            .font(.system(size:8,weight:.medium,design:.rounded)).foregroundStyle(RTheme.muted)
                        if step > 0 { Spacer(minLength:0) }
                    }
                }.frame(width:27)
                GeometryReader { proxy in
                    ZStack {
                        ForEach(0...2,id:\.self) { step in
                            let y = proxy.size.height * CGFloat(step) / 2
                            Path { path in
                                path.move(to:CGPoint(x:0,y:y))
                                path.addLine(to:CGPoint(x:proxy.size.width,y:y))
                            }.stroke(RTheme.line.opacity(0.7),style:StrokeStyle(lineWidth:0.8,dash:[3,3]))
                        }
                        Path { path in
                            for (index,value) in values.enumerated() {
                                let x = proxy.size.width * CGFloat(index) / CGFloat(max(values.count-1,1))
                                let y = proxy.size.height - CGFloat((value-low)/(high-low)) * (proxy.size.height-10) - 5
                                if index == 0 { path.move(to:CGPoint(x:x,y:y)) } else { path.addLine(to:CGPoint(x:x,y:y)) }
                            }
                        }.stroke(RTheme.cyan,style:StrokeStyle(lineWidth:3,lineCap:.round,lineJoin:.round))
                        ForEach(Array(values.enumerated()),id:\.offset) { index,value in
                            let x = proxy.size.width * CGFloat(index) / CGFloat(max(values.count-1,1))
                            let y = proxy.size.height - CGFloat((value-low)/(high-low)) * (proxy.size.height-10) - 5
                            Circle().fill(.white).frame(width:5,height:5).position(x:x,y:y)
                        }
                    }
                }.frame(height:112)
            }
            HStack {
                Text(hours.first?.time ?? "Nu")
                Spacer()
                Text("+6 h")
                Spacer()
                Text("+12 h")
                Spacer()
                Text("+18 h")
                Spacer()
                Text("+24 h")
            }.font(.system(size:8,weight:.medium)).foregroundStyle(RTheme.muted).padding(.leading,34)
        }.referencePanel()
    }

    private func summaryTile(title:String,value:String,subtitle:String,symbol:String,tint:Color) -> some View {
        VStack(alignment:.leading,spacing:8) {
            Label(title,systemImage:symbol).font(.system(size:9,weight:.heavy)).tracking(0.7).foregroundStyle(RTheme.muted)
            Text(value).font(.system(size:24,weight:.bold,design:.rounded)).foregroundStyle(tint).minimumScaleFactor(0.75)
            Text(subtitle).font(.system(size:10,weight:.medium)).foregroundStyle(RTheme.muted)
            Spacer(minLength:0)
        }.frame(maxWidth:.infinity,minHeight:112,alignment:.leading).padding(13)
            .background(RTheme.panel,in:RoundedRectangle(cornerRadius:17))
            .overlay(RoundedRectangle(cornerRadius:17).stroke(RTheme.line.opacity(0.7),lineWidth:1))
    }

    private func detailMetric(_ title:String,_ value:String,_ symbol:String) -> some View {
        HStack(spacing:10) {
            Image(systemName:symbol).font(.system(size:17,weight:.semibold)).foregroundStyle(RTheme.cyan).frame(width:24)
            VStack(alignment:.leading,spacing:2) {
                Text(value).font(.system(size:17,weight:.bold,design:.rounded)).foregroundStyle(.white)
                Text(title).font(.system(size:10,weight:.medium)).foregroundStyle(RTheme.muted)
            }
            Spacer(minLength:0)
        }.frame(maxWidth:.infinity,minHeight:58,alignment:.leading).padding(.horizontal,11).padding(.vertical,7)
            .background(RTheme.panel,in:RoundedRectangle(cornerRadius:13))
            .overlay(RoundedRectangle(cornerRadius:13).stroke(RTheme.line.opacity(0.7),lineWidth:1))
    }
}
 
private struct ForecastDayDetails: View {
    let day: DayForecast
    let hours: [HourForecast]
    let place: String
    @Environment(\.dismiss) private var dismiss

    private var dayHours: [HourForecast] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier:"en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let key = formatter.string(from:day.date)
        return hours.filter { $0.id.hasPrefix(key) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors:[Color(red:0.10,green:0.10,blue:0.18),RTheme.bg,RTheme.bg],startPoint:.topLeading,endPoint:.bottomTrailing)
                    .ignoresSafeArea()
                ScrollView(showsIndicators:false) {
                    VStack(alignment:.leading,spacing:15) {
                        VStack(alignment:.leading,spacing:4) {
                            Text(place).font(.system(size:13,weight:.semibold)).foregroundStyle(RTheme.cyan)
                            Text(day.day).font(.system(size:25,weight:.bold,design:.rounded)).foregroundStyle(.white)
                            Text(day.condition).font(.system(size:13,weight:.medium)).foregroundStyle(RTheme.muted)
                        }
                        HStack(spacing:14) {
                            Image(systemName:day.symbol).symbolRenderingMode(.palette)
                                .foregroundStyle(Color(red:0.88,green:0.91,blue:1),RTheme.cyan).font(.system(size:58))
                            VStack(alignment:.leading,spacing:3) {
                                Text("\(day.high)°").font(.system(size:48,weight:.bold,design:.rounded)).foregroundStyle(.white)
                                Text("HÖGSTA TEMPERATUR").font(.system(size:10,weight:.heavy)).tracking(1).foregroundStyle(RTheme.cyan)
                                Text("Lägsta \(day.low)°").font(.system(size:14,weight:.medium)).foregroundStyle(RTheme.muted)
                            }
                            Spacer()
                        }.padding(17)
                            .background(LinearGradient(colors:[Color(red:0.13,green:0.19,blue:0.29),RTheme.panel],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:22))
                            .overlay(RoundedRectangle(cornerRadius:22).stroke(RTheme.line,lineWidth:1))

                        Text("DAGENS PROGNOS").font(.system(size:9,weight:.heavy)).tracking(1.1).foregroundStyle(RTheme.cyan)
                        LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:9) {
                            dayMetric("Nederbördsrisk","\(day.precipitationChance)%","drop.fill")
                            dayMetric("Nederbörd",String(format:"%.1f mm",day.precipitation),"cloud.rain.fill")
                            dayMetric("Medelvind",String(format:"%.1f m/s",day.wind),"wind")
                            dayMetric("Byvind",String(format:"%.1f m/s",day.gust),"wind")
                            dayMetric("UV-index",String(format:"%.0f",day.uv),"sun.max.fill")
                        }

                        if !dayHours.isEmpty {
                            Text("TIMME FÖR TIMME").font(.system(size:9,weight:.heavy)).tracking(1.1).foregroundStyle(RTheme.cyan)
                            VStack(spacing:0) {
                                ForEach(dayHours) { hour in
                                    HStack(spacing:9) {
                                        Text(hour.time).font(.system(size:11,weight:.bold)).foregroundStyle(.white).frame(width:38,alignment:.leading)
                                        Image(systemName:hour.symbol).font(.system(size:19)).foregroundStyle(RTheme.cyan).frame(width:26)
                                        Text("\(hour.temperature)°").font(.system(size:14,weight:.bold,design:.rounded)).foregroundStyle(.white).frame(width:36)
                                        VStack(alignment:.leading,spacing:2) {
                                            Text("Nederbördsrisk \(hour.precipitationChance)%").font(.system(size:9,weight:.semibold)).foregroundStyle(RTheme.cyan)
                                            Text(String(format:"Vind %.1f • By %.1f m/s",hour.wind,hour.gust)).font(.system(size:8)).foregroundStyle(RTheme.muted)
                                        }
                                        Spacer(minLength:2)
                                        Text(String(format:"%.1f mm",hour.precipitation)).font(.system(size:9,weight:.medium)).foregroundStyle(.white)
                                    }.padding(.vertical,8)
                                    if hour.id != dayHours.last?.id { Divider().overlay(RTheme.line) }
                                }
                            }.padding(.horizontal,12).referencePanel()
                        } else {
                            Text("Timprognosen för den här dagen är inte tillgänglig ännu. Dygnsprognosen ovan bygger på väderdata för hela dagen.")
                                .font(.system(size:11,weight:.medium)).foregroundStyle(RTheme.muted)
                                .referencePanel()
                        }
                    }.padding(16)
                }
            }
            .navigationTitle("Dagens prognos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark,for:.navigationBar)
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) {
                    Button("Stäng") { dismiss() }.foregroundStyle(RTheme.cyan)
                }
            }
        }.preferredColorScheme(.dark)
    }

    private func dayMetric(_ title:String,_ value:String,_ symbol:String) -> some View {
        HStack(spacing:9) {
            Image(systemName:symbol).font(.system(size:17,weight:.semibold)).foregroundStyle(RTheme.cyan).frame(width:23)
            VStack(alignment:.leading,spacing:2) {
                Text(value).font(.system(size:17,weight:.bold,design:.rounded)).foregroundStyle(.white)
                Text(title).font(.system(size:10,weight:.medium)).foregroundStyle(RTheme.muted)
            }
            Spacer(minLength:0)
        }.frame(maxWidth:.infinity,minHeight:58,alignment:.leading).padding(.horizontal,11).padding(.vertical,7)
            .background(RTheme.panel,in:RoundedRectangle(cornerRadius:13))
            .overlay(RoundedRectangle(cornerRadius:13).stroke(RTheme.line.opacity(0.7),lineWidth:1))
    }
}

private struct HourlyForecastDetail: View {
    let hours: [HourForecast]
    let place: String
    @State private var selectedMetric = "Temperatur"

    private let metrics = ["Temperatur", "Nederbörd", "Vind"]

    var body: some View {
        NavigationStack {
            ZStack {
                RTheme.bg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(place).font(.system(size: 13, weight: .semibold)).foregroundStyle(RTheme.cyan)
                            Text("Timprognos").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            Text("48 timmar framåt • Prognos per timme")
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(RTheme.muted)
                        }
                        if hours.isEmpty {
                            Text("Ingen timprognos tillgänglig just nu.")
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(RTheme.muted)
                                .referencePanel()
                        } else {
                            Picker("Visa", selection: $selectedMetric) {
                                ForEach(metrics, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .tint(RTheme.cyan)

                            metricChart

                            Text("PROGNOS TIMME FÖR TIMME")
                                .font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(RTheme.cyan)

                            VStack(spacing: 0) {
                                ForEach(Array(hours.prefix(48))) { hour in
                                    HStack(spacing: 9) {
                                        Text(hour.time).font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.white).frame(width: 38, alignment: .leading)
                                        Image(systemName: hour.symbol).font(.system(size: 19))
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(Color(red: 0.82, green: 0.90, blue: 1), RTheme.cyan)
                                            .frame(width: 27)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("\(hour.temperature)°  •  Regnrisk \(hour.precipitationChance)%")
                                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                                            Text(String(format: "%.1f mm nederbörd  •  Vind %.1f / by %.1f m/s", hour.precipitation, hour.wind, hour.gust))
                                                .font(.system(size: 8, weight: .medium)).foregroundStyle(RTheme.muted)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.vertical, 9).padding(.horizontal, 11)
                                    if hour.id != hours.prefix(48).last?.id { Divider().overlay(RTheme.line) }
                                }
                            }.referencePanel()
                        }
                    }.padding(16)
                }
            }
            .navigationTitle("Kommande timmar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }.preferredColorScheme(.dark)
    }

    private var metricChart: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(selectedMetric.uppercased())
                .font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(RTheme.muted)
            GeometryReader { proxy in
                let values = Array(hours.prefix(24)).map { hour -> Double in
                    switch selectedMetric {
                    case "Nederbörd": return hour.precipitation
                    case "Vind": return hour.wind
                    default: return Double(hour.temperature)
                    }
                }
                let minimum = min(values.min() ?? 0, 0)
                let maximum = max(values.max() ?? 1, minimum + 1)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        VStack {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(RTheme.cyan.gradient)
                                .frame(height: max(3, proxy.size.height * CGFloat((value - minimum) / (maximum - minimum))))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: 94)
            HStack {
                Text("Nu")
                Spacer()
                Text("+6 h")
                Spacer()
                Text("+12 h")
                Spacer()
                Text("+18 h")
                Spacer()
                Text("+24 h")
            }.font(.system(size: 8, weight: .medium)).foregroundStyle(RTheme.muted)
        }.referencePanel()
    }
}

private struct PlaceSearchSheet: View {
    @ObservedObject var model: WeatherViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ZStack {
                RTheme.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 14) {
                    Text("Välj var du vill se vädret")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Använd din position eller sök efter en ort eller stad.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(RTheme.muted)
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(RTheme.cyan)
                        TextField("Sök ort eller stad", text: $query)
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .submitLabel(.search)
                            .onSubmit { model.searchPlaces(query) }
                        Button("Sök") { model.searchPlaces(query) }
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(RTheme.cyan)
                            .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(12)
                    .background(RTheme.panel, in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(RTheme.line, lineWidth: 1))
                    Button {
                        model.refresh()
                        dismiss()
                    } label: {
                        Label("Använd min nuvarande position", systemImage: "location.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(RTheme.cyan)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                    if model.isSearchingPlaces {
                        ProgressView().tint(RTheme.cyan)
                    }
                    if !model.placeSearchStatus.isEmpty {
                        Text(model.placeSearchStatus)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(RTheme.muted)
                    }
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(model.placeSearchResults) { place in
                                Button {
                                    model.selectPlace(place)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Image(systemName: "mappin.and.ellipse").foregroundStyle(RTheme.cyan)
                                        Text(place.name).foregroundStyle(.white).font(.system(size: 14, weight: .semibold))
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(RTheme.muted)
                                    }
                                    .padding(12)
                                    .background(RTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(18)
            }
            .navigationTitle("Plats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Stäng") { dismiss() }.foregroundStyle(RTheme.cyan)
                }
            }
        }
    }
}

private struct SevenDayForecastDetail: View {
    let days: [DayForecast]
    let place: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                RTheme.bg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(place)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(RTheme.cyan)
                            Text("7 dagar framåt")
                                .font(.system(size: 23, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("Svep i sidled för att se hela veckans prognos.")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(RTheme.muted)
                        }

                        if days.isEmpty {
                            Text("Ingen prognos tillgänglig ännu.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(RTheme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .referencePanel()
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(days) { day in
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack(spacing: 12) {
                                            Image(systemName: day.symbol)
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(.white, RTheme.cyan)
                                                .font(.system(size: 27))
                                                .frame(width: 38, height: 38)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(day.day)
                                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                                    .foregroundStyle(.white)
                                                Text(day.condition)
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundStyle(RTheme.muted)
                                            }
                                            Spacer()
                                            HStack(alignment: .firstTextBaseline, spacing: 7) {
                                                Text("\(day.high)°")
                                                    .font(.system(size: 21, weight: .bold, design: .rounded))
                                                    .foregroundStyle(.white)
                                                Text("\(day.low)°")
                                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                                    .foregroundStyle(RTheme.muted)
                                            }
                                        }
                                        Rectangle().fill(.white.opacity(0.09)).frame(height: 1)
                                        HStack(spacing: 5) {
                                            forecastMetricColumn(icon: "drop.fill", label: "Regnrisk", value: "\(day.precipitationChance)%")
                                            forecastMetricColumn(icon: "cloud.rain.fill", label: "Nederbörd", value: String(format: "%.1f mm", day.precipitation))
                                            forecastMetricColumn(icon: "wind", label: "Vind", value: String(format: "%.1f m/s", day.wind))
                                            forecastMetricColumn(icon: "sun.max.fill", label: "UV", value: String(format: "%.0f", day.uv))
                                        }
                                    }
                                    .padding(12)
                                    .background(RTheme.panel, in: RoundedRectangle(cornerRadius: 17))
                                    .overlay(RoundedRectangle(cornerRadius: 17).stroke(RTheme.line.opacity(0.75), lineWidth: 1))
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 18)
                }
            }
            .navigationTitle("7-dagarsprognos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Stäng") { dismiss() }.foregroundStyle(RTheme.cyan)
                }
            }
        }
    }

    private func forecastMetricColumn(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(RTheme.cyan)
                Text(label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(RTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func weatherTemp(_ value:Int)->Int { value }

private struct RWeatherBackground: View {
    let condition:String
    private var isStorm:Bool { condition.localizedCaseInsensitiveContains("åska") }
    private var isSnow:Bool { condition.localizedCaseInsensitiveContains("snö") }
    private var isRain:Bool { condition.localizedCaseInsensitiveContains("regn") || condition.localizedCaseInsensitiveContains("skur") }
    private var isSun:Bool { condition.localizedCaseInsensitiveContains("sol") || condition.localizedCaseInsensitiveContains("klart") }
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment:.top) {
                LinearGradient(colors: isStorm ? [Color(red:0.10,green:0.12,blue:0.22),RTheme.bg] : isSnow ? [Color(red:0.13,green:0.25,blue:0.36),RTheme.bg] : isRain ? [Color(red:0.015,green:0.13,blue:0.23),Color(red:0.01,green:0.055,blue:0.11),RTheme.bg] : isSun ? [Color(red:0.23,green:0.20,blue:0.15),RTheme.bg] : [Color(red:0.08,green:0.18,blue:0.27),RTheme.bg],startPoint:.topLeading,endPoint:.bottomTrailing)
                Circle().fill((isSun ? Color.orange : RTheme.cyan).opacity(0.16)).frame(width:260,height:260).blur(radius:80).offset(x:geo.size.width*0.35,y:-90)
                Image(systemName:isStorm ? "cloud.bolt.rain.fill" : isSnow ? "cloud.snow.fill" : isRain ? "cloud.heavyrain.fill" : isSun ? "sun.max.fill" : "cloud.fill")
                    .symbolRenderingMode(.hierarchical).font(.system(size:230,weight:.ultraLight))
                    .foregroundStyle(.white.opacity(0.075)).offset(x:geo.size.width*0.15,y:65)
                if isRain || isStorm {
                    RainStreaks().opacity(0.42)
                }
                LinearGradient(colors:[.clear,RTheme.bg.opacity(0.35),RTheme.bg],startPoint:.top,endPoint:.bottom)
            }.frame(width:geo.size.width,height:geo.size.height).clipped()
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}

private struct RainStreaks: View {
    var body: some View {
        Canvas { context,size in
            for i in 0..<85 {
                let x = CGFloat((i*47)%Int(max(size.width,1)))
                let y = CGFloat((i*83)%900)
                var path = Path()
                path.move(to:CGPoint(x:x,y:y))
                path.addLine(to:CGPoint(x:x-3,y:y+12+CGFloat(i%4)*3))
                context.stroke(path,with:.color(.white.opacity(i%3 == 0 ? 0.30:0.13)),lineWidth:1)
            }
        }
    }
}

private struct CircleIconButton:View {
    let icon:String
    var body:some View {
        Image(systemName:icon).font(.system(size:14,weight:.semibold))
            .foregroundStyle(.white).frame(width:32,height:32)
            .background(.white.opacity(0.07),in:Circle())
            .overlay(Circle().stroke(.white.opacity(0.17),lineWidth:1))
    }
}

private struct RTabBar:View {
    @Binding var selection:WeatherTab
    var body:some View {
        HStack(spacing:3) {
            ForEach(WeatherTab.allCases) { tab in
                Button { selection = tab } label: {
                    VStack(spacing:5) {
                        Image(systemName:tab.symbol).font(.system(size:20,weight:.semibold))
                        Text(tab == .watch ? "Vädervakter" : tab == .more ? "Inställningar" : tab.rawValue)
                            .font(.system(size:9,weight:.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(selection == tab ? RTheme.cyan:.white.opacity(0.68))
                    .frame(maxWidth:.infinity).frame(height:58)
                    .background(selection == tab ? LinearGradient(colors:[RTheme.blue.opacity(0.58),RTheme.cyan.opacity(0.08)],startPoint:.top,endPoint:.bottom) : LinearGradient(colors:[.clear,.clear],startPoint:.top,endPoint:.bottom),in:RoundedRectangle(cornerRadius:15))
                }.buttonStyle(.plain)
            }
        }.padding(6)
            .background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:21))
            .overlay(RoundedRectangle(cornerRadius:21).stroke(.white.opacity(0.15),lineWidth:1))
            .padding(.horizontal,13).padding(.top,5).padding(.bottom,3)
            .background(LinearGradient(colors:[RTheme.bg.opacity(0),RTheme.bg.opacity(0.96)],startPoint:.top,endPoint:.bottom))
    }
}

private struct RPlaceholder:View {
    let title:String
    let subtitle:String
    let icon:String
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Image(systemName:icon).font(.system(size:42)).foregroundStyle(RTheme.cyan)
            Text(title).font(.system(size:29,weight:.bold,design:.rounded)).foregroundStyle(.white)
            Text(subtitle).font(.system(size:15,weight:.semibold)).foregroundStyle(RTheme.cyan)
            Text("Den här delen av appen byggs vidare efter startsidan.")
                .font(.system(size:13)).foregroundStyle(RTheme.muted)
            Spacer()
        }.padding(25).padding(.top,50).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
    }
}

private extension View {
    func referencePanel()->some View {
        padding(12)
            .background(RTheme.panel,in:RoundedRectangle(cornerRadius:19))
            .overlay(RoundedRectangle(cornerRadius:19).stroke(RTheme.line.opacity(0.75),lineWidth:1))
            .shadow(color:.black.opacity(0.24),radius:12,y:6)
    }
}
