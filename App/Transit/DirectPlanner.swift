import Foundation

/// The city area (pack role `city`, the Comune di Milano boundary): "destination outside the city" suggests bike +
/// transit (BRIEF §8).
struct CityArea: Sendable {
    /// Outer rings only (the comune has no holes worth keeping), lon/lat.
    let rings: [[LatLon]]

    init(rings: [[LatLon]]) { self.rings = rings }

    /// GeoJSON Polygon / MultiPolygon, or a FeatureCollection of them.
    init(geoJSON data: Data) throws {
        let json = try JSONSerialization.jsonObject(with: data)
        var rings: [[LatLon]] = []
        func ring(_ any: Any) -> [LatLon] {
            ((any as? [[Double]]) ?? []).compactMap { $0.count >= 2 ? LatLon(lat: $0[1], lon: $0[0]) : nil }
        }
        func geometry(_ g: [String: Any]) {
            switch g["type"] as? String {
            case "Polygon": if let c = g["coordinates"] as? [Any], let outer = c.first { rings.append(ring(outer)) }
            case "MultiPolygon": for p in (g["coordinates"] as? [[Any]]) ?? [] { if let outer = p.first { rings.append(ring(outer)) } }
            default: break
            }
        }
        if let o = json as? [String: Any] {
            if let features = o["features"] as? [[String: Any]] {
                for f in features { if let g = f["geometry"] as? [String: Any] { geometry(g) } }
            } else if let g = o["geometry"] as? [String: Any] {
                geometry(g)
            } else {
                geometry(o)
            }
        }
        self.rings = rings.filter { $0.count >= 3 }
    }

    func contains(_ p: LatLon) -> Bool {
        rings.contains { r in
            var inside = false
            var j = r.count - 1
            for i in 0 ..< r.count {
                let a = r[i], b = r[j]
                if (a.lat > p.lat) != (b.lat > p.lat), p.lon < (b.lon - a.lon) * (p.lat - a.lat) / (b.lat - a.lat) + a.lon {
                    inside.toggle()
                }
                j = i
            }
            return inside
        }
    }
}

/// A direct connection before the bike legs are planned: ride in and out are estimates.
struct TransitCandidate: Hashable, Sendable {
    let departure: TransitDeparture
    let rule: BikeRule
    /// Estimated ride to the boarding stop and from the alighting stop.
    let rideIn: TimeInterval
    let rideOut: TimeInterval
    let arrival: Date
}

/// Direct connections only (BUILD_PLAN M8, iteration 1): ride to a station, one train or metro run that takes bikes,
/// ride on. No changes. Static timetable from the pack; no live delays.
enum DirectPlanner {
    /// Stations considered at each end, per operator (metro stops are dense: nearest-overall would leave out every
    /// railway station in central Milan), and how far.
    static let stationRadius = 4000.0
    static let stationsPerEnd = 6
    /// How far ahead departures are searched.
    static let window: TimeInterval = 90 * 60
    /// Bike estimate before the real legs: straight line × detour at city speed (15 km/h).
    static let detour = 1.3
    static let estimateSpeed = 4.2
    /// Time to get the bike into the station and on the platform (train: stairs and lifts; metro: lifts, shorter).
    static func boarding(_ mode: TransitRoute.Mode) -> TimeInterval { mode == .rail ? 3 * 60 : 2 * 60 }
    /// Getting off and out of the station with the bike (P4 TripBar "Out 3").
    static let outOfStation: TimeInterval = 3 * 60
    /// Stops this close to both ends would be a pointless hop.
    static let minimumHop = 1500.0

    static func estimate(_ a: LatLon, _ b: LatLon) -> TimeInterval { Geo.distance(a, b) * detour / estimateSpeed }

    /// Direct connections catchable from `origin` at `now`, earliest arrival at `destination` first.
    static func candidates(_ store: TransitStore, from origin: LatLon, to destination: LatLon, at now: Date) -> [TransitCandidate] {
        let boards = nearby(store, origin), alights = nearby(store, destination)
        let rideIn = Dictionary(uniqueKeysWithValues: boards.map { ($0.stop.id, estimate(origin, $0.stop.location)) })
        let rideOut = Dictionary(uniqueKeysWithValues: alights.map { ($0.stop.id, estimate($0.stop.location, destination)) })
        let earliest = now.addingTimeInterval((rideIn.values.min() ?? 0) + 2 * 60)
        let runs = store.departures(from: boards.map(\.stop.id), to: alights.map(\.stop.id),
                                    after: earliest, before: earliest.addingTimeInterval(window))
        var best: [String: TransitCandidate] = [:]   // per run: its best board/alight pair
        for d in runs {
            guard let tin = rideIn[d.board.id], let tout = rideOut[d.alight.id],
                  Geo.distance(d.board.location, d.alight.location) >= minimumHop,
                  d.departs >= now.addingTimeInterval(tin + boarding(d.route.mode)) else { continue }
            let rule = store.bikeRule(for: d)
            guard rule.offered else { continue }
            let c = TransitCandidate(departure: d, rule: rule, rideIn: tin, rideOut: tout,
                                     arrival: d.arrives.addingTimeInterval(outOfStation + tout))
            if let old = best[d.trip], old.arrival <= c.arrival { continue }
            best[d.trip] = c
        }
        return best.values.sorted { $0.arrival < $1.arrival }
    }

