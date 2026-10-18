import Foundation

/// A rule the route breaks, the stretches that break it, and boxes to exclude on the next try.
struct RuleViolation: Equatable, Sendable {
    let rule: Rule
    let meters: Double
    let exclusions: [[[Double]]]
}

/// Checks a route against the active rules. Thresholds absorb data noise; logged in docs/DECISIONS.md.
enum RuleChecker {
    /// Pieces this close to the start or the destination don't count (your own doorstep may be cobbled).
    static let endpointTolerance = 50.0
    static let cobbleTolerance = 15.0
    static let alongTolerance = 15.0
    static let unpavedTolerance = 50.0
    /// "Bike lanes only": mixed traffic is allowed only for short links and crossings.
    static let maxMixedRun = 150.0
    static let maxGrade = 6
    static let gradeMinLength = 50.0

    static func violations(of rules: [Rule], in a: RouteAnalysis) -> [RuleViolation] {
        rules.compactMap { violation(of: $0, in: a) }
    }

    /// What may remain when nothing better exists. The design's City Best keeps 70 m of cobbles at Piazza Ascoli with
    /// "No cobbles" on, while Cargo / kids is blocked by cobbles: so rules are soft for every type but Cargo / kids.
    static func softTolerance(_ rule: Rule, rideType: RideType) -> Double {
        guard rideType != .cargo else { return 0 }
        switch rule {
        case .noCobbles: return 100
        case .neverAlongTramRails: return 30
        case .pavedOnly: return 200
        case .litStreetsOnly: return 100
        case .noStepsOrGaps, .maxGrade6, .bikeLanesOnly, .noWalking: return 0
        }
    }

    /// Violations that still count after the soft tolerance for this ride type.
    static func hardViolations(_ violations: [RuleViolation], rideType: RideType) -> [RuleViolation] {
        violations.filter { $0.meters > softTolerance($0.rule, rideType: rideType) }
    }

    static func violation(of rule: Rule, in a: RouteAnalysis) -> RuleViolation? {
        let along = RouteAnalyzer.cumulative(a.shape)
        let total = along.last ?? a.lengthM
        func inside(_ e: RouteEdge) -> Bool {
            let s = along[safe: e.beginShapeIndex] ?? 0, t = along[safe: e.endShapeIndex] ?? total
            return t > endpointTolerance && s < total - endpointTolerance
        }
        func points(_ e: RouteEdge) -> [LatLon] {
            let lo = max(0, min(e.beginShapeIndex, a.shape.count - 1)), hi = max(lo, min(e.endShapeIndex, a.shape.count - 1))
            return Array(a.shape[lo ... hi])
        }
        /// One box per edge, trimmed short of both ends so the streets crossing at its junctions stay usable
        /// (Valhalla drops every edge touching a polygon), and few polygons (valhalla-mobile slows down with many).
        func point(at d: Double, on p: [LatLon], along: [Double]) -> LatLon { RuleChecker.point(at: d, on: p, along: along) }
        func boxes(_ edges: [RouteEdge], padding: Double) -> [[[Double]]] {
            edges.compactMap { e -> [[Double]]? in
                let p = points(e)
                guard p.count > 1 else { return p.isEmpty ? nil : Geo.box(around: p, padding: padding) }
                let len = Geo.length(p)
                let trim = min(8, len / 4)
                let inner = trimmed(p, from: trim, to: len - trim)
                return inner.count > 1 ? Geo.box(around: inner, padding: padding) : nil
            }
        }
        let cobbleWays = Set(a.hazards.filter { $0.type == .cobbles }.map(\.osm))
        let alongWays = Set(a.hazards.filter { $0.type == .along }.map(\.osm))  // already without separated tracks

        switch rule {
        case .noCobbles:
            let bad = a.edges.filter { cobbleWays.contains("w\($0.wayId)") && inside($0) }
            let m = bad.reduce(0) { $0 + $1.meters }
            return m > cobbleTolerance ? RuleViolation(rule: rule, meters: m, exclusions: boxes(bad, padding: 8)) : nil
        case .neverAlongTramRails:
            let bad = a.edges.filter { alongWays.contains("w\($0.wayId)") && inside($0) }
            let m = a.hazards.filter { $0.type == .along && alongWays.contains($0.osm) }.reduce(0) { $0 + $1.lengthM }
            return m > alongTolerance && !bad.isEmpty
                ? RuleViolation(rule: rule, meters: m, exclusions: boxes(bad, padding: 4)) : nil
        case .noStepsOrGaps:
            let stepWays = Set(a.hazards.filter { $0.type == .steps }.map(\.osm))
            let stepEdges = a.edges.filter { e in (e.use == "steps" || stepWays.contains("w\(e.wayId)")) && inside(e) }
            let gaps = a.hazards.filter { $0.type == .gap && isNarrowGap($0.detail) && $0.distanceAlong > endpointTolerance && $0.distanceAlong < total - endpointTolerance }
            guard !stepEdges.isEmpty || !gaps.isEmpty else { return nil }
            // A barrier is a point: box just the barrier, so the way and its junctions stay usable around it.
            let gapBoxes = gaps.map { g in Geo.box(around: [point(at: g.distanceAlong, on: a.shape, along: along)], padding: 3) }
            return RuleViolation(rule: rule, meters: stepEdges.reduce(0) { $0 + $1.meters } + Double(gaps.count),
                                 exclusions: boxes(stepEdges, padding: 6) + gapBoxes)
        case .pavedOnly:
            // Cobbles reach Valhalla as "dirt" (pack retag): they are paved, and the cobbles rule covers them.
            let bad = a.edges.filter { $0.unpaved && !cobbleWays.contains("w\($0.wayId)") && inside($0) }
            let m = bad.reduce(0) { $0 + $1.meters }
            return m > unpavedTolerance ? RuleViolation(rule: rule, meters: m, exclusions: boxes(bad, padding: 4)) : nil
        case .maxGrade6:
            // Sustained slopes from the smoothed profile (see ElevationProfile), up or down.
            let steep = a.profile.stretches(steeperThan: Double(maxGrade), climb: true, minLength: 300)
                + a.profile.stretches(steeperThan: Double(maxGrade), climb: false, minLength: 300)
            guard !steep.isEmpty else { return nil }
            var edgeStart = 0.0
            var bad: [RouteEdge] = []
            for e in a.edges {
                let lo = edgeStart, hi = edgeStart + e.meters
                if steep.contains(where: { $0.start < hi && $0.start + $0.length > lo }), inside(e) { bad.append(e) }
                edgeStart = hi
            }
            let meters = steep.reduce(0) { $0 + $1.length }
            return RuleViolation(rule: rule, meters: meters, exclusions: boxes(bad, padding: 4))
        case .bikeLanesOnly:
            var runs: [[RouteEdge]] = [], current: [RouteEdge] = []
            for e in a.edges {
                if RouteAnalyzer.category(of: e, cobbleWays: []) == .mixed { current.append(e) } else if !current.isEmpty {
                    runs.append(current); current = []
                }
            }
            if !current.isEmpty { runs.append(current) }
            let long = runs.filter { $0.reduce(0) { $0 + $1.meters } > maxMixedRun }.flatMap { $0 }.filter(inside)
            return long.isEmpty ? nil : RuleViolation(rule: rule, meters: long.reduce(0) { $0 + $1.meters },
                                                      exclusions: boxes(long, padding: 3))
        case .noWalking:
            let bad = a.walkEdges.filter(inside)
            let m = bad.reduce(0) { $0 + $1.meters }
            return m > 0 ? RuleViolation(rule: rule, meters: m, exclusions: boxes(bad, padding: 3)) : nil
        case .litStreetsOnly:
            // Unlit paths and roads tagged unlit, from the sidecar `ways` table (RouteAnalyzer).
            return a.unlitMeters > 0
                ? RuleViolation(rule: rule, meters: a.unlitMeters, exclusions: boxes(a.unlitEdges.filter(inside), padding: 6))
                : nil
        }
    }

