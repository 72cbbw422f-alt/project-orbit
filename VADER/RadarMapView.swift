import SwiftUI
import MapLibre
import Combine
import UIKit

private struct RadarFrame: Identifiable, Equatable {
    let time: Date
    let path: String
    var id: TimeInterval { time.timeIntervalSince1970 }
}

private enum RadarService {
    private struct Manifest: Decodable {
        struct Radar: Decodable {
            struct Frame: Decodable {
                let time: TimeInterval
                let path: String
            }
            let past: [Frame]
        }
        let host: String
        let radar: Radar
    }

    static func loadFrames() async throws -> (String, [RadarFrame]) {
        var request = URLRequest(url: URL(string: "https://api.rainviewer.com/public/weather-maps.json")!)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Regnvakt iOS", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        let frames = manifest.radar.past.map {
            RadarFrame(time: Date(timeIntervalSince1970: $0.time), path: $0.path)
        }.sorted { $0.time < $1.time }
        guard !frames.isEmpty else { throw URLError(.dataNotAllowed) }
        return (manifest.host, frames)
    }
}

struct RadarMapView: View {
    let coordinate: CLLocationCoordinate2D?
    let place: String

    @State private var radarHost = "https://tilecache.rainviewer.com"
    @State private var frames: [RadarFrame] = []
    @State private var selectedIndex = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastUpdated: Date?
    @State private var isPlaying = false
    @State private var showRadar = true
    @State private var precipitationType = "Hämtar nederbördstyp…"
    @State private var typeDetail = "Modellbedömning vid vald plats"
    @State private var showTypeInfo = false

    private let playback = Timer.publish(every: 0.75, on: .main, in: .common).autoconnect()

    private var mapCoordinate: CLLocationCoordinate2D {
        let value = coordinate ?? CLLocationCoordinate2D(latitude: 61.7274, longitude: 17.1058)
        return CLLocationCoordinate2D(
            latitude: value.latitude.isFinite ? min(85, max(-85, value.latitude)) : 61.7274,
            longitude: value.longitude.isFinite ? min(180, max(-180, value.longitude)) : 17.1058
        )
    }

    private var selectedFrame: RadarFrame? {
        frames.indices.contains(selectedIndex) ? frames[selectedIndex] : nil
    }

