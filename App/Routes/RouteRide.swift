import Foundation

/// Ride this route (P7 S7d, BRIEF: "plan to the nearest point, then follow"): ride to the end of the route nearer to
/// the rider, then along the whole route to the other end. One Valhalla route through vias placed along the relation,
/// so Ferrostar rides it as one; no rule rounds (the route is the point) and no Fastest card.
enum RouteRide {
    /// Vias every this many metres along the route, fewer on long routes (Valhalla takes a few dozen locations).
    static let viaSpacing = 1500.0
    static let maxVias = 40

    struct Leg: Equatable {
        /// The route oriented from where the rider joins it.
        var line: [LatLon]
        /// The names at the join and at the far end ("from" / "to" swapped when ridden the other way).
        var from: String
        var to: String
        var reversed: Bool
    }

    /// Join at the nearer end.
    static func leg(_ route: CycleRoute, from origin: LatLon) -> Leg? {
        guard let first = route.line.first, let last = route.line.last, route.line.count > 1 else { return nil }
        let reversed = Geo.distance(origin, last) < Geo.distance(origin, first)
        return Leg(line: reversed ? route.line.reversed() : route.line, from: reversed ? route.to : route.from,
                   to: reversed ? route.from : route.to, reversed: reversed)
    }

    /// The join point, then points along the line, evenly spaced; the far end is the destination, not a via.
    static func vias(_ line: [LatLon]) -> [LatLon] {
        guard let first = line.first, line.count > 1 else { return [] }
        let along = RouteAnalyzer.cumulative(line)
        let length = along.last ?? 0
        let spacing = max(viaSpacing, length / Double(maxVias))
        var out = [first]
        var d = spacing
        while d < length - spacing / 2 {
            out.append(RuleChecker.point(at: d, on: line, along: along))
            d += spacing
        }
        return out
    }

    /// How much of the planned option is the ride to the route: the distance along its shape to the point nearest
    /// the join.
    static func approachMeters(_ option: RouteOption, join: LatLon) -> Double {
        let shape = option.analysis.shape
        guard shape.count > 1 else { return 0 }
        let along = RouteAnalyzer.cumulative(shape)
        // The nearest point in the first half (a loop route passes its own start again at the end); the via snaps to
        // the road, so it may not be on the shape exactly.
        let half = shape.indices.filter { along[$0] <= along.last! / 2 }
        let nearest = half.min { Geo.distance(shape[$0], join) < Geo.distance(shape[$1], join) } ?? 0
        return along[nearest]
    }

    /// S7d: "**16 min** to the start at the Darsena, then the full route to Pavia".
    static func line(approachSeconds: TimeInterval, leg: Leg) -> String {
        let mins = max(1, Int((approachSeconds / 60).rounded()))
        let start = leg.from.isEmpty ? "to the start" : "to the start at \(leg.from)"
        let end = leg.to.isEmpty ? "then the full route" : "then the full route to \(leg.to)"
        return "**\(mins) min** \(start), \(end)"
    }

    /// "2 h 20", "45 min".
    static func duration(_ s: TimeInterval) -> String {
        let m = max(1, Int((s / 60).rounded()))
        return m < 60 ? "\(m) min" : "\(m / 60) h \(String(format: "%02d", m % 60))"
    }
}

extension RoutePlanner {
    /// One Best-costing route from `origin` through `vias` to `destination` (Ride this route, and its reroutes).
    func follow(from origin: LatLon, through vias: [LatLon], to destination: LatLon, heading: Double? = nil,
                rules: RuleSet) async throws -> RouteOption? {
        let profile = try RideProfile.load(rules.rideType).adjusted(for: rules)
        return try await compute(profile.best, from: origin, to: destination, heading: heading, exclusions: [], vias: vias,
                                 phase: "follow")
    }
}
