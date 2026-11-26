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
    let connection: TransitConnection
    let rule: BikeRule
    /// Estimated ride to the boarding stop and from the alighting stop.
    let rideIn: TimeInterval
    let rideOut: TimeInterval
    let arrival: Date

    var departure: TransitDeparture { connection.departure }
}

/// Direct connections only (BUILD_PLAN M8, iteration 1): ride to a station, one train or metro run that takes bikes,
/// ride on. No changes. From Transitous since M11 PR 4 (``TransitSource``), live times where operators publish them.
enum DirectPlanner {
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

    /// Direct connections catchable from `origin` at `now` that take bikes, earliest arrival at `destination` first.
    static func candidates(_ runs: [TransitConnection], rules: BikeRules, from origin: LatLon, to destination: LatLon,
                           at now: Date) -> [TransitCandidate] {
        var best: [String: TransitCandidate] = [:]   // per run: its best board/alight pair
        for c in runs {
            let d = c.departure
            let tin = estimate(origin, d.board.location), tout = estimate(d.alight.location, destination)
            guard Geo.distance(d.board.location, d.alight.location) >= minimumHop,
                  d.departs >= now.addingTimeInterval(tin + boarding(d.route.mode)) else { continue }
            let rule = rules.rule(for: d, feedAllowsBikes: c.feedAllowsBikes)
            guard rule.offered else { continue }
            let candidate = TransitCandidate(connection: c, rule: rule, rideIn: tin, rideOut: tout,
                                             arrival: d.arrives.addingTimeInterval(outOfStation + tout))
            if let old = best[d.trip], old.arrival <= candidate.arrival { continue }
            best[d.trip] = candidate
        }
        return best.values.sorted { $0.arrival < $1.arrival }
    }

    /// The next runs between the same two stops after `d` that take bikes (the "Next trains" chips, a missed train).
    static func later(_ runs: [TransitConnection], rules: BikeRules, than d: TransitDeparture, count: Int) -> [TransitConnection] {
        var seen = Set<String>()
        return runs.filter { c in
            c.departure.board.id == d.board.id && c.departure.alight.id == d.alight.id && c.departure.departs > d.departs
                && rules.rule(for: c.departure, feedAllowsBikes: c.feedAllowsBikes).offered && seen.insert(c.departure.trip).inserted
        }
        .sorted { $0.departure.departs < $1.departure.departs }
        .prefix(count).map { $0 }
    }

    /// The leg's line cut at each stop (nearest point, in order), so the map draws it hop by hop
    /// (``TransitPlan/legLines(straightGaps:)``); nil where the line is missing.
    static func hops(_ line: [LatLon], stops: [TransitStopTime]) -> [[LatLon]?] {
        guard line.count > 1, stops.count > 1 else { return Array(repeating: nil, count: max(0, stops.count - 1)) }
        var cuts: [Int] = []
        var from = 0
        for (i, s) in stops.enumerated() {
            if i == 0 { cuts.append(0); continue }
            if i == stops.count - 1 { cuts.append(line.count - 1); continue }
            var bestIndex = from, bestDistance = Double.infinity
            for j in from ..< line.count {
                let m = Geo.distance(line[j], s.stop.location)
                if m < bestDistance { bestDistance = m; bestIndex = j }
            }
            cuts.append(bestIndex)
            from = bestIndex
        }
        return zip(cuts, cuts.dropFirst()).map { a, b in b > a ? Array(line[a ... b]) : nil }
    }
}

/// Ride in, one run, ride out (S3e TransitCard, S5).
struct TransitPlan: Sendable {
    let rideIn: RouteOption
    let departure: TransitDeparture
    let rule: BikeRule
    let stops: [TransitStopTime]
    let rideOut: RouteOption
    /// When the plan was made (the rider leaves now).
    let planned: Date
    /// The track between consecutive stops (``DirectPlanner/hops(_:stops:)``), nil where unknown.
    var track: [[LatLon]?] = []
    /// The other runs the plan was made from (a missed train takes the next one of the same pair).
    var runs: [TransitConnection] = []

    /// The leg as drawn: on the track where known. `straightGaps` joins the stops with straight lines where it isn't
    /// (overviews: the leg reads as one); else those stretches are left out (riding: no line across the city).
    func legLines(straightGaps: Bool) -> [[LatLon]] {
        let pts = stops.map(\.stop.location)
        var out: [[LatLon]] = []
        var current: [LatLon] = []
        func add(_ line: [LatLon]) { current += current.last == line.first ? Array(line.dropFirst()) : line }
        for (i, pair) in zip(pts, pts.dropFirst()).enumerated() {
            if let t = track.indices.contains(i) ? track[i] : nil {
                add(t)
            } else if straightGaps {
                add([pair.0, pair.1])
            } else {
                if current.count > 1 { out.append(current) }
                current = []
            }
        }
        if current.count > 1 { out.append(current) }
        return out
    }

