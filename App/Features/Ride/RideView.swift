import SwiftUI
import UIKit

/// Sheets on the Ride map (P4 S1g–i).
enum RideSheet: Equatable { case rideType, mapStyle }

/// S1 Ride (P4 §01): the map, Where to? with Home and Work, notices, the ride-type chip, Map and Recenter.
struct RideView: View {
    @Bindable var app: AppModel
    @Binding var sheet: RideSheet?
    /// The download sheet covers the bottom controls (S0e).
    var bottomCovered = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.mapAppearance) private var mapAppearance
    @Environment(\.liveMap) private var liveMap
    @State private var following: Bool
    @State private var camera = MapCamera(center: RideView.milan, zoom: 15)
    @State private var search: SearchPurpose?
    /// The tab bar (and the home indicator) under the map: the ⓘ sits above it.
    @State private var tabBar: CGFloat = 0
    /// Where the rider moved the map: a region there that isn't on the phone is offered (Filippo, 2 Nov).
    @State private var browsed: LatLon?
    /// Its zoom: a region is offered from city scale (Filippo, 5 Nov: "if I browse there at high LOD").
    @State private var browsedZoom: Double = 15
    static let offerZoom = 10.0
    /// Regions whose offer the rider closed (this session).
    @State private var declined: Set<String> = []
    /// The rider closed "No routes here yet" (this session).
    @State private var uncoveredDismissed = false

    static let milan = LatLon(lat: 45.4746, lon: 9.2050)   // Porta Venezia, until the first fix

    init(app: AppModel, sheet: Binding<RideSheet?>, bottomCovered: Bool = false, following: Bool = true) {
        self.app = app
        _sheet = sheet
        self.bottomCovered = bottomCovered
        _following = State(initialValue: following)
        // The tab is rebuilt on every switch: start on the rider, not Porta Venezia (Filippo, 7 Nov).
        _camera = State(initialValue: MapCamera(center: app.location.coordinate ?? RideView.milan, zoom: 15))
    }

    var body: some View {
        ZStack {
            map.ignoresSafeArea()
            VStack(spacing: CGFloat.velix.s) {
                if !bottomCovered { SearchBar(homeSet: app.state.home != nil, workSet: app.state.work != nil,
                          homeLabel: shortcutLabel("Home", app.state.home, named: false),
                          workLabel: shortcutLabel("Work", app.state.work, named: true),
                          onHome: { home() }, onWork: { work() }, onTap: { search = .destination })
                notices }
                Spacer()
                if !bottomCovered { downloadCard; controls }
            }
            .padding(.horizontal, CGFloat.velix.m)
            .padding(.top, CGFloat.velix.xs)
            .padding(.bottom, CGFloat.velix.m)
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { tabBar = $0 }
        .fullScreenCover(item: $search) { purpose in
            SearchView(app: app, purpose: purpose) { place in
                search = nil
                guard let place else { return }
                switch purpose {
                case .setHome: app.state.home = place
                case .setWork: app.state.work = place
                case .destination: app.show(place)
                case .area: break
                }
            }
        }
        .onChange(of: app.location.coordinate, initial: true) { _, here in
            if following, let here { camera = MapCamera(center: here, zoom: camera.zoom, revision: camera.revision) }
        }
    }

    // MARK: Map

    @ViewBuilder private var map: some View {
        if liveMap {
            VelixMap(style: MapStyleKind(app.mapStyle), mode: MapMode(scheme, mapAppearance),
                     bikeLanes: app.bikeLanes, transitLines: app.transitLines, camera: camera,
                     userLocation: app.isOutsideRegion ? nil : app.location.coordinate, userHeading: app.location.heading,
                     coveredBottom: tabBar, onUserPan: { following = false },
                     onTapFeature: { app.show($0, remember: false) }, onRegionChange: { browsed = $0; browsedZoom = $1 })
        } else {
            Color.velix.surface2
        }
    }

    // MARK: Notices (S1a, S1b, S1e, S1f)

    /// A region on offer where the map is (or the rider is) that isn't downloaded yet.
    private var offer: RegionCatalog.Region? {
        guard !app.pack.isDownloading, following || browsedZoom >= Self.offerZoom,
              let p = (following ? nil : browsed) ?? app.location.coordinate,
              let r = app.pack.offer(at: p), !declined.contains(r.id) else { return nil }
        return r
    }

    /// Offline where no downloaded region has the map (Filippo, 5 Nov: the map elsewhere comes online).
    private var offlineHere: Bool {
        guard !app.pack.isOnline, let p = (following ? nil : browsed) ?? app.location.coordinate else { return false }
        return app.pack.installedRegion(containing: p) == nil
    }

    /// Panned at city scale to a place no region on offer covers.
    private var browsedUncovered: Bool {
        guard !following, !uncoveredDismissed, browsedZoom >= Self.offerZoom, let p = browsed,
              !app.pack.catalog.regions.isEmpty else { return false }
        return app.pack.installedRegion(containing: p) == nil && app.pack.catalog.region(containing: p) == nil
    }

    @ViewBuilder private var notices: some View {
        if offlineHere {
            NoticeBanner(title: "You’re offline",
                         message: "The map here needs a connection. Places you’ve seen and your downloaded regions still show.",
                         icon: VelixIconView(.wifiOff, size: 22), tone: .info)
        } else if let r = offer {
            NoticeBanner(title: "\(r.name) isn’t on your phone",
                         message: "Download it (\(r.downloadBytes / 1_000_000) MB) for routes there, even without signal.",
                         icon: VelixIconView(.download, size: 22), tone: .info, onDismiss: { declined.insert(r.id) },
                         link: ("Download \(r.name)", { app.pack.install(r.id) }))
        } else if browsedUncovered {
            NoticeBanner(title: "No routes here yet",
                         message: "Velix covers Lombardy and its neighbours for now. You can still look at the map.",
                         icon: VelixIconView(.mapPinOff, size: 22), tone: .info, onDismiss: { uncoveredDismissed = true })
        } else if app.isOutsideRegion {
            NoticeBanner(title: "You’re outside the downloaded regions",
                         message: "Velix covers Lombardy and its neighbours for now. You can still search and look at the map.",
                         icon: VelixIconView(.mapPinOff, size: 22), tone: .info)
        } else if app.location.access == .denied || app.location.cannotFind {
            NoticeBanner(title: "Can’t find your location", message: "Turn on Location in Settings, or search from any place.",
                         icon: VelixIconView(.locateOff, size: 22), tone: .info,
                         link: ("Open Settings", {
                             if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                         }))
        }
    }

    // MARK: Downloading (S1d)

    @ViewBuilder private var downloadCard: some View {
        switch app.pack.state {
        case let .downloading(r, t), let .failed(r, t):
            VStack(alignment: .leading, spacing: CGFloat.velix.xs) {
                HStack(spacing: CGFloat.velix.xs) {
                    VelixIconView(.download, size: 20)
                    Text("Downloading \(app.pack.regionName)").velixType(.label)
                    Spacer()
                    Text(Format.megabytes(r, of: t)).velixType(.label).monospacedDigit().foregroundStyle(Color.velix.ink2)
                }
                ProgressBar(fraction: app.pack.fraction)
                Text("Search works now. Routes start when the download is done.").velixType(.footnote).foregroundStyle(Color.velix.ink2)
            }
            .foregroundStyle(Color.velix.ink)
            .padding(CGFloat.velix.s)
            .background(Color.velix.surface, in: RoundedRectangle(cornerRadius: CGFloat.velix.radius.card))
            .velixElevation(VelixElevations.e1)
            .accessibilityElement(children: .combine)
        default:
            EmptyView()
        }
    }

    // MARK: Chip, Map, Recenter

    private var controls: some View {
        HStack(alignment: .bottom) {
            RideTypeChip(rideType: app.state.rideType) { sheet = .rideType }
            Spacer()
            VStack(spacing: CGFloat.velix.s) {
                if !following {
                    RecenterButton(following: false) {
                        following = true
                        browsed = nil
                        if let here = app.location.coordinate { camera = MapCamera(center: here, zoom: max(camera.zoom, 15), revision: camera.revision + 1) }
                    }
                    .disabled(app.location.coordinate == nil)
                    .opacity(app.location.coordinate == nil ? 0.5 : 1)
                }
                MapButton(active: sheet == .mapStyle) { sheet = .mapStyle }
            }
        }
    }

    /// P8: "Home, 0.3 kilometres", "Work, Politecnico, 5.4 kilometres" (the distance from here, when known).
    private func shortcutLabel(_ title: String, _ place: Place?, named: Bool) -> String? {
        guard let place else { return nil }
        var parts = [title]
        if named { parts.append(place.name) }
        if let here = app.location.coordinate { parts.append(Format.spoken(Format.km(Geo.distance(here, place.location)))) }
        return parts.joined(separator: ", ")
    }

    private func home() {
        if let home = app.state.home { app.choose(home) } else { search = .setHome }
    }

    private func work() {
        if let work = app.state.work { app.choose(work) } else { search = .setWork }
    }
}

/// Ride-map sheets over a scrim (P4 S1g–i).
struct RideSheetHost: View {
    @Bindable var app: AppModel
    @Binding var sheet: RideSheet?
    let kind: RideSheet
    var openYou: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.25).ignoresSafeArea().onTapGesture { sheet = nil }
                .accessibilityAddTraits(.isButton).accessibilityLabel("Close")
            Group {
                switch kind {
                case .rideType:
                    RideTypePicker(selected: $app.state.rideType, onClose: { sheet = nil }, onEditRules: openYou)
                case .mapStyle:
                    MapStyleSheet(rideType: app.state.rideType, style: $app.mapStyle, bikeLanes: $app.bikeLanes,
                                  transitLines: $app.transitLines, appearance: $app.state.mapAppearance, onClose: { sheet = nil })
                }
            }
            // The sheet's surface continues under the home indicator.
            .background(alignment: .bottom) { Color.velix.surface.frame(height: 60).offset(y: 50) }
        }
        .transition(.opacity)
    }
}
