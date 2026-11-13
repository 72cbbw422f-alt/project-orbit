import SwiftUI

private enum PlacesPalette {
    static let cyan = Color(red: 0.04, green: 0.78, blue: 0.98)
    static let muted = Color(red: 0.69, green: 0.78, blue: 0.88)
    static let panel = Color(red: 0.015, green: 0.075, blue: 0.13).opacity(0.91)
    static let line = Color(red: 0.18, green: 0.52, blue: 0.72).opacity(0.48)
}

struct SavedPlacesView: View {
    @ObservedObject var model: WeatherViewModel
    let onAddPlace: () -> Void
    let onSelectPlace: () -> Void

    private var favorite: SavedWeatherPlace? {
        model.savedPlaces.first(where: \\.isFavorite)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(PlacesPalette.cyan)
                    Text("Platser")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Dina sparade väderplatser")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PlacesPalette.cyan)
                }
                Spacer()
                Button(action: onAddPlace) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(PlacesPalette.cyan.opacity(0.20), in: Circle())
                        .overlay(Circle().stroke(PlacesPalette.line, lineWidth: 1))
                }
                .accessibilityLabel("Lägg till plats")
            }

            Button {
                model.refresh()
                onSelectPlace()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(PlacesPalette.cyan)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Min nuvarande position")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Använd GPS för lokalt väder")
                            .font(.system(size: 11))
                            .foregroundStyle(PlacesPalette.muted)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .foregroundStyle(PlacesPalette.cyan)
                }
                .padding(14)
                .background(PlacesPalette.panel, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(PlacesPalette.line, lineWidth: 1))
            }
            .buttonStyle(.plain)

            if let favorite {
                VStack(alignment: .leading, spacing: 9) {
                    Text("FAVORIT")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(PlacesPalette.muted)
                    placeRow(favorite, prominent: true)
                }
            }

            HStack {
                Text("SPARADE PLATSER")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(PlacesPalette.muted)
                Spacer()
                Text("\(model.savedPlaces.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(PlacesPalette.muted)
            }

            if model.savedPlaces.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "star.circle")
                        .font(.system(size: 38))
                        .foregroundStyle(PlacesPalette.cyan.opacity(0.8))
                    Text("Inga sparade platser ännu")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Sök efter en ort och välj den. Då sparas den här så att du enkelt kan återvända.")
                        .font(.system(size: 12))
                        .foregroundStyle(PlacesPalette.muted)
                        .multilineTextAlignment(.center)
                    Button("Lägg till en plats", action: onAddPlace)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(PlacesPalette.cyan)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .padding(.horizontal, 18)
                .background(PlacesPalette.panel, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(PlacesPalette.line, lineWidth: 1))
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.savedPlaces.filter { !$0.isFavorite }) { place in
                            placeRow(place)
                        }
                    }
                    .padding(.bottom, 18)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 42)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func placeRow(_ place: SavedWeatherPlace, prominent: Bool = false) -> some View {
        HStack(spacing: 10) {
            Button {
                model.selectSavedPlace(place)
                onSelectPlace()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: prominent ? "star.fill" : "mappin")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(PlacesPalette.cyan)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(place.name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                        if prominent {
                            Text("Din favoritplats")
                                .font(.system(size: 10))
                                .foregroundStyle(PlacesPalette.muted)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(PlacesPalette.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    model.toggleFavorite(place)
                } label: {
                    Label(place.isFavorite ? "Ta bort favorit" : "Gör till favorit",
                          systemImage: place.isFavorite ? "star.slash" : "star")
                }
                Button(role: .destructive) {
                    model.removePlace(place)
                } label: {
                    Label("Ta bort plats", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(PlacesPalette.muted)
                    .frame(width: 32, height: 38)
                    .contentShape(Rectangle())
            }
        }
        .padding(13)
        .background(PlacesPalette.panel, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(PlacesPalette.line, lineWidth: 1))
    }
}
