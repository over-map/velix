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
    /// "Download Piedmont?" (Find route for a place in a region not on the phone).
    @State private var asking: RegionCatalog.Region?
    /// Find route waits for this region's download, then opens route options.
    @State private var waitingFor: String?

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
                                onFindRoute: findRoute, onClose: onClose)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { cardHeight = VelixMap.covered(fromTop: $0) }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .confirmationDialog(asking.map { "Download \($0.name)?" } ?? "", isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
                            titleVisibility: .visible, presenting: asking) { r in
            Button("Download") {
                waitingFor = r.id
                app.pack.install(r.id)
            }
            Button("Not now", role: .cancel) {}
        } message: { r in
            Text("Routes to \(place.name) need the \(r.name) map (\(r.downloadBytes / 1_000_000) MB).")
        }
        // The region arrived: on to route options.
        .onChange(of: app.pack.installed.map(\.pack)) { _, packs in
            if let w = waitingFor, packs.contains(w) { waitingFor = nil; onFindRoute() }
        }
    }

    private func findRoute() {
        if case .needsDownload = availability, let r = app.pack.offer(at: place.location) { asking = r } else { onFindRoute() }
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
        if app.packContains(place.location) { return .routable }
        guard let r = app.pack.offer(at: place.location) else { return .notCovered }
        if app.pack.downloading == r.id { return .downloading(region: r.name, fraction: app.pack.fraction) }
        return .needsDownload(region: r.name, megabytes: r.downloadBytes / 1_000_000)
    }

    private var distance: String? {
        app.location.coordinate.map { Format.km(Geo.distance($0, place.location)) }
    }
}