    static func nearby(_ store: TransitStore, _ p: LatLon) -> [(stop: TransitStop, meters: Double)] {
        let all = store.stops(near: p, within: stationRadius, limit: .max)
        return Dictionary(grouping: all, by: \.stop.feed).values.flatMap { $0.prefix(stationsPerEnd) }
    }

    /// The next runs between the same two stops after `d` (the "Next trains" chips).
    static func later(_ store: TransitStore, than d: TransitDeparture, count: Int) -> [TransitDeparture] {
        let runs = store.departures(from: [d.board.id], to: [d.alight.id], after: d.departs.addingTimeInterval(1),
                                    before: d.departs.addingTimeInterval(window))
        var seen = Set<String>()
        return runs.filter { store.bikeRule(for: $0).offered && seen.insert($0.trip).inserted }.prefix(count).map { $0 }
    }
}

/// Ride in, one run, ride out (S3e TransitCard, S5).
struct TransitPlan: Sendable {
    let rideIn: RouteOption
    let departure: TransitDeparture
    let rule: BikeRule
    let stops: [TransitStopTime]
    let rideOut: RouteOption
    /// The next runs of the same pair (S3e "Next trains").
    let later: [TransitDeparture]
    /// When the plan was made (the rider leaves now).
    let planned: Date

    var arrival: Date { departure.arrives.addingTimeInterval(DirectPlanner.outOfStation + rideOut.seconds) }
    var seconds: TimeInterval { arrival.timeIntervalSince(planned) }
    var bikeSeconds: TimeInterval { rideIn.seconds + rideOut.seconds }
    var bikeMeters: Double { rideIn.meters + rideOut.meters }
    var climb: Double { rideIn.analysis.climbM + rideOut.analysis.climbM }
    /// Waiting at the boarding stop, boarding time included (TripBar "Wait").
    var wait: TimeInterval { max(0, departure.departs.timeIntervalSince(planned) - rideIn.seconds) }
    var onBoard: TimeInterval { departure.arrives.timeIntervalSince(departure.departs) }
}

/// Bike legs for the best direct connection, with the ride's rules (two ordinary plans, run in the background after
/// the bike-only options).
struct TransitPlanner: Sendable {
    let store: TransitStore
    let planner: RoutePlanner

    /// Candidates tried with real bike legs before giving up.
    static let tries = 2

    func plan(from origin: LatLon, to destination: LatLon, rules: RuleSet, at now: Date) async -> TransitPlan? {
        let candidates = DirectPlanner.candidates(store, from: origin, to: destination, at: now)
        for c in candidates.prefix(Self.tries) {
            guard let rideIn = try? await Self.best(planner.plan(from: origin, to: c.departure.board.location, heading: nil, rules: rules)),
                  let rideOut = try? await Self.best(planner.plan(from: c.departure.alight.location, to: destination, heading: nil, rules: rules))
            else { continue }
            // The real ride in may be longer than the estimate: take the first run of the same pair still caught.
            let ready = now.addingTimeInterval(rideIn.seconds + DirectPlanner.boarding(c.departure.route.mode))
            let runs = [c.departure] + DirectPlanner.later(store, than: c.departure, count: 4)
            guard let index = runs.firstIndex(where: { $0.departs >= ready }) else { continue }
            let d = runs[index]
            return TransitPlan(rideIn: rideIn, departure: d, rule: store.bikeRule(for: d), stops: store.stopTimes(of: d),
                               rideOut: rideOut, later: Array(runs.dropFirst(index + 1).prefix(2)), planned: now)
        }
        return nil
    }

    private static func best(_ plan: RoutePlan) -> RouteOption? {
        switch plan {
        case let .options(o): o.best
        case let .noRouteMeetsRules(_, _, closest, _): closest
        case .noRoute: nil
        }
    }
}

/// When to show "Long ride? Hop on the train with your bike" (CLAUDE.md decision override of BRIEF §8 / HANDOFF):
/// any one trigger, never under 5 km.
enum TransitTrigger {
    static let minimumTrip = 5000.0

    struct Bike: Sendable { var seconds: TimeInterval; var meters: Double; var climb: Double }

    static func shows(bike: Bike, transit: TransitPlan, destinationOutsideCity: Bool) -> Bool {
        shows(bike: bike, transitSeconds: transit.seconds, transitClimb: transit.climb, destinationOutsideCity: destinationOutsideCity)
    }

    static func shows(bike: Bike, transitSeconds: TimeInterval, transitClimb: Double, destinationOutsideCity: Bool) -> Bool {
        guard bike.meters >= minimumTrip else { return false }
        let saves = bike.seconds - transitSeconds
        guard saves > 0 else { return false }
        if saves >= 20 * 60 || saves >= 0.3 * bike.seconds { return true }
        if (bike.seconds > 45 * 60 || bike.meters > 12_000) && saves >= 10 * 60 { return true }
        if bike.climb - transitClimb >= 200 { return true }
        return destinationOutsideCity
    }
}
