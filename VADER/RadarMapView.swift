import SwiftUI
import MapKit
import Combine

private struct RadarFrame: Identifiable, Decodable {
    let time: TimeInterval
    let path: String
    var id: TimeInterval { time }
}

private struct RadarIndex: Decodable {
    let host: String
    let radar: RadarFrames
    struct RadarFrames: Decodable { let past: [RadarFrame] }
}

private enum RadarService {
    static func frames() async throws -> (String, [RadarFrame]) {
        let url = URL(string: "https://api.rainviewer.com/public/weather-maps.json")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let index = try JSONDecoder().decode(RadarIndex.self, from: data)
        let frames = index.radar.past.sorted { $0.time < $1.time }
        guard !frames.isEmpty else { throw URLError(.cannotParseResponse) }
        return (index.host, frames)
    }
}

private struct RadarMapRepresentable: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    let host: String
    let frame: RadarFrame?

    func makeCoordinator() -> Coordinator { Coordinator() }

    private var safeCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinate.latitude.isFinite ? min(85, max(-85, coordinate.latitude)) : 61.7274,
                               longitude: coordinate.longitude.isFinite ? min(180, max(-180, coordinate.longitude)) : 17.1058)
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 360, height: 430))
        map.delegate = context.coordinator
        map.mapType = .mutedStandard
        map.overrideUserInterfaceStyle = .dark
        map.showsCompass = true
        map.showsScale = true
        map.pointOfInterestFilter = .excludingAll
        map.setRegion(MKCoordinateRegion(center: safeCoordinate, latitudinalMeters: 150000, longitudinalMeters: 150000), animated: false)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let target = safeCoordinate
        if context.coordinator.lastCoordinate.latitude != target.latitude ||
            context.coordinator.lastCoordinate.longitude != target.longitude {
            context.coordinator.lastCoordinate = target
            map.setRegion(MKCoordinateRegion(center: target, latitudinalMeters: 150000, longitudinalMeters: 150000), animated: true)
        }
        guard !host.isEmpty, context.coordinator.lastFrameID != frame?.id, let frame else { return }
        context.coordinator.lastFrameID = frame.id
        map.overlays.filter { $0 is MKTileOverlay }.forEach { map.removeOverlay($0) }
        let template = "\(host)\(frame.path)/256/{z}/{x}/{y}/2/1_1.png"
        let overlay = MKTileOverlay(urlTemplate: template)
        overlay.canReplaceMapContent = false
        overlay.minimumZ = 0
        overlay.maximumZ = 7
        overlay.tileSize = CGSize(width: 256, height: 256)
        map.addOverlay(overlay, level: .aboveLabels)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var lastFrameID: TimeInterval?
        var lastCoordinate = CLLocationCoordinate2D(latitude: .nan, longitude: .nan)
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                let renderer = MKTileOverlayRenderer(tileOverlay: tile)
                renderer.alpha = 0.78
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

struct RadarMapView: View {
    let coordinate: CLLocationCoordinate2D?
    let place: String
    @State private var host = ""
    @State private var frames: [RadarFrame] = []
    @State private var selectedIndex = 0
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isPlaying = false
    @State private var lastFetched: Date?
    private let playback = Timer.publish(every: 0.85, on: .main, in: .common).autoconnect()

    private var mapCoordinate: CLLocationCoordinate2D {
        coordinate ?? CLLocationCoordinate2D(latitude: 61.7274, longitude: 17.1058)
    }
    private var selectedFrame: RadarFrame? { frames.indices.contains(selectedIndex) ? frames[selectedIndex] : nil }

    var body: some View {
        ZStack {
            Color(red: 0.008, green: 0.025, blue: 0.055).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("NEDERBÖRDSRADAR").font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(.white)
                        Text(place.uppercased()).font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(Color.cyan)
                    }
                    Spacer()
                    Button { Task { await loadFrames() } } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 16, weight: .bold)).foregroundStyle(.cyan)
                            .padding(10).background(.white.opacity(0.08), in: Circle())
                    }
                    .accessibilityLabel("Uppdatera radarn")
                }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)

                ZStack {
                    RadarMapRepresentable(coordinate: mapCoordinate, host: host, frame: selectedFrame)
                        .frame(maxWidth: .infinity)
                        .frame(height: 430)
                    if isLoading {
                        ProgressView("Hämtar radar…").tint(.cyan).padding(14).background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
                    } else if let errorMessage {
                        VStack(spacing: 7) {
                            Image(systemName: "wifi.exclamationmark").font(.system(size: 25))
                            Text(errorMessage).font(.system(size: 12, weight: .semibold)).multilineTextAlignment(.center)
                            Button("Försök igen") { Task { await loadFrames() } }.font(.system(size: 12, weight: .bold)).foregroundStyle(.cyan)
                        }.foregroundStyle(.white).padding(18).background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 10)
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 6) {
                        Circle().fill(Color.cyan).frame(width: 7, height: 7)
                        Text("RADAR").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    }.foregroundStyle(.white).padding(9).background(.black.opacity(0.68), in: Capsule()).padding(20)
                }

                VStack(spacing: 10) {
                    HStack {
                        Text(selectedFrame.map { Date(timeIntervalSince1970: $0.time).formatted(date: .omitted, time: .shortened) } ?? "—")
                            .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        Spacer()
                        Text("SENASTE 2 TIMMARNA").font(.system(size: 8, weight: .heavy)).tracking(0.8).foregroundStyle(.cyan)
                    }
                    Slider(value: Binding(get: { Double(selectedIndex) }, set: { selectedIndex = Int($0.rounded()) }),
                           in: 0...Double(max(0, frames.count - 1)), step: 1)
                        .tint(.cyan).disabled(frames.isEmpty)
                    HStack(spacing: 14) {
                        Button { selectedIndex = max(0, selectedIndex - 1) } label: { Image(systemName: "backward.end.fill") }
                        Button { isPlaying.toggle() } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill").font(.system(size: 15, weight: .bold))
                                .frame(width: 40, height: 40).background(Color.cyan.opacity(0.18), in: Circle())
                        }
                        Button { selectedIndex = min(max(0, frames.count - 1), selectedIndex + 1) } label: { Image(systemName: "forward.end.fill") }
                        Spacer()
                        if let lastFetched {
                            Text("Uppdaterad \(lastFetched.formatted(date: .omitted, time: .shortened))")
                                .font(.system(size: 8, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                        }
                    }.font(.system(size: 15, weight: .bold)).foregroundStyle(.cyan)
                    HStack {
                        Text("Regn / nederbörd").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white)
                        Spacer()
                        Text("Data: RainViewer").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.65))
                    }
                }
                .padding(14)
                .background(Color(red: 0.015, green: 0.075, blue: 0.13).opacity(0.95), in: RoundedRectangle(cornerRadius: 18))
                .padding(10)
            }
        }
        .task { await loadFrames() }
        .onReceive(playback) { _ in
            guard isPlaying, !frames.isEmpty else { return }
            if selectedIndex >= frames.count - 1 { selectedIndex = 0 }
            else { selectedIndex += 1 }
        }
    }

    @MainActor
    private func loadFrames() async {
        isLoading = true
        errorMessage = nil
        isPlaying = false
        do {
            let result = try await RadarService.frames()
            host = result.0
            frames = result.1
            selectedIndex = max(0, frames.count - 1)
            lastFetched = Date()
        } catch {
            errorMessage = "Radardata kunde inte hämtas just nu."
        }
        isLoading = false
    }
}
