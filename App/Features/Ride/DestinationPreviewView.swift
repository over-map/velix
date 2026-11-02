import SwiftUI

/// Search first (Filippo, 2 Nov): a searched place is framed on the map with its end marker before any route is
/// planned; Find route opens S3 route options. Home and Work skip this (one tap, the commute).
struct DestinationPreviewView: View {
    @Bindable var app: AppModel
    let place: Place
    var onClose: () -> Void
    var onFindRoute: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.mapAppearance) private var mapAppearance
    @Environment(\.liveMap) private var liveMap
    @State private var cardHeight: CGFloat = 220

    /// Close enough to read the streets around the place.
    static let zoom = 16.0

    var body: some View {
        ZStack(alignment: .top) {
            map.ignoresSafeArea()
            HStack {
                Button(action: onClose) {
                    VelixIconView(.chevronLeft, size: 22).foregroundStyle(Color.velix.ink)
                        .frame(width: 44, height: 44)
                        .background(Color.velix.surface, in: Circle())
                        .velixElevation(VelixElevations.e1, in: Circle())
                }
                .buttonStyle(VelixPressStyle())
                .accessibilityLabel("Back")
                Spacer()
            }
            .padding(.horizontal, CGFloat.velix.m)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                DestinationCard(place: place, distance: distance, availability: availability,
                                onFindRoute: onFindRoute, onClose: onClose)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { cardHeight = VelixMap.covered(fromTop: $0) }
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    @ViewBuilder private var map: some View {
        if liveMap {
            VelixMap(style: MapStyleKind(app.mapStyle), mode: MapMode(scheme, mapAppearance),
                     bikeLanes: app.bikeLanes, transitLines: app.transitLines, route: marker,
                     camera: MapCamera(center: place.location, zoom: Self.zoom),
                     userLocation: app.isOutsideRegion ? nil : app.location.coordinate, userHeading: app.location.heading,
                     insets: UIEdgeInsets(top: 100, left: 0, bottom: cardHeight, right: 0))
        } else {
            Color.velix.surface2
        }
    }

    /// Only the end marker, with the place's name.
    private var marker: MapRouteModel {
        var m = MapRouteModel(best: [], endName: place.name)
        m.end = place.location
        return m
    }

    var availability: DestinationCard.Availability {
        app.packContains(place.location) ? .routable : .notCovered(region: app.pack.regionName)
    }

    private var distance: String? {
        app.location.coordinate.map { Format.km(Geo.distance($0, place.location)) }
    }
}
