import SwiftUI

/// The app: first launch (S0) until done, then the tabs (Ride · Routes · You).
struct RootView: View {
    @State private var app: AppModel
    @State private var tab: TabBar.Tab = .ride
    @Environment(\.colorScheme) private var scheme
    @State private var sheet: RideSheet?
    /// S0e–g: the download sheet over the live map, right after onboarding.
    @State private var showDownload = false
    private let following: Bool

    init(app: AppModel, sheet: RideSheet? = nil, showDownload: Bool = false, following: Bool = true) {
        _app = State(initialValue: app)
        self.following = following
        _sheet = State(initialValue: sheet)
        _showDownload = State(initialValue: showDownload)
    }

    var body: some View {
        Group {
            if app.state.onboarded {
                main
            } else {
                OnboardingView(app: app) {
                    app.state.onboarded = true
                    if !app.pack.isReady { app.pack.install(); showDownload = true }
                }
            }
        }
        .environment(\.mapAppearance, app.state.mapAppearance)
        .onChange(of: app.state.packAutoUpdate) { _, on in app.pack.autoUpdate = on }
        .task {
            app.pack.autoUpdate = app.state.packAutoUpdate
            await app.pack.refreshCatalog()       // the regions on offer (browsing or searching outside offers them)
            // First pack: the rider's region when Velix offers it, else Lombardy.
            if !app.pack.isReady, let here = app.location.coordinate, let r = app.pack.catalog.region(containing: here) {
                RegionPack.active = r.id
            }
            if app.state.onboarded, !app.pack.isReady { app.pack.install() }
            app.history.importLogs()
            #if DEBUG
            if let region = Self.launchRegion { await Self.install(region, pack: app.pack) }
            if let dry = Self.purgeSimulated {
                let (records, files) = app.history.removeSimulated(dryRun: dry)
                NSLog("[purge] %@ %d simulated rides from the history, %d files to rides-simulated/: %@",
                      dry ? "would remove" : "removed", records.count, files.count, records.joined(separator: ", "))
            }
            if let place = Self.launchDestination { app.choose(place) }
            #endif
            await app.refreshWarning()
        }
    }

    private var main: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .ride: RideView(app: app, sheet: $sheet, bottomCovered: showDownload, following: following)
                case .routes: RoutesView(app: app, model: app.routesModel(), sheet: $sheet).id(app.state.rideType)
                case .you: YouView(app: app)
                }
            }
            // The tab bar sits on the screen bottom (its own padding covers the home indicator); content stops above it.
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 44) }
            if !showDownload {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    TabBar(selected: tab) { tab = $0 }
                }
                .ignoresSafeArea(edges: .bottom)
            }
            if let sheet { RideSheetHost(app: app, sheet: $sheet, kind: sheet, openYou: { self.sheet = nil; tab = .you }) }
            if showDownload { DownloadSheet(pack: app.pack) { showDownload = false } }
            if let route = app.follow {
                RouteOptionsView(app: app, model: RouteOptionsModel(follow: route),
                                 onClose: { app.follow = nil },
                                 onStart: { _, _, _ in },
                                 onStartFollow: { option, place, vias in app.follow = nil; app.start(option, to: place, follow: vias) },
                                 onEditRules: { app.follow = nil; tab = .you })
                    .id("follow-\(route.id)" + app.state.rideType.rawValue)
                    .transition(.move(edge: .bottom))
            }
            if let place = app.preview {
                DestinationPreviewView(app: app, place: place,
                                       onClose: { app.preview = nil },
                                       onFindRoute: { app.choose(place) })
                    .id("preview-\(place.id)")
                    .transition(.move(edge: .bottom))
            }
            if let place = app.destination {
                RouteOptionsView(app: app, model: RouteOptionsModel(destination: place),
                                 onClose: { app.destination = nil },
                                 onStart: { app.start($0, choice: $1, avoided: $2, to: place) },
                                 onStartTransit: { app.startTransit($0, to: place) },
                                 onEditRules: { app.destination = nil; app.preview = nil; tab = .you })
                    .id(place.id + app.state.rideType.rawValue)
                    .transition(.move(edge: .bottom))
            }
        }
        // The ride, then its summary in the same cover (S4 → S6 without a flash of the Ride map).
        .fullScreenCover(isPresented: Binding(get: { app.ride != nil || app.summary != nil },
                                              set: { if !$0 { if let t = app.transit { t.end() } else { app.ride?.end() }; app.summary = nil } })) {
            if let ride = app.ride {
                RidingView(session: ride, app: app, transit: app.transit)
            } else if let summary = app.summary {
                RideSummaryView(model: summary, mapStyle: MapStyleKind(app.mapStyle), onDone: { app.summary = nil })
            }
        }
    }
}

