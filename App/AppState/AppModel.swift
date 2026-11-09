import Foundation
import Observation
import SwiftUI

/// App-wide state: what's remembered (``AppState``), location, the pack and the routing engine.
@MainActor
@Observable
final class AppModel {
    var state: AppState { didSet { if state != oldValue { store.save(state) } } }
    let location: LocationService
    let pack: PackService
    let engine = EngineHost()
    let search: PlaceSearch
    /// Past rides (M9).
    let history: RideHistory

    /// Session only: "Lit streets only" for the next ride (S8 Tonight), off when a ride ends.
    var litStreetsOnly = false
    /// MapStyleSheet overlays (session).
    var bikeLanes = false
    var transitLines = false
    /// Map sheet → Satellite (session): kept across ride types, back to the type's own style on the next launch
    /// (Filippo, 7 Nov).
    var satellite = false

    private let store: AppStore

    init(store: AppStore = .live, location: LocationService = LocationService(), pack: PackService = PackService(),
         search: PlaceSearch = PhotonSearch(),
         history: RideHistory? = nil) {
        self.store = store
        self.state = store.load()
        self.location = location
        self.pack = pack
        self.search = search
        self.history = history ?? RideHistory()
        pack.onInstalled = { [weak self] _ in self?.engine.reset() }
    }

    var rules: RuleSet { state.ruleSet(for: state.rideType, litStreetsOnly: litStreetsOnly) }

    /// Outside every installed region (S1e).
    var isOutsideRegion: Bool {
        guard let here = location.coordinate else { return false }
        return !packContains(here)
    }

    /// Search first (Filippo, 2 Nov): a searched place framed on the map before its route options (Find route).
    var preview: Place?
    /// S3: the destination whose route options are open.
    var destination: Place?
    /// The ride in progress (Start).
    var ride: RideSession? {
        // One GPS at a time (M10): the ride's own provider while riding; the app's location follows its fixes.
        didSet {
            guard ride !== oldValue else { return }
            ride?.onLocation = { [weak self] in self?.location.feed($0) }
            location.paused = ride != nil
        }
    }
    /// S6, after a ride that ended by itself at the door (not after End).
    var summary: RideSummaryModel?
    /// The bike + transit stages of the ride in progress (P6), if it is one.
    var transit: TransitRide?
    /// S7c → S7d: Ride this route opens route options for this cycle route.
    var follow: CycleRoute?

    /// The cycle routes around a point (Routes tab): of the installed region holding it, which becomes the active one
    /// (not during a ride: the ride's region stays).
    func routeStore(at p: LatLon) -> RouteStore? {
        if ride == nil, let r = pack.installedRegion(containing: p), r.pack != RegionPack.active { RegionPack.active = r.pack }
        return routeStore
    }

    /// The active region's cycle routes, opened once per installed pack.
    var routeStore: RouteStore? {
        guard let url = RegionPack.routes else { return nil }
        if let cached = routeStoreCache, cached.url == url { return cached.store }
        let store = try? RouteStore(path: url)
        routeStoreCache = store.map { (url, $0) }
        return store
    }
    @ObservationIgnored private var routeStoreCache: (url: URL, store: RouteStore)?

    /// The Routes tab keeps its area, filter and focus across tab switches, per ride type.
    @ObservationIgnored private var routesModels: [RideType: RoutesModel] = [:]

    func routesModel() -> RoutesModel {
        if let m = routesModels[state.rideType] { return m }
        let here = location.coordinate.flatMap { packContains($0) ? $0 : nil }
        let m = RoutesModel(rideType: state.rideType, home: .init(center: here ?? RideView.milan, name: here == nil ? "Milan" : "you"))
        routesModels[state.rideType] = m
        return m
    }

    /// Some installed pack can route here (its region, or the 10 km past its border).
    func packContains(_ p: LatLon) -> Bool {
        pack.installed.isEmpty ? RegionPackManifest.sideloaded.contains(p) : pack.covers(p)
    }

    /// Open route options for a place (Home, Work, Find route): tap 1 of the commute.
    func choose(_ place: Place) {
        state.addRecent(place)
        destination = place
    }

    /// Frame a searched or recent place first; Home and Work open route options straight away (the commute). A place
    /// tapped on the map joins the recents only when routed to (`remember: false`).
    func show(_ place: Place, remember: Bool = true) {
        if place == state.home || place == state.work { return choose(place) }
        if remember { state.addRecent(place) }
        preview = place
    }

    /// A tapped place's street and area, when online ("Café" → "Café · Via Tortona 12, Milano").
    func describe(_ place: Place) async {
        guard let found = try? await search.reverse(place.location), preview?.id == place.id else { return }
        let area = found.subtitle.isEmpty ? found.name : found.name == place.name ? found.subtitle : "\(found.name), \(found.subtitle)"
        guard !area.isEmpty else { return }
        var p = place
        p.subtitle = place.subtitle.isEmpty ? area : "\(place.subtitle) · \(area)"
        preview = p
    }

    /// Tap 2: ride the chosen route.
    func start(_ option: RouteOption, choice: RideChoice = .best, avoided: [AvoidedRoad] = [], to place: Place,
               follow vias: [LatLon]? = nil) {
        let rules = state.ruleSet(for: state.rideType, litStreetsOnly: litStreetsOnly)
        let session = RideSession(destination: place, option: option, avoided: avoided, rules: rules, choice: choice,
                                  planner: engine.loadedPlanner, follow: vias)
        session.onEnd = { [weak self] session in
            self?.ended(session, transit: nil)
            self?.ride = nil
            self?.litStreetsOnly = false     // "For the next ride only" (S8)
        }
        do {
            try session.start()
            // The ride covers route options at once: a sliding cover showed the Ride map under it (Filippo, 7 Nov).
            Self.withoutAnimation { ride = session; destination = nil; preview = nil }
        } catch {
            print("Start failed: \(error)")
        }
    }

    /// Start bike + transit (S3e → P6 S5): ride to the station, the train, ride on, as one ride.
    func startTransit(_ plan: TransitPlan, to place: Place) {
        let rules = state.ruleSet(for: state.rideType, litStreetsOnly: litStreetsOnly)
        let trip = TransitRide(plan: plan, destination: place, rules: rules, planner: engine.loadedTransitPlanner)
        trip.session.onEnd = { [weak self, weak trip] session in
            self?.ended(session, transit: trip?.plan.departure.name)
            self?.ride = nil
            self?.transit = nil
            self?.litStreetsOnly = false
        }
        do {
            try trip.start()
            Self.withoutAnimation { transit = trip; ride = trip.session; destination = nil; preview = nil }
        } catch {
            print("Start failed: \(error)")
        }
    }

    private static func withoutAnimation(_ change: () -> Void) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t, change)
    }

    /// Every ride of 200 m or more goes into the history; S6 opens only when it ended at the door.
    private func ended(_ session: RideSession, transit: String?) {
        // Simulated rides (debug) stay out of the history (M7: only real rides count).
        let record = RideSession.isSimulated ? nil : RideHistory.record(session, transit: transit)
        if let record { history.add(record) }
        if session.arrived { summary = RideSummaryModel(session) }
    }

    /// The map style: Satellite if picked this session, else the ride type's own (Standard or Outdoor).
    var mapStyle: MapStyleSheet.Style {
        get { satellite ? .satellite : MapStyleSheet.styles(for: state.rideType)[0] }
        set { satellite = newValue == .satellite }
    }
}