    /// The point `d` metres along a polyline.
    static func point(at d: Double, on p: [LatLon], along: [Double]) -> LatLon {
        guard p.count > 1 else { return p.first ?? LatLon(lat: 0, lon: 0) }
        let i = max(0, min((along.firstIndex { $0 >= d } ?? along.count - 1) - 1, p.count - 2))
        let seg = along[i + 1] - along[i]
        let f = seg > 0 ? max(0, min(1, (d - along[i]) / seg)) : 0
        return LatLon(lat: p[i].lat + (p[i + 1].lat - p[i].lat) * f, lon: p[i].lon + (p[i + 1].lon - p[i].lon) * f)
    }

    /// The part of a polyline between two distances along it.
    static func trimmed(_ p: [LatLon], from a: Double, to b: Double) -> [LatLon] {
        guard b > a else { return [] }
        let along = RouteAnalyzer.cumulative(p)
        func at(_ d: Double) -> LatLon {
            let i = max(0, min((along.firstIndex { $0 >= d } ?? along.count - 1) - 1, p.count - 2))
            let seg = along[i + 1] - along[i]
            let f = seg > 0 ? (d - along[i]) / seg : 0
            return LatLon(lat: p[i].lat + (p[i + 1].lat - p[i].lat) * f, lon: p[i].lon + (p[i + 1].lon - p[i].lon) * f)
        }
        return [at(a)] + zip(p, along).filter { $0.1 > a && $0.1 < b }.map(\.0) + [at(b)]
    }

    /// Barriers that make a narrow gap (a cargo bike or trailer can't pass); bollards and open gates don't count.
    static let narrowBarriers: Set<String> = ["cycle_barrier", "kissing_gate", "stile", "turnstile", "full-height_turnstile",
                                              "motorcycle_barrier"]
    static func isNarrowGap(_ detail: String) -> Bool {
        narrowBarriers.contains(detail) || detail.hasPrefix("maxwidth")
    }

    /// Total perimeter of exclusion rings (Valhalla limits it; see ValhallaOnDeviceProvider).
    static func perimeter(_ rings: [[[Double]]]) -> Double {
        rings.reduce(0) { sum, ring in
            sum + zip(ring, ring.dropFirst()).reduce(0) { $0 + Geo.distance(LatLon(lat: $1.0[1], lon: $1.0[0]), LatLon(lat: $1.1[1], lon: $1.1[0])) }
        }
    }
}
