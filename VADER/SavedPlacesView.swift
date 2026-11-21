import SwiftUI

private enum PlacesPalette {
    static let cyan = Color(red: 0.04, green: 0.78, blue: 0.98)
    static let muted = Color(red: 0.69, green: 0.78, blue: 0.88)
    static let panel = Color(red: 0.015, green: 0.075, blue: 0.13).opacity(0.91)
    static let line = Color(red: 0.18, green: 0.52, blue: 0.72).opacity(0.48)
    static let green = Color(red: 0.25, green: 0.88, blue: 0.62)
}

struct SavedPlacesView: View {
    @ObservedObject var model: WeatherViewModel
    let onAddPlace: () -> Void
    let onSelectPlace: () -> Void

    private var monitoredPlaces: [SavedWeatherPlace] {
        model.savedPlaces.filter { model.isMonitored($0) }
    }

    private var favorite: SavedWeatherPlace? {
        model.savedPlaces.first(where: \.isFavorite)
    }

    private var otherPlaces: [SavedWeatherPlace] {
        model.savedPlaces.filter { !model.isMonitored($0) && !$0.isFavorite }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 5) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 38, weight: .medium))
                            .foregroundStyle(PlacesPalette.cyan)
                        Text("Platser")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Dina sparade väderplatser")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(PlacesPalette.cyan)
                        Text("Välj vilka orter du vill bevaka. Bevakade platser visas överst.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(PlacesPalette.muted)
                            .fixedSize(horizontal: false, vertical: true)
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
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white)
                            Text("Använd GPS för lokalt väder")
                                .font(.system(size: 14))
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

                if !monitoredPlaces.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeading("BEVAKADE ORTER", subtitle: "NOTISER AKTIVA", color: PlacesPalette.green)
                        ForEach(monitoredPlaces) { place in
                            placeRow(place, monitoredHighlight: true)
                        }
                    }
                }

                if let favorite, !model.isMonitored(favorite) {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeading("FAVORIT")
                        placeRow(favorite, prominent: true)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionHeading("SPARADE PLATSER")
                    if otherPlaces.isEmpty && monitoredPlaces.isEmpty && favorite == nil {
                        VStack(spacing: 10) {
                            Image(systemName: "star.circle")
                                .font(.system(size: 38))
                                .foregroundStyle(PlacesPalette.cyan.opacity(0.8))
                            Text("Inga sparade platser ännu")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                            Text("Sök efter en ort och välj den. Då sparas den här så att du enkelt kan återvända.")
                                .font(.system(size: 15))
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
                    } else if otherPlaces.isEmpty {
                        Text("Alla övriga sparade platser visas här när du lägger till fler.")
                            .font(.system(size: 14))
                            .foregroundStyle(PlacesPalette.muted)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(otherPlaces) { place in
                            placeRow(place)
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 42)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.visible)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sectionHeading(_ title: String, subtitle: String? = nil, color: Color = PlacesPalette.muted) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(color)
            Spacer()
            if let subtitle {
                Label(subtitle, systemImage: "bell.badge.fill")
                    .font(.system(size: 10, weight: .black))
                    .tracking(0.5)
                    .foregroundStyle(color)
            }
        }
        .padding(.top, 2)
    }

    private func placeRow(_ place: SavedWeatherPlace, prominent: Bool = false, monitoredHighlight: Bool = false) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    model.selectSavedPlace(place)
                    onSelectPlace()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: monitoredHighlight ? "bell.badge.fill" : (prominent ? "star.fill" : "mappin"))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(monitoredHighlight ? PlacesPalette.green : PlacesPalette.cyan)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(place.name)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white)
                            if monitoredHighlight {
                                Text("BEVAKAS • NOTISER PÅ")
                                    .font(.system(size: 10, weight: .black))
                                    .tracking(0.6)
                                    .foregroundStyle(PlacesPalette.green)
                            } else if prominent {
                                Text("Din favoritplats")
                                    .font(.system(size: 13))
                                    .foregroundStyle(PlacesPalette.muted)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(PlacesPalette.muted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)

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
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(PlacesPalette.muted)
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
            }

            Button {
                model.setMonitoring(place, enabled: !model.isMonitored(place))
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: model.isMonitored(place) ? "bell.badge.fill" : "bell.slash")
                        .font(.system(size: 15, weight: .semibold))
                    Text(model.isMonitored(place) ? "Bevakas" : "Bevaka den här platsen")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    Text(model.isMonitored(place) ? "PÅ" : "AV")
                        .font(.system(size: 11, weight: .black))
                        .tracking(0.7)
                }
                .foregroundStyle(model.isMonitored(place) ? PlacesPalette.green : PlacesPalette.muted)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background((model.isMonitored(place) ? PlacesPalette.green : PlacesPalette.cyan).opacity(model.isMonitored(place) ? 0.12 : 0.055), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(model.isMonitored(place) ? PlacesPalette.green.opacity(0.55) : PlacesPalette.line, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isMonitored(place) ? "Stäng av bevakning för \(place.name)" : "Börja bevaka \\(place.name)")
        }
        .padding(13)
        .background(PlacesPalette.panel, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(monitoredHighlight ? PlacesPalette.green.opacity(0.72) : PlacesPalette.line, lineWidth: monitoredHighlight ? 1.5 : 1))
    }
}
