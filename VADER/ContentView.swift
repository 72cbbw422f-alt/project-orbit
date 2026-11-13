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
                        showSevenDayForecast: { showingSevenDayForecast = true }
                    )
                case .radar: RPlaceholder(title: "Radar", subtitle: "Nederbördsradar", icon: "dot.radiowaves.left.and.right")
                case .watch: VaktDashboard(weather: weatherModel.snapshot ?? .demo, days: weatherModel.days, hours: weatherModel.hours)
                case .places: RPlaceholder(title: "Platser", subtitle: "Dina sparade platser", icon: "mappin.and.ellipse")
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
                    ActiveWatchSummary(weather: weather, days: days, hours: hours)
                    precipitationCard
                    compactMetrics
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
            VStack(alignment: .trailing, spacing: 3) {
                Text("SENAST UPPDATERAD")
                    .font(.system(size: 7, weight: .bold)).tracking(0.7)
                    .foregroundStyle(RTheme.muted)
                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(RTheme.cyan)
                }.buttonStyle(.plain)
            }
        }
    }

    private var currentConditions: some View {
        HStack(spacing: 12) {
            Image(systemName: "cloud.rain.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color(red:0.82,green:0.91,blue:1), RTheme.cyan)
                .font(.system(size: 57))
                .shadow(color: RTheme.cyan.opacity(0.42), radius: 15)
                .frame(width: 76)
            Text("\(weather.temperature)°")
                .font(.system(size: 67, weight: .semibold, design: .rounded))
                .tracking(-4).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 3) {
                Text(weather.condition)
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .lineLimit(2).minimumScaleFactor(0.8)
                Text("Känns som \(weather.feelsLike)°")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(RTheme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
    }

    private func mainCards(width: CGFloat) -> some View {
        let windWidth = max(112, width * 0.30)
        return HStack(alignment: .top, spacing: 9) {
            rainAlertCard
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            windCard
                .frame(width: windWidth, height: 190)
        }
        .frame(height: 190)
    }

    private var rainAlertCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Label(watchTitle, systemImage: "umbrella.fill")
                    .font(.system(size: 9, weight: .heavy))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(LinearGradient(colors:[RTheme.blue,RTheme.cyan.opacity(0.72)],startPoint:.leading,endPoint:.trailing),in:Capsule())
                    .foregroundStyle(.white)
                Spacer(minLength: 1)
                HStack(spacing: 3) {
                    Circle().fill(.green).frame(width:6,height:6)
                    Text(isLive ? "LIVE" : "DEMO").font(.system(size:7,weight:.heavy))
                }.foregroundStyle(.green)
            }
            Text(isLive ? "Aktuellt väder" : "Regn närmar sig")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.75)
            Text(isLive ? weather.condition : "Om 18 min")
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .tracking(-1.2).foregroundStyle(RTheme.cyan)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(isLive ? "Just nu \(String(format: "%.1f", weather.precipitationToday)) mm nederbörd registrerad i aktuell tidsperiod." : "Måttlig nederbörd väntas pågå i ca 45 min.")
                .font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.88))
                .lineLimit(2).fixedSize(horizontal:false,vertical:true)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                miniRainStat(icon:"thermometer",title:"Temperatur",value:"\(weather.temperature)°")
                miniRainStat(icon:"wind",title:"Vind",value:String(format:"%.1f m/s",weather.wind))
                miniRainStat(icon:"drop.fill",title:"Nederbörd",value:String(format:"%.1f mm",weather.precipitationToday))
            }
        }
        .padding(11)
        .background {
            RoundedRectangle(cornerRadius: 19)
                .fill(LinearGradient(colors:[Color(red:0.015,green:0.16,blue:0.27).opacity(0.98),Color(red:0.015,green:0.065,blue:0.13).opacity(0.96)],startPoint:.topLeading,endPoint:.bottomTrailing))
        }
        .overlay(alignment:.trailing) {
            Image(systemName:watchSymbol)
                .font(.system(size:54))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white.opacity(0.12),RTheme.cyan.opacity(0.23))
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
        VStack(alignment:.leading,spacing:7) {
            Label("Vind",systemImage:"wind").font(.system(size:14,weight:.bold)).foregroundStyle(.white)
            Spacer(minLength:0)
            ZStack {
                Circle().fill(.white.opacity(0.025))
                Circle().stroke(.white.opacity(0.20),lineWidth:1)
                ForEach(0..<36,id:\.self) { i in
                    Capsule().fill(.white.opacity(i.isMultiple(of:3) ? 0.85 : 0.28))
                        .frame(width:1,height:i.isMultiple(of:3) ? 7:4)
                        .offset(y:-35).rotationEffect(.degrees(Double(i)*10))
                }
                VStack { Text("N"); Spacer(); Text("S") }
                    .font(.system(size:9,weight:.heavy)).foregroundStyle(.white).padding(.vertical,5)
                HStack { Text("V"); Spacer(); Text("Ö") }
                    .font(.system(size:9,weight:.heavy)).foregroundStyle(.white).padding(.horizontal,5)
                Image(systemName:"location.north.fill")
                    .font(.system(size:22,weight:.bold)).foregroundStyle(RTheme.cyan)
                    .rotationEffect(.degrees(weather.windDirectionDegrees))
                    .shadow(color:RTheme.cyan.opacity(0.7),radius:8)
                VStack(spacing:0) {
                    Text(String(format:"%.1f",weather.wind))
                        .font(.system(size:19,weight:.bold,design:.rounded))
                    Text("m/s").font(.system(size:8,weight:.bold))
                }.foregroundStyle(.white)
            }.frame(maxWidth:.infinity).aspectRatio(1,contentMode:.fit)
            Text(String(format:"Byvind %.1f m/s",weather.windGust))
                .font(.system(size:8,weight:.semibold)).foregroundStyle(RTheme.muted)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(10)
        .background(RTheme.panel,in:RoundedRectangle(cornerRadius:19))
        .overlay(RoundedRectangle(cornerRadius:19).stroke(RTheme.line,lineWidth:1))
        .shadow(color:.black.opacity(0.25),radius:12,y:6)
    }

    private var precipitationCard: some View {
        VStack(alignment:.leading,spacing:8) {
            Label("Nederbörd kommande 2 timmar",systemImage:"cloud.drizzle.fill")
                .font(.system(size:14,weight:.bold)).foregroundStyle(.white)
            HStack(alignment:.bottom,spacing:5) {
                VStack(alignment:.trailing,spacing:12) {
                    Text("Kraftig"); Text("Måttlig"); Text("Lätt")
                }
                .font(.system(size:8,weight:.medium)).foregroundStyle(RTheme.muted)
                .frame(width:38,height:70,alignment:.bottom)
                GeometryReader { proxy in
                    ZStack(alignment:.bottom) {
                        VStack(spacing:0) {
                            ForEach(0..<3,id:\.self) { _ in
                                Rectangle().fill(.white.opacity(0.17)).frame(height:1)
                                Spacer(minLength:0)
                            }
                        }
                        HStack(alignment:.bottom,spacing:3) {
                            ForEach(bars.indices,id:\.self) { index in
                                RoundedRectangle(cornerRadius:2)
                                    .fill(LinearGradient(colors:[RTheme.cyan,Color(red:0.0,green:0.45,blue:0.88)],startPoint:.top,endPoint:.bottom))
                                    .frame(maxWidth:.infinity)
                                    .frame(height:max(3,proxy.size.height*bars[index]))
                            }
                        }
                    }
                }.frame(height:70)
            }
            HStack {
                Text("Nu"); Spacer(); Text("15 min"); Spacer(); Text("30 min"); Spacer(); Text("45 min"); Spacer(); Text("60 min"); Spacer(); Text("90 min"); Spacer(); Text("120 min")
            }.font(.system(size:8,weight:.medium)).foregroundStyle(RTheme.muted)
                .padding(.leading,43)
            Text("Illustrativ kurva – inte en uppmätt prognos.")
                .font(.system(size:8)).foregroundStyle(RTheme.muted.opacity(0.8))
        }.referencePanel()
    }

    private var sevenDayForecast: some View {
        Button(action: showSevenDayForecast) {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(RTheme.cyan)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text("7-dygnsprognos")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Text(days.isEmpty
                         ? "Tryck för att öppna veckoprognosen"
                         : "Se temperatur, nederbörd, vind och UV för hela veckan")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(RTheme.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(RTheme.cyan)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 19))
        }
        .buttonStyle(.plain)
        .referencePanel()
    }

    private func forecastDetail(icon: String, title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(RTheme.cyan)
            Text(title).font(.system(size: 7, weight: .medium)).foregroundStyle(RTheme.muted)
            Text(value).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
        }.frame(maxWidth: .infinity)
    }

    private var compactMetrics: some View {
        HStack(spacing:7) {
            circularMetric(title:"Luftfuktighet",symbol:"humidity.fill",value:"\(weather.humidity)%",progress:Double(weather.humidity)/100,tint:RTheme.cyan)
            circularMetric(title:"Tryck",symbol:"gauge",value:"1012",progress:0.62,tint:Color(red:0.42,green:0.72,blue:0.94),suffix:"hPa")
            circularMetric(title:"UV-index",symbol:"sun.max.fill",value:"\(weather.uvIndex)",progress:0.03,tint:.green,suffix:"Låg")
            moonMetric
        }
        .frame(height:111)
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

    private var moonMetric: some View {
        VStack(spacing:5) {
            Label("Sol & måne",systemImage:"moon.stars.fill")
                .font(.system(size:8,weight:.semibold)).foregroundStyle(.white).lineLimit(1)
            Image(systemName:"moon.fill").font(.system(size:29)).foregroundStyle(Color(red:0.77,green:0.83,blue:0.94))
            Text("Månfas").font(.system(size:8,weight:.medium)).foregroundStyle(RTheme.muted)
            Text("—").font(.system(size:11,weight:.bold)).foregroundStyle(.white)
        }.frame(maxWidth:.infinity,maxHeight:.infinity).padding(6)
            .background(RTheme.panel,in:RoundedRectangle(cornerRadius:17))
            .overlay(RoundedRectangle(cornerRadius:17).stroke(RTheme.line.opacity(0.7),lineWidth:1))
    }

    private var daylightStrip: some View {
        HStack(spacing:7) {
            Image(systemName:"sun.max.fill").font(.system(size:17)).foregroundStyle(.yellow)
            Text("Dagslängd").font(.system(size:11,weight:.semibold)).foregroundStyle(.white)
            Text("— h — min").font(.system(size:11,weight:.bold)).foregroundStyle(.white)
            Spacer()
            Text("Soluppgång  —:—  •  Solnedgång  —:—")
                .font(.system(size:8,weight:.medium)).foregroundStyle(RTheme.muted)
        }.padding(.horizontal,12).padding(.vertical,11)
            .background(RTheme.panel,in:Capsule())
            .overlay(Capsule().stroke(RTheme.line.opacity(0.7),lineWidth:1))
    }

    private var hourlyCard: some View {
        VStack(alignment:.leading,spacing:11) {
            HStack {
                Label("Kommande timmar",systemImage:"clock")
                    .font(.system(size:14,weight:.bold)).foregroundStyle(.white)
                Spacer()
                Text("VISA MER  ›").font(.system(size:9,weight:.bold)).foregroundStyle(RTheme.cyan)
            }
            HStack(spacing:0) {
                if hours.isEmpty {
                    Text("Timprognosen visas när väderdata har hämtats.")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(RTheme.muted)
                } else {
                ForEach(hours) { hour in
                    VStack(spacing:7) {
                        Text(hour.time).font(.system(size:10,weight:.semibold)).foregroundStyle(.white)
                        Image(systemName:hour.symbol).symbolRenderingMode(.palette)
                            .foregroundStyle(Color(red:0.82,green:0.90,blue:1),RTheme.cyan)
                            .font(.system(size:22)).frame(height:27)
                        Text("\(hour.precipitationChance)%").font(.system(size:9,weight:.bold)).foregroundStyle(RTheme.cyan)
                        Text("\(hour.temperature)°").font(.system(size:14,weight:.bold,design:.rounded)).foregroundStyle(.white)
                    }.frame(maxWidth:.infinity)
                }
                }
            }
        }.referencePanel()
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
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 9) {
                                    ForEach(days) { day in
                                        VStack(alignment: .center, spacing: 9) {
                                            Text(day.day)
                                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                                .foregroundStyle(.white)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.75)

                                            Image(systemName: day.symbol)
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(.white, RTheme.cyan)
                                                .font(.system(size: 29))
                                                .frame(height: 34)

                                            Text(day.condition)
                                                .font(.system(size: 9, weight: .medium))
                                                .foregroundStyle(RTheme.muted)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.7)

                                            HStack(spacing: 7) {
                                                Text("\(day.high)°")
                                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                                    .foregroundStyle(.white)
                                                Text("\(day.low)°")
                                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                                    .foregroundStyle(RTheme.muted)
                                            }

                                            Rectangle()
                                                .fill(.white.opacity(0.09))
                                                .frame(height: 1)

                                            compactForecastMetric(icon: "drop.fill", value: "\(day.precipitationChance)%")
                                            compactForecastMetric(icon: "cloud.rain.fill", value: String(format: "%.1f mm", day.precipitation))
                                            compactForecastMetric(icon: "wind", value: String(format: "%.1f m/s", day.wind))
                                            compactForecastMetric(icon: "sun.max.fill", value: String(format: "UV %.0f", day.uv))
                                        }
                                        .frame(width: 112)
                                        .padding(.vertical, 12)
                                        .padding(.horizontal, 8)
                                        .background(RTheme.panel, in: RoundedRectangle(cornerRadius: 17))
                                        .overlay(RoundedRectangle(cornerRadius: 17).stroke(RTheme.line.opacity(0.75), lineWidth: 1))
                                    }
                                }
                                .padding(.vertical, 2)
                            }
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

    private func compactForecastMetric(icon: String, value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(RTheme.cyan)
                .frame(width: 12)
            Text(value)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
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
