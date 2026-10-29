import Foundation
import Observation

/// Severe-weather warnings for the S1 notice. The source (MeteoAM / ARPA CAP) is decided in M10; until then none.
protocol WeatherWarnings: Sendable {
    func current(near: LatLon?) async -> WeatherWarning?
}

struct WeatherWarning: Equatable, Sendable {
    var title: String        // "Severe weather in Milan"
    var message: String      // "Thunderstorms until 18:00. Take care if you ride."
    var pill: String         // "Storm until 18:00"
}

struct NoWeatherWarnings: WeatherWarnings {
    func current(near: LatLon?) async -> WeatherWarning? { nil }
}

/// App-wide state: what's remembered (``AppState``), location, the pack and the routing engine.
@MainActor
@Observable
final class AppModel {
    var state: AppState { didSet { if state != oldValue { store.save(state) } } }
    let location: LocationService
    let pack: PackService
    let engine = EngineHost()
    let search: PlaceSearch
    let weather: WeatherWarnings
    let mapPreference: MapStylePreference
    /// Past rides (M9).
    let history: RideHistory
    /// Apple Health (M9b).
    let health: HealthStoring

    /// Session only: "Lit streets only" for the next ride (S8 Tonight), off when a ride ends.
    var litStreetsOnly = false
    var warning: WeatherWarning?
    var warningDismissed = false
    /// MapStyleSheet overlays (session).
    var bikeLanes = false
    var transitLines = false
    /// Mirrors ``MapStylePreference`` so views redraw when it changes.
    private var styleTick = 0

    private let store: AppStore

    init(store: AppStore = .live, location: LocationService = LocationService(), pack: PackService = PackService(),
         search: PlaceSearch = PhotonSearch(), weather: WeatherWarnings = NoWeatherWarnings(),
         mapPreference: MapStylePreference = MapStylePreference(), history: RideHistory? = nil,
         health: HealthStoring = HealthKitStore()) {
        self.store = store
        self.state = store.load()
        self.location = location
        self.pack = pack
        self.search = search
        self.weather = weather
        self.mapPreference = mapPreference
        self.history = history ?? RideHistory()
        self.health = health
        pack.onInstalled = { [weak self] in self?.engine.reset() }
    }

    var rules: RuleSet { state.ruleSet(for: state.rideType, litStreetsOnly: litStreetsOnly) }

    /// Inside the region the pack covers (S1e).
    var isOutsideRegion: Bool {
        guard let here = location.coordinate else { return false }
        if case let .ready(m) = pack.state { return !m.contains(here) }
        return !RegionPackManifest.sideloaded.contains(here)
    }

    func refreshWarning() async {
        warning = await weather.current(near: location.coordinate)
    }

    /// S3: the destination whose route options are open.
    var destination: Place?
    /// The ride in progress (Start).
    var ride: RideSession?
    /// S6, after a ride that ended by itself at the door (not after End).
    var summary: RideSummaryModel?
    /// The bike + transit stages of the ride in progress (P6), if it is one.
    var transit: TransitRide?
    /// S7c → S7d: Ride this route opens route options for this cycle route.
    var follow: CycleRoute?

    /// The pack's cycle routes (Routes tab), opened once per installed pack.
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

    /// Inside the region the pack covers.
    func packContains(_ p: LatLon) -> Bool {
        if case let .ready(m) = pack.state { return m.contains(p) }
        return RegionPackManifest.sideloaded.contains(p)
    }

    /// Open route options for a place (Home, Work, a search result): tap 1 of the commute.
    func choose(_ place: Place) {
        state.addRecent(place)
        destination = place
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
            ride = session
            destination = nil
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
            transit = trip
            ride = trip.session
            destination = nil
        } catch {
            print("Start failed: \(error)")
        }
    }

    /// Every ride of 200 m or more goes into the history; S6 opens only when it ended at the door.
    private func ended(_ session: RideSession, transit: String?) {
        let record = RideHistory.record(session, transit: transit)
        if let record {
            history.add(record)
            if state.healthOn { Task { await HealthSync.save(record, to: health, history: history) } }
        }
        if session.arrived { summary = RideSummaryModel(session) }
    }

    /// S6b Connect: connect if needed, then save that ride (the latest when nil).
    func saveToHealth(_ record: RideRecord? = nil) async {
        var on = state.healthOn
        if !on { on = await connectHealth() }
        guard on, let r = record ?? history.rides.first else { return }
        await HealthSync.save(r, to: health, history: history)
    }

    /// You / S6b → Connect Apple Health: asks once (the system sheet); on when workouts may be written.
    func connectHealth() async -> Bool {
        guard health.available else { return false }
        let ok = (try? await health.authorize()) ?? false
        state.healthOn = ok
        return ok
    }

    /// The map style for the current ride type (remembered per type).
    var mapStyle: MapStyleSheet.Style {
        get { _ = styleTick; return mapPreference.style(for: state.rideType) }
        set { mapPreference.set(newValue, for: state.rideType); styleTick += 1 }
    }
}
