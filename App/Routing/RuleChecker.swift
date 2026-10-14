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
    static let gradeMinLength = 30.0

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
        case .noStepsOrGaps, .maxGrade6, .bikeLanesOnly: return 0
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
        func boxes(_ edges: [RouteEdge], padding: Double) -> [[[Double]]] {
            edges.flatMap { e -> [[[Double]]] in
                let p = points(e)
                guard p.count > 1 else { return p.isEmpty ? [] : [Geo.box(around: p, padding: padding)] }
                return zip(p, p.dropFirst()).map { Geo.box(around: [$0.0, $0.1], padding: padding) }
            }
        }
        let cobbleWays = Set(a.hazards.filter { $0.type == .cobbles }.map(\.osm))
        let alongWays = Set(a.hazards.filter { $0.type == .along }.map(\.osm))

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
            let gaps = a.hazards.filter { $0.type == .gap && $0.distanceAlong > endpointTolerance && $0.distanceAlong < total - endpointTolerance }
            guard !stepEdges.isEmpty || !gaps.isEmpty else { return nil }
            let gapBoxes = gaps.compactMap { g -> [[Double]]? in
                guard let e = a.edges.first(where: { (along[safe: $0.beginShapeIndex] ?? 0) <= g.distanceAlong && g.distanceAlong <= (along[safe: $0.endShapeIndex] ?? total) }) else { return nil }
                return Geo.box(around: points(e), padding: 6)
            }
            return RuleViolation(rule: rule, meters: stepEdges.reduce(0) { $0 + $1.meters } + Double(gaps.count),
                                 exclusions: boxes(stepEdges, padding: 6) + gapBoxes)
        case .pavedOnly:
            let bad = a.edges.filter { $0.unpaved && inside($0) }
            let m = bad.reduce(0) { $0 + $1.meters }
            return m > unpavedTolerance ? RuleViolation(rule: rule, meters: m, exclusions: boxes(bad, padding: 4)) : nil
        case .maxGrade6:
            let bad = a.edges.filter { $0.meters >= gradeMinLength && max($0.maxUpwardGrade, $0.maxDownwardGrade) > maxGrade && inside($0) }
            return bad.isEmpty ? nil : RuleViolation(rule: rule, meters: bad.reduce(0) { $0 + $1.meters },
                                                     exclusions: boxes(bad, padding: 4))
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
        case .litStreetsOnly:
            // Unlit paths and roads tagged unlit, from the sidecar `ways` table (RouteAnalyzer).
            return a.unlitMeters > 0
                ? RuleViolation(rule: rule, meters: a.unlitMeters, exclusions: boxes(a.unlitEdges.filter(inside), padding: 6))
                : nil
        }
    }

    /// Total perimeter of exclusion rings (Valhalla limits it; see ValhallaOnDeviceProvider).
    static func perimeter(_ rings: [[[Double]]]) -> Double {
        rings.reduce(0) { sum, ring in
            sum + zip(ring, ring.dropFirst()).reduce(0) { $0 + Geo.distance(LatLon(lat: $1.0[1], lon: $1.0[0]), LatLon(lat: $1.1[1], lon: $1.1[0])) }
        }
    }
}
