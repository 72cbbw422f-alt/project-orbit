import SwiftUI
import MapKit

private struct RainViewerFrame: Identifiable, Decodable {
    let time: TimeInterval
    let path: String
    var id: TimeInterval { time }
}

private struct RainViewerManifest: Decodable {
    let host: String
    let radar: Radar
    struct Radar: Decodable { let past: [RainViewerFrame] }
}

private enum RainViewerService {
    static func loadFrames() async throws -> (String, [RainViewerFrame]) {
        let url = URL(string: "https://api.rainviewer.com/public/weather-maps.json")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let manifest = try JSONDecoder().decode(RainViewerManifest.self, from: data)
        let frames = manifest.radar.past.sorted { $0.time < $1.time }
        guard !frames.isEmpty else { throw URLError(.cannotParseResponse) }
        return (manifest.host, frames)
    }
}

struct RadarMapView: View {
    let coordinate: CLLocationCoordinate2D?
    let place: String

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var frames: [RainViewerFrame] = []
    @State private var selectedIndex = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastUpdated: Date?
    @State private var isPlaying = false
    @State private var host = ""

    private let playback = Timer.publish(every: 0.85, on: .main, in: .common).autoconnect()

    private var mapCoordinate: CLLocationCoordinate2D {
        let value = coordinate ?? CLLocationCoordinate2D(latitude: 61.7274, longitude: 17.1058)
        let latitude = value.latitude.isFinite ? min(85, max(-85, value.latitude)) : 61.7274
        let longitude = value.longitude.isFinite ? min(180, max(-180, value.longitude)) : 17.1058
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var initialPosition: MapCameraPosition {
        .region(MKCoordinateRegion(
            center: mapCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2)
        ))
    }

    private var selectedFrame: RainViewerFrame? {
        frames.indices.contains(selectedIndex) ? frames[selectedIndex] : nil
    }

    var body: some View {
        ZStack {
            Color(red: 0.008, green: 0.025, blue: 0.055).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("NEDERBÖRDSRADAR")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text(place.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(.cyan)
                    }
                    Spacer()
                    Button { Task { await refreshRadar() } } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.cyan)
                            .padding(10)
                            .background(.white.opacity(0.08), in: Circle())
                    }
                    .accessibilityLabel("Uppdatera radarn")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)

                Map(position: $cameraPosition) {
                    Marker(place, coordinate: mapCoordinate).tint(.cyan)
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 10) {
                    HStack {
                        HStack(spacing: 7) {
                            Circle().fill(frames.isEmpty ? .orange : .cyan).frame(width: 7, height: 7)
                            Text(frames.isEmpty ? "RADAR" : "RADARDATA HÄMTAD")
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(0.8)
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        Text("RainViewer")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }

                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView().tint(.cyan)
                            Text("Hämtar radartider…")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    } else if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let selectedFrame {
                        HStack {
                            Text(Date(timeIntervalSince1970: selectedFrame.time)
                                .formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Spacer()
                            Text("HISTORISKA RADARTIDER")
                                .font(.system(size: 8, weight: .heavy))
                                .tracking(0.7)
                                .foregroundStyle(.cyan)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(selectedIndex) },
                                set: { selectedIndex = Int($0.rounded()) }
                            ),
                            in: 0...Double(max(0, frames.count - 1)),
                            step: 1
                        )
                        .tint(.cyan)
                        .disabled(frames.count < 2)
                        HStack(spacing: 14) {
                            Button {
                                selectedIndex = max(0, selectedIndex - 1)
                            } label: {
                                Image(systemName: "backward.end.fill")
                            }
                            Button {
                                isPlaying.toggle()
                            } label: {
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 15, weight: .bold))
                                    .frame(width: 40, height: 40)
                                    .background(Color.cyan.opacity(0.18), in: Circle())
                            }
                            Button {
                                selectedIndex = min(frames.count - 1, selectedIndex + 1)
                            } label: {
                                Image(systemName: "forward.end.fill")
                            }
                            Spacer()
                            if let lastUpdated {
                                Text("Uppdaterad \(lastUpdated.formatted(date: .omitted, time: .shortened))")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.cyan)
                    } else {
                        Text("Tryck på uppdatera för att hämta tillgängliga radartider.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack {
                        Text("Kartunderlag: Apple Maps")
                        Spacer()
                        Text("Nederbördsbild kopplas in i nästa steg")
                    }
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                }
                .padding(14)
                .background(Color(red: 0.015, green: 0.075, blue: 0.13).opacity(0.95), in: RoundedRectangle(cornerRadius: 18))
                .padding(10)
            }
        }
        .onAppear { cameraPosition = initialPosition }
        .task { await refreshRadar() }
        .onReceive(playback) { _ in
            guard isPlaying, !frames.isEmpty else { return }
            selectedIndex = selectedIndex >= frames.count - 1 ? 0 : selectedIndex + 1
        }
    }

    @MainActor
    private func refreshRadar() async {
        guard !isLoading else { return }
        isLoading = true
        isPlaying = false
        errorMessage = nil
        do {
            let result = try await RainViewerService.loadFrames()
            host = result.0
            frames = result.1
            selectedIndex = max(0, frames.count - 1)
            lastUpdated = Date()
        } catch {
            errorMessage = "Radartider kunde inte hämtas just nu."
        }
        isLoading = false
    }
}
