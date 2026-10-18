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
         mapPreference: MapStylePreference = MapStylePreference()) {
        self.store = store
        self.state = store.load()
        self.location = location
        self.pack = pack
        self.search = search
        self.weather = weather
        self.mapPreference = mapPreference
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

    func choose(_ place: Place) { state.addRecent(place) }

    /// The map style for the current ride type (remembered per type).
    var mapStyle: MapStyleSheet.Style {
        get { _ = styleTick; return mapPreference.style(for: state.rideType) }
        set { mapPreference.set(newValue, for: state.rideType); styleTick += 1 }
    }
}
