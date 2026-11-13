import SwiftUI
import MapKit

struct RadarMapView: View {
    let coordinate: CLLocationCoordinate2D?
    let place: String

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

    @State private var cameraPosition: MapCameraPosition = .automatic

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
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.cyan)
                        .padding(10)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)

                Map(position: $cameraPosition) {
                    Marker(place, coordinate: mapCoordinate)
                        .tint(.cyan)
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 7) {
                        Circle().fill(.orange).frame(width: 7, height: 7)
                        Text("KARTTEST")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(0.8)
                            .foregroundStyle(.white)
                        Spacer()
                        Text("Nederbördsöverlägg avstängt")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    Text("Den här testversionen använder Apples inbyggda karta utan externa radaröverlägg. Syftet är att kontrollera om själva kartvyn öppnas utan att appen kraschar.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        cameraPosition = initialPosition
                    } label: {
                        Label("Centrera på \(place)", systemImage: "location.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.cyan)
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(Color(red: 0.015, green: 0.075, blue: 0.13).opacity(0.95), in: RoundedRectangle(cornerRadius: 18))
                .padding(10)
            }
        }
        .onAppear {
            cameraPosition = initialPosition
        }
    }
}
