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
    @Environment(\.liveMap) private var liveMap
    @State private var following: Bool
    @State private var camera = MapCamera(center: RideView.milan, zoom: 15)
    @State private var search: SearchPurpose?

    static let milan = LatLon(lat: 45.4746, lon: 9.2050)   // Porta Venezia, until the first fix

    init(app: AppModel, sheet: Binding<RideSheet?>, bottomCovered: Bool = false, following: Bool = true) {
        self.app = app
        _sheet = sheet
        self.bottomCovered = bottomCovered
        _following = State(initialValue: following)
    }

    var body: some View {
        ZStack {
            map.ignoresSafeArea()
            VStack(spacing: CGFloat.velix.s) {
                if !bottomCovered { SearchBar(homeSet: app.state.home != nil, workSet: app.state.work != nil,
                          onHome: { home() }, onWork: { work() }, onTap: { search = .destination })
                notices }
                Spacer()
                if !bottomCovered { downloadCard; controls }
            }
            .padding(.horizontal, CGFloat.velix.m)
            .padding(.top, CGFloat.velix.xs)
            .padding(.bottom, CGFloat.velix.m)
        }
        .fullScreenCover(item: $search) { purpose in
            SearchView(app: app, purpose: purpose) { place in
                search = nil
                guard let place else { return }
                switch purpose {
                case .setHome: app.state.home = place
                case .setWork: app.state.work = place
                case .destination: app.choose(place)
                case .area: break
                }
            }
        }
        .onChange(of: app.location.coordinate) { _, here in
            if following, let here { camera = MapCamera(center: here, zoom: camera.zoom) }
        }
    }

    // MARK: Map

    @ViewBuilder private var map: some View {
        if liveMap {
            VelixMap(style: MapStyleKind(app.mapStyle), mode: scheme == .dark ? .night : .day,
                     bikeLanes: app.bikeLanes, transitLines: app.transitLines, camera: camera,
                     userLocation: app.isOutsideRegion ? nil : app.location.coordinate, userHeading: app.location.heading,
                     onUserPan: { following = false })
        } else {
            Color.velix.surface2
        }
    }

    // MARK: Notices (S1a, S1b, S1e, S1f)

    @ViewBuilder private var notices: some View {
        if app.isOutsideRegion {
            NoticeBanner(title: "You’re outside \(app.pack.regionName)",
                         message: "Velix has routes for \(app.pack.regionName) for now. You can still search and look at the map.",
                         icon: VelixIconView(.mapPinOff, size: 22), tone: .info)
        } else if app.location.access == .denied || app.location.cannotFind {
            NoticeBanner(title: "Can’t find your location", message: "Turn on Location in Settings, or search from any place.",
                         icon: VelixIconView(.locateOff, size: 22), tone: .info,
                         link: ("Open Settings", {
                             if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                         }))
        }
        if let w = app.warning {
            if app.warningDismissed {
                NoticePill(text: w.pill).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                NoticeBanner.weather(w.title, w.message) { app.warningDismissed = true }
            }
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
                        if let here = app.location.coordinate { camera = MapCamera(center: here, zoom: max(camera.zoom, 15)) }
                    }
                    .disabled(app.location.coordinate == nil)
                    .opacity(app.location.coordinate == nil ? 0.5 : 1)
                }
                MapButton(active: sheet == .mapStyle) { sheet = .mapStyle }
            }
        }
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
                                  transitLines: $app.transitLines, onClose: { sheet = nil })
                }
            }
            // The sheet's surface continues under the home indicator.
            .background(alignment: .bottom) { Color.velix.surface.frame(height: 60).offset(y: 50) }
        }
        .transition(.opacity)
    }
}
