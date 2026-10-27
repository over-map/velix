@preconcurrency import FerrostarCore
@preconcurrency import FerrostarCoreFFI
import Foundation

/// Which card the rider started from: reroutes keep it (P5 S4g "Rerouting keeps the ride type's rules").
enum RideChoice: String, Sendable { case best, fastest }

/// Ferrostar's route provider for reroutes (M7): the app's planner, with the ride's rules and choice, instead of a
/// bare Valhalla request. A route that can't meet the rules still comes back (the closest), so the rider is never
/// left without one; a failed plan throws and Ferrostar keeps the current route.
final class PlannedRouteProvider: CustomRouteProvider, @unchecked Sendable {
    typealias Plan = @Sendable (LatLon, LatLon, Double?) async throws -> RoutePlan

    private let plan: Plan
    private var _choice: RideChoice
    /// Best or Fastest; a bike + transit ride switches it when late (M8c).
    var choice: RideChoice {
        get { lock.withLock { _choice } }
        set { lock.withLock { _choice = newValue } }
    }
    private let lock = NSLock()
    private var _lastOption: RouteOption?
    private var _lastAvoided: [AvoidedRoad] = []
    /// The option behind the last route returned (its analysis drives hazards and the map).
    var lastOption: RouteOption? { lock.withLock { _lastOption } }
    /// The roads the last Best route leaves out (S4f tags; none on a Fastest ride).
    var lastAvoided: [AvoidedRoad] { lock.withLock { _lastAvoided } }
    /// Called when a reroute fails: Ferrostar swallows the error and keeps the current route.
    var onFailure: @Sendable () -> Void = {}

    enum Failure: Error { case noDestination, noRoute }

    init(choice: RideChoice, plan: @escaping Plan) {
        _choice = choice
        self.plan = plan
    }

    convenience init(planner: RoutePlanner, rules: RuleSet, choice: RideChoice) {
        self.init(choice: choice) { from, to, heading in
            try await planner.plan(from: from, to: to, heading: heading, rules: rules)
        }
    }

    func getRoutes(userLocation: UserLocation, waypoints: [Waypoint]) async throws -> [Route] {
        do {
            guard let to = waypoints.last?.coordinate else { throw Failure.noDestination }
            let from = LatLon(lat: userLocation.coordinates.lat, lon: userLocation.coordinates.lng)
            let heading = userLocation.courseOverGround.map { Double($0.degrees) }
            let planned = try await plan(from, LatLon(lat: to.lat, lon: to.lng), heading)
            let choice = self.choice
            guard let option = Self.pick(planned, choice: choice) else { throw Failure.noRoute }
            let route = try RideSession.route(from: option)
            let avoided = if case let .options(o) = planned, choice == .best { o.avoided } else { [AvoidedRoad]() }
            lock.withLock { _lastOption = option; _lastAvoided = avoided }
            return [route]
        } catch {
            onFailure()
            throw error
        }
    }

    static func pick(_ plan: RoutePlan, choice: RideChoice) -> RouteOption? {
        switch plan {
        case let .options(o): choice == .fastest ? (o.fastest ?? o.best) : o.best
        case let .noRouteMeetsRules(_, _, closest, _): closest
        case .noRoute: nil
        }
    }
}

/// Ferrostar's delegate during a ride: the app's ``ReroutePolicy`` decides when to reroute, and new routes are
/// taken on the main actor (Ferrostar calls `loadedAlternateRoutes` from a background task).
final class RideCoordinator: FerrostarCoreDelegate, @unchecked Sendable {   // only touched on the main actor
    weak var session: RideSession?

    func core(_ core: FerrostarCore, didStartWith route: Route) {}

    func core(_ core: FerrostarCore, correctiveActionForDeviation deviation: DeviationKind,
              remainingWaypoints waypoints: [Waypoint]) -> CorrectiveAction {
        // A shortcut onto a later step of the same route is not a reason to reroute.
        guard case .completelyOffRoute = deviation else { return .doNothing }
        let go = MainActor.assumeIsolated { session?.rerouteRequested() ?? false }
        return go ? .getNewRoutes(waypoints: waypoints) : .doNothing
    }

    func core(_ core: FerrostarCore, loadedAlternateRoutes routes: [Route]) {
        Task { @MainActor in self.session?.rerouted(routes) }
    }
}
