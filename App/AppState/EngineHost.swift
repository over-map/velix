import Foundation

/// One Valhalla engine + hazard store per session (mmapping the tiles is expensive), for the active region; rebuilt
/// after a pack install, or when a trip needs another region (``planner(covering:)``).
@MainActor
final class EngineHost {
    /// The region the engine and stores below were opened for.
    private(set) var region: String?
    private var engine: ValhallaOnDeviceProvider?
    private var hazards: HazardStore?
    private var loading: Task<RoutePlanner, Error>?
    private var transit: TransitStore?
    private var city: CityArea?

    enum Failure: Error {
        case noPack
        /// No installed region's routing data covers both ends (a trip across regions, beyond the border buffer).
        case acrossRegions
    }

    /// The planner of the installed region covering every point (a trip's two ends), opening it if needed. Valhalla
    /// doesn't fail for a point outside its tiles, it snaps to their edge: never plan with a pack that doesn't cover.
    func planner(covering points: [LatLon]) async throws -> RoutePlanner {
        if RegionPack.preferSideloaded || RegionPack.installed().isEmpty { return try await planner() }
        guard let r = RegionPack.region(covering: points) else { throw Failure.acrossRegions }
        if r != RegionPack.active || region != r {
            reset()
            RegionPack.active = r
        }
        return try await planner()
    }

    /// The planner, creating the engine on first use.
    func planner() async throws -> RoutePlanner {
        if let engine, let hazards { return RoutePlanner(engine: engine, hazards: hazards) }
        if let loading { return try await loading.value }
        guard let tiles = RegionPack.tileExtract, let hz = RegionPack.hazardStore else { throw Failure.noPack }
        region = RegionPack.active
        let task = Task { () throws -> RoutePlanner in
            let profile = try RideProfile.load(.city).best
            let e = try await Task.detached(priority: .userInitiated) {
                try ValhallaOnDeviceProvider(tileExtract: tiles, profile: profile)
            }.value
            let h = try HazardStore(path: hz)
            self.engine = e
            self.hazards = h
            return RoutePlanner(engine: e, hazards: h)
        }
        loading = task
        defer { loading = nil }
        return try await task.value
    }

    /// The planner, once loaded (a ride starts from planned options, so it is): reroutes plan with it (M7).
    var loadedPlanner: RoutePlanner? {
        guard let engine, let hazards else { return nil }
        return RoutePlanner(engine: engine, hazards: hazards)
    }

    /// Bike + transit (M8): the timetable and the bike planner, or nil when the pack has no timetable.
    func transitPlanner() async throws -> TransitPlanner? {
        let planner = try await planner()
        if transit == nil, let url = RegionPack.transit {
            transit = try await Task.detached(priority: .userInitiated) { try TransitStore(path: url) }.value
        }
        return transit.map { TransitPlanner(store: $0, planner: planner) }
    }

    /// The transit planner, once loaded (a bike + transit ride starts from a planned suggestion, so it is).
    var loadedTransitPlanner: TransitPlanner? {
        guard let planner = loadedPlanner, let transit else { return nil }
        return TransitPlanner(store: transit, planner: planner)
    }

    /// The city area (destination outside it: suggest transit), or nil when the pack has none.
    var cityArea: CityArea? {
        if city == nil, let url = RegionPack.city, let data = try? Data(contentsOf: url) { city = try? CityArea(geoJSON: data) }
        return city
    }

    /// Drop the engine (after installing a new pack).
    func reset() {
        region = nil
        engine = nil
        hazards = nil
        transit = nil
        city = nil
        loading?.cancel()
        loading = nil
    }
}
