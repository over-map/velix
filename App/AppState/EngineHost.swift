import Foundation

/// One Valhalla engine + hazard store per session (mmapping the tiles is expensive), rebuilt after a pack install.
@MainActor
final class EngineHost {
    private var engine: ValhallaOnDeviceProvider?
    private var hazards: HazardStore?
    private var loading: Task<RoutePlanner, Error>?

    enum Failure: Error { case noPack }

    /// The planner, creating the engine on first use.
    func planner() async throws -> RoutePlanner {
        if let engine, let hazards { return RoutePlanner(engine: engine, hazards: hazards) }
        if let loading { return try await loading.value }
        guard let tiles = RegionPack.tileExtract, let hz = RegionPack.hazardStore else { throw Failure.noPack }
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

    /// The engine Ferrostar navigates with (M6b Start).
    var navigationEngine: ValhallaOnDeviceProvider? { engine }

    /// Drop the engine (after installing a new pack).
    func reset() {
        engine = nil
        hazards = nil
        loading?.cancel()
        loading = nil
    }
}
