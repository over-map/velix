import Foundation

/// Where hazards and lighting come from: the pack sidecar (``HazardStore``) or a test fake.
protocol HazardSource: Sendable {
    func lineHazards(onWays ways: some Collection<Int64>) -> [HazardRecord]
    func pointHazards(in box: (Double, Double, Double, Double)) -> [HazardRecord]
    func lighting(ofWays ways: some Collection<Int64>) -> [Int64: (lit: Bool?, path: Bool)]
}

extension HazardStore: HazardSource {}

/// Turns a route's Valhalla edges and shape into a ``RouteAnalysis``.
enum RouteAnalyzer {
    /// A point hazard counts as on the route within this distance of its line.
    static let pointTolerance = 6.0
    /// Lane-end hazards apply only when riding within this angle of their heading.
    static let headingTolerance = 50.0

    static let pathUses: Set<String> = ["cycleway", "path", "mountain_bike", "footway", "sidewalk", "track", "bridleway"]
    static let quietClasses: Set<String> = ["residential", "service_other", "unclassified", "service"]

    static func category(of edge: RouteEdge, cobbleWays: Set<Int64>) -> MixCategory {
        if cobbleWays.contains(edge.wayId) { return .cobbles }
        if edge.unpaved { return .unpaved }
        if pathUses.contains(edge.use) { return .protected }
        if edge.use == "living_street" || edge.use == "pedestrian" || edge.use == "steps" { return .quiet }
        switch edge.cycleLane {
        case "separated": return .protected
        case "dedicated": return .painted
        default: break
        }
        // Quiet: residential-type streets, or any road at 30 km/h or less (Zona 30, 20 mph zones).
        return quietClasses.contains(edge.roadClass) || edge.speed <= calmSpeed ? .quiet : .mixed
    }

    static let calmSpeed = 30

    static func analyze(shape: [LatLon], edges: [RouteEdge], hazards source: some HazardSource) -> RouteAnalysis {
        var a = RouteAnalysis(shape: shape, edges: edges)
        let along = cumulative(shape)
        a.lengthM = edges.reduce(0) { $0 + $1.meters }
        let wayIDs = edges.map(\.wayId)

        // Line hazards by way id.
        let lines = Dictionary(grouping: source.lineHazards(onWays: wayIDs), by: { $0.wayId ?? -1 })
        let cobbleWays = Set(lines.compactMap { way, hz in hz.contains { $0.type == .cobbles } ? way : nil })
        let lighting = source.lighting(ofWays: wayIDs)

        var run = 0.0
        var seenLineHazard = Set<String>()
        for edge in edges {
            let cat = category(of: edge, cobbleWays: cobbleWays)
            a.mix[cat, default: 0] += edge.meters
            a.metersByWay[edge.wayId, default: 0] += edge.meters
            if pathUses.contains(edge.use) { a.pathMeters += edge.meters }
            if cat == .mixed {
                run += edge.meters
                a.longestMixedRun = max(a.longestMixedRun, run)
                if let name = edge.name, !quietClasses.contains(edge.roadClass) { a.busyByName[name, default: 0] += edge.meters }
            } else {
                run = 0
            }

            if let l = lighting[edge.wayId], edge.meters >= 30, (l.path && l.lit != true) || l.lit == false {
                a.unlitMeters += edge.meters
                a.unlitEdges.append(edge)
            }
            for h in lines[edge.wayId] ?? [] {
                // Rails beside a separated track or path are behind a kerb: the hazard is sharing the carriageway.
                if h.type == .along, cat == .protected { continue }
                let key = "\(h.id)"
                guard !seenLineHazard.contains(key) else { continue }
                seenLineHazard.insert(key)
                a.hazards.append(RouteHazard(type: h.type, distanceAlong: along[safe: edge.beginShapeIndex] ?? 0,
                                             lengthM: min(h.lengthM, edge.meters), street: edge.name,
                                             detail: h.detail, osm: h.osm))
            }
        }
        a.unlitPaths = Set(edges.filter { e in
            guard let l = lighting[e.wayId], e.meters >= 30 else { return false }
            return (l.path && l.lit != true) || l.lit == false
        }.map(\.wayId)).count

        // Point hazards near the line, chunk by chunk.
        var seenPoints = Set<Int64>()
        let chunk = 40
        for start in stride(from: 0, to: max(shape.count - 1, 0), by: chunk) {
            let end = min(start + chunk, shape.count - 1)
            let piece = Array(shape[start ... end])
            for h in source.pointHazards(in: Geo.bbox(piece, padding: pointTolerance + 2)) where !seenPoints.contains(h.id) {
                let p = LatLon(lat: h.lat, lon: h.lon)
                var best: (d: Double, i: Int, t: Double)?
                for i in start ..< end {
                    let r = Geo.distance(from: p, toSegment: shape[i], shape[i + 1])
                    if r.meters <= pointTolerance, r.meters < (best?.d ?? .infinity) { best = (r.meters, i, r.t) }
                }
                guard let hit = best else { continue }
                if let heading = h.heading,
                   Geo.angleBetween(heading, Geo.bearing(shape[hit.i], shape[hit.i + 1])) > headingTolerance {
                    continue
                }
                seenPoints.insert(h.id)
                let d = along[hit.i] + hit.t * Geo.distance(shape[hit.i], shape[hit.i + 1])
                a.hazards.append(RouteHazard(type: h.type, distanceAlong: d, lengthM: 0,
                                             street: edgeName(at: hit.i, edges), detail: h.detail, osm: h.osm))
            }
        }
        a.profile = ElevationProfile(edges: edges)
        a.climbM = a.profile.climb
        a.maxGrade = Int(a.profile.maxGrade.rounded())
        a.hazards += steepStretches(a.profile, edges: edges, along: along)
        a.hazards.sort { $0.distanceAlong < $1.distanceAlong }
        return a
    }

    /// Steep climbs and descents from Valhalla edge grades (elevation is baked into the pack tiles).
    static let steepGrade = 7
    static let steepMinLength = 300.0

    static func steepStretches(_ profile: ElevationProfile, edges: [RouteEdge], along: [Double]) -> [RouteHazard] {
        var out: [RouteHazard] = []
        for kind in [HazardType.climb, .descent] {
            for s in profile.stretches(steeperThan: Double(steepGrade) - 0.5, climb: kind == .climb, minLength: steepMinLength) {
                let sign = kind == .climb ? "+" : "−"
                out.append(RouteHazard(type: kind, distanceAlong: s.start, lengthM: s.length,
                                       street: street(atDistance: s.start, edges),
                                       detail: "\(sign)\(Int(s.worst.rounded()))% for \(DifferenceLine.distance(s.length))", osm: ""))
            }
        }
        return out
    }

    private static func street(atDistance d: Double, _ edges: [RouteEdge]) -> String? {
        var x = 0.0
        for e in edges {
            x += e.meters
            if x >= d { return e.name }
        }
        return edges.last?.name
    }

    static func cumulative(_ shape: [LatLon]) -> [Double] {
        var out = [0.0]
        out.reserveCapacity(shape.count)
        for (a, b) in zip(shape, shape.dropFirst()) { out.append(out.last! + Geo.distance(a, b)) }
        return out
    }

    private static func edgeName(at shapeIndex: Int, _ edges: [RouteEdge]) -> String? {
        edges.first { $0.beginShapeIndex <= shapeIndex && shapeIndex < max($0.endShapeIndex, $0.beginShapeIndex + 1) }?.name
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