    private var radarTileURL: String? {
        guard showRadar, let frame = selectedFrame else { return nil }
        return "\(radarHost)\(frame.path)/512/{z}/{x}/{y}/2/1_1.png"
    }

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.055, blue: 0.085).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("REGNVAKT")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .tracking(2.2)
                            .foregroundStyle(Color(red: 0.45, green: 0.83, blue: 1))
                        Text("Nederbördsradar")
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(place)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.68))
                    }
                    Spacer()
                    Button { showRadar.toggle() } label: {
                        Image(systemName: showRadar ? "cloud.rain.fill" : "cloud")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(showRadar ? Color.cyan : .white.opacity(0.75))
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.09), in: Circle())
                    }
                    .accessibilityLabel(showRadar ? "Dölj radar" : "Visa radar")
                    Button { Task { await refreshRadar() } } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.09), in: Circle())
                    }
                    .accessibilityLabel("Uppdatera radarn")
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 12)

                ZStack(alignment: .topLeading) {
                    RegnvaktMapView(coordinate: mapCoordinate, radarTileURL: radarTileURL)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    HStack(spacing: 7) {
                        Circle().fill(Color(red: 0.25, green: 0.88, blue: 0.96)).frame(width: 7, height: 7)
                        Text("RADAR • RAINVIEWER")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1)
                            .foregroundStyle(.white)
                        Spacer()
                        Text("© OpenStreetMap")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.black.opacity(0.48), in: Capsule())
                    .padding(12)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 13) {
                    HStack(spacing: 9) {
                        Image(systemName: precipitationSymbol)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(Color(red: 0.45, green: 0.83, blue: 1))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(precipitationType)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                            Text(typeDetail)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.62))
                        }
                        Spacer()
                        Button { showTypeInfo = true } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 19))
                                .foregroundStyle(Color.cyan)
                        }
                    }
                    .padding(12)
                    .background(Color(red: 0.10, green: 0.15, blue: 0.21), in: RoundedRectangle(cornerRadius: 15))

                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView().tint(.cyan)
                            Text("Hämtar senaste radarobservationer…")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    } else if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let selectedFrame {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("VALD RADARTID")
                                    .font(.system(size: 9, weight: .heavy))
                                    .tracking(1)
                                    .foregroundStyle(Color.cyan)
                                Text(selectedFrame.time.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(.white)
                            }
                            Spacer()
                            Text("SENASTE 2 TIMMARNA")
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(0.8)
                                .foregroundStyle(.white.opacity(0.58))
                        }
                        Slider(value: Binding(
                            get: { Double(selectedIndex) },
                            set: { selectedIndex = Int($0.rounded()) }
                        ), in: 0...Double(max(0, frames.count - 1)), step: 1)
                        .tint(Color(red: 0.27, green: 0.79, blue: 1))
                        .disabled(frames.count < 2)
                        HStack(spacing: 18) {
                            Button { selectedIndex = max(0, selectedIndex - 1) } label: {
                                Image(systemName: "backward.end.fill").font(.system(size: 17))
                            }
                            Button { isPlaying.toggle() } label: {
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(Color(red: 0.03, green: 0.09, blue: 0.14))
                                    .frame(width: 48, height: 48)
                                    .background(Color(red: 0.43, green: 0.84, blue: 1), in: Circle())
                            }
                            Button { selectedIndex = min(frames.count - 1, selectedIndex + 1) } label: {
                                Image(systemName: "forward.end.fill").font(.system(size: 17))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("OBSERVATION")
                                    .font(.system(size: 8, weight: .heavy))
                                    .tracking(0.8)
                                    .foregroundStyle(.white.opacity(0.45))
                                Text(lastUpdated?.formatted(date: .omitted, time: .shortened) ?? "—")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.72))
                            }
                        }
                        .foregroundStyle(Color(red: 0.45, green: 0.83, blue: 1))
                    } else {
                        Text("Radarhistorik visas här när data har hämtats.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack {
                        Text("Väderdata från RainViewer")
                        Spacer()
                        Text("Karta © OpenStreetMap")
                    }
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
                }
                .padding(16)
                .background(
                    LinearGradient(colors: [
                        Color(red: 0.075, green: 0.12, blue: 0.18),
                        Color(red: 0.055, green: 0.09, blue: 0.14)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.07), lineWidth: 1))
                .padding(12)
            }
        }
        .task {
            await refreshRadar()
            await refreshPrecipitationType()
        }
        .onChange(of: selectedIndex) { _, _ in
            if selectedFrame != nil { }
        }
        .onReceive(playback) { _ in
            guard isPlaying, !frames.isEmpty else { return }
            selectedIndex = selectedIndex >= frames.count - 1 ? 0 : selectedIndex + 1
        }
        .alert("Om nederbördstyp", isPresented: $showTypeInfo) {
            Button("Stäng", role: .cancel) {}
        } message: {
            Text("Radarbilden visar observerad nederbörd från RainViewer. Nederbördstypen vid din valda plats hämtas separat från en vädermodell och är en bedömning – inte en direkt klassificering av varje radar-pixel.")
        }
    }

    private var precipitationSymbol: String {
        let text = precipitationType.lowercased()
        if text.contains("snö") { return "cloud.snow.fill" }
        if text.contains("hagel") { return "cloud.hail.fill" }
        if text.contains("regn") { return "cloud.rain.fill" }
        return "cloud.fill"
    }

    @MainActor
    private func refreshRadar() async {
        guard !isLoading else { return }
        isLoading = true
        isPlaying = false
        errorMessage = nil
        do {
            let result = try await RadarService.loadFrames()
            radarHost = result.0
            frames = result.1
            selectedIndex = frames.count - 1
            lastUpdated = Date()
        } catch {
            errorMessage = "Radarleverantören kunde inte nås. Försök igen om en stund."
        }
        isLoading = false
    }

    @MainActor
    private func refreshPrecipitationType() async {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(mapCoordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(mapCoordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components.url else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = root["current"] as? [String: Any] else { return }
            let temp = (current["temperature_2m"] as? NSNumber)?.doubleValue ?? 0
            let code = (current["weather_code"] as? NSNumber)?.intValue ?? 0
            precipitationType = Self.precipitationName(code: code, temperature: temp)
            typeDetail = "Modellbedömning • \(Int(temp.rounded()))°C vid \(place)"
        } catch {
            precipitationType = "Nederbördstyp saknas"
            typeDetail = "Kunde inte hämta modellbedömning"
        }
    }

    private static func precipitationName(code: Int, temperature: Double) -> String {
        switch code {
        case 51...57: return temperature <= 0 ? "Möjligen underkylt duggregn" : "Duggregn"
        case 61...67: return temperature <= 0 ? "Möjligen underkylt regn" : "Regn"
        case 71...77, 85...86: return "Snö"
        case 80...82: return temperature <= 0 ? "Möjligen underkylda skurar" : "Regnskurar"
        case 95...99: return "Åska"
        default: return "Ingen nederbörd enligt modellen"
        }
    }
}

private struct RegnvaktMapView: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    let radarTileURL: String?
    private let styleURL = URL(string: "https://tiles.openfreemap.org/styles/fiord")!

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: styleURL)
        map.delegate = context.coordinator
        map.logoView.isHidden = false
        map.attributionButton.isHidden = false
        map.compassView.isHidden = false
        map.showsUserLocation = false
        map.allowsRotating = false
        map.allowsTilting = false
        map.minimumZoomLevel = 3
        map.maximumZoomLevel = 12
        map.setCenter(coordinate, zoomLevel: 7.0, animated: false)
        context.coordinator.latestTileURL = radarTileURL
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.latestTileURL = radarTileURL
        context.coordinator.applyRadarIfReady()
        let previous = context.coordinator.lastCoordinate
        if previous == nil || abs(previous!.latitude - coordinate.latitude) > 0.001 ||
            abs(previous!.longitude - coordinate.longitude) > 0.001 {
            context.coordinator.lastCoordinate = coordinate
            map.setCenter(coordinate, zoomLevel: min(max(map.zoomLevel, 7.0), 12), animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        weak var mapView: MLNMapView?
        var latestTileURL: String?
        var lastCoordinate: CLLocationCoordinate2D?
        private var styleReady = false
        private var appliedURL: String?

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            self.mapView = mapView
            styleReady = true
            appliedURL = nil
            applyRadarIfReady()
        }

        func applyRadarIfReady() {
            guard styleReady, let style = mapView?.style else { return }
            guard appliedURL != latestTileURL else { return }
            if let layer = style.layer(withIdentifier: "regnvakt-radar-layer") {
                style.removeLayer(layer)
            }
            if let source = style.source(withIdentifier: "regnvakt-radar-source") {
                style.removeSource(source)
            }
            appliedURL = latestTileURL
            guard let template = latestTileURL else { return }
            let source = MLNRasterTileSource(
                identifier: "regnvakt-radar-source",
                tileURLTemplates: [template],
                options: nil
            )
            let layer = MLNRasterStyleLayer(identifier: "regnvakt-radar-layer", source: source)
            layer.rasterOpacity = NSExpression(forConstantValue: 0.82)
            style.addSource(source)
            style.addLayer(layer)
        }
    }
}