    var arrival: Date { departure.arrives.addingTimeInterval(DirectPlanner.outOfStation + rideOut.seconds) }
    var seconds: TimeInterval { arrival.timeIntervalSince(planned) }
    var bikeSeconds: TimeInterval { rideIn.seconds + rideOut.seconds }
    var bikeMeters: Double { rideIn.meters + rideOut.meters }
    var climb: Double { rideIn.analysis.climbM + rideOut.analysis.climbM }
    /// Waiting at the boarding stop, boarding time included (TripBar "Wait").
    var wait: TimeInterval { max(0, departure.departs.timeIntervalSince(planned) - rideIn.seconds) }
    var onBoard: TimeInterval { departure.arrives.timeIntervalSince(departure.departs) }
    /// The run's time zone (times on screen).
    var zone: TimeZone { departure.timeZone }

    /// A live update's times for the run.
    struct Moved: Equatable, Sendable { let departs: Date; let arrives: Date; let realTime: Bool }

    /// The plan with the run at its live times: the stops shift by the delay (Transitous gives the delay per stop
    /// only in the whole trip; the shift keeps the timeline consistent).
    func moved(_ m: Moved) -> TransitPlan {
        let delay = m.departs.timeIntervalSince(departure.departs)
        let shifted = stops.enumerated().map { i, s in
            i == stops.count - 1 ? TransitStopTime(stop: s.stop, arrives: m.arrives, departs: m.arrives)
                : TransitStopTime(stop: s.stop, arrives: s.arrives.addingTimeInterval(delay), departs: s.departs.addingTimeInterval(delay))
        }
        var p = TransitPlan(rideIn: rideIn, departure: departure.moved(departs: m.departs, arrives: m.arrives, realTime: m.realTime),
                            rule: rule, stops: shifted, rideOut: rideOut, planned: planned)
        p.track = track
        p.runs = runs
        return p
    }
}

/// Bike legs for the best direct connection, with the ride's rules (two ordinary plans, run in the background after
/// the bike-only options).
struct TransitPlanner: Sendable {
    let source: TransitSource
    var rules: BikeRules = .bundled
    let planner: RoutePlanner

    /// Candidates tried with real bike legs before giving up.
    static let tries = 2

    /// The best connection: the first run still caught after the real ride in, then the next runs of the same pair
    /// (S3e "Next trains": up to three choices). Empty when no direct connection with bikes works, or offline.
    func plans(from origin: LatLon, to destination: LatLon, rules ride: RuleSet, at now: Date) async -> [TransitPlan] {
        guard let runs = try? await source.connections(from: origin, to: destination, at: now) else { return [] }
        let candidates = DirectPlanner.candidates(runs, rules: rules, from: origin, to: destination, at: now)
        for c in candidates.prefix(Self.tries) {
            guard let rideIn = try? await Self.best(planner.plan(from: origin, to: c.departure.board.location, heading: nil, rules: ride)),
                  let rideOut = try? await Self.best(planner.plan(from: c.departure.alight.location, to: destination, heading: nil, rules: ride))
            else { continue }
            // The real ride in may be longer than the estimate: take the first run of the same pair still caught.
            let ready = now.addingTimeInterval(rideIn.seconds + DirectPlanner.boarding(c.departure.route.mode))
            let choices = ([c.connection] + DirectPlanner.later(runs, rules: rules, than: c.departure, count: 4))
                .filter { $0.departure.departs >= ready }
            guard !choices.isEmpty else { continue }
            return choices.prefix(Self.choices).map { plan($0, rideIn: rideIn, rideOut: rideOut, planned: now, runs: runs) }
        }
        return []
    }

    func plan(_ c: TransitConnection, rideIn: RouteOption, rideOut: RouteOption, planned: Date, runs: [TransitConnection]) -> TransitPlan {
        Self.plan(c, rules: rules, rideIn: rideIn, rideOut: rideOut, planned: planned, runs: runs)
    }

    static func plan(_ c: TransitConnection, rules: BikeRules, rideIn: RouteOption, rideOut: RouteOption, planned: Date,
                     runs: [TransitConnection]) -> TransitPlan {
        var p = TransitPlan(rideIn: rideIn, departure: c.departure, rule: rules.rule(for: c.departure, feedAllowsBikes: c.feedAllowsBikes),
                            stops: c.stops, rideOut: rideOut, planned: planned)
        p.track = DirectPlanner.hops(c.line, stops: c.stops)
        p.runs = runs
        return p
    }

    static let choices = 3

    func plan(from origin: LatLon, to destination: LatLon, rules: RuleSet, at now: Date) async -> TransitPlan? {
        await plans(from: origin, to: destination, rules: rules, at: now).first
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
        // A transit trip of no time or less is broken data, never a saving.
        guard bike.meters >= minimumTrip, transitSeconds > 0 else { return false }
        let saves = bike.seconds - transitSeconds
        guard saves > 0 else { return false }
        if saves >= 20 * 60 || saves >= 0.3 * bike.seconds { return true }
        if (bike.seconds > 45 * 60 || bike.meters > 12_000) && saves >= 10 * 60 { return true }
        if bike.climb - transitClimb >= 200 { return true }
        return destinationOutsideCity
    }
}