/// Temporary tab content until its milestone.
struct PlaceholderTab: View {
    let title: String
    let message: String
    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat.velix.s) {
            Text(title).velixType(.display).foregroundStyle(Color.velix.ink)
            Text(message).velixType(.body).foregroundStyle(Color.velix.ink2)
            Spacer()
        }
        .padding(CGFloat.velix.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.velix.canvas)
    }
}

/// Screens draw a live map, except in snapshot tests (MapLibre isn't deterministic there).
private struct MapBackdropKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var liveMap: Bool {
        get { self[MapBackdropKey.self] }
        set { self[MapBackdropKey.self] = newValue }
    }
}

enum Format {
    /// "0.3 km", "5.4 km", "14 km".
    static func km(_ meters: Double) -> String {
        let km = meters / 1000
        return km < 10 ? String(format: "%.1f km", km) : "\(Int(km.rounded())) km"
    }

    /// "132 of 220 MB"
    static func megabytes(_ received: Int64, of total: Int64) -> String {
        "\(received / 1_000_000) of \(total / 1_000_000) MB"
    }
}

#if DEBUG
extension RootView {
    /// `-ride-to 45.4621,9.1944[,Piazza Santo Stefano]`: open route options for a place at launch (with
    /// `-fake-location` and `-simulate-ride`, a whole ride can be tried away from Lombardy, on the phone or the Simulator).
    static var launchDestination: Place? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-ride-to"), i + 1 < args.count else { return nil }
        let parts = args[i + 1].split(separator: ",", maxSplits: 2).map(String.init)
        guard parts.count >= 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
        return Place(id: "launch-\(parts[0]),\(parts[1])", name: parts.count > 2 ? parts[2] : "Destination",
                     subtitle: "", kind: .address, lat: lat, lon: lon)
    }

    /// `-install-region piemonte`: download a region at launch, as its Download button does, logging progress to the
    /// console (phone tests from the Mac: `devicectl … launch --console`). `-ride-to` waits for it.
    static var launchRegion: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-install-region"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// `-purge-simulated-rides [dry]`: simulated rides out of the history (`dry`: only say which). Nil without the flag.
    static var purgeSimulated: Bool? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-purge-simulated-rides") else { return nil }
        return i + 1 < args.count && args[i + 1] == "dry"
    }

    static func install(_ region: String, pack: PackService) async {
        if case .ready = pack.state(of: region) { NSLog("[pack] %@ already installed", region); return }
        if pack.catalog.region(region) == nil { NSLog("[pack] %@ not in the catalog", region); return }
        pack.install(region)
        var logged = -1, started = false
        while true {
            switch pack.state(of: region) {
            case let .ready(m): NSLog("[pack] %@ %@ installed", region, m.version); return
            case let .failed(r, t): NSLog("[pack] %@ failed at %@", region, Format.megabytes(r, of: t)); return
            case .none where started: NSLog("[pack] %@ download stopped", region); return
            case .none: break       // install() starts in a task
            case .checking: started = true
            case let .downloading(r, t) where t > 0 && Int(r * 10 / t) != logged:
                started = true
                logged = Int(r * 10 / t)
                NSLog("[pack] %@ downloading %@", region, Format.megabytes(r, of: t))
            default: break
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
#endif
