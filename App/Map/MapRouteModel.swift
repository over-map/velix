import Foundation

/// What the map draws for a planned trip (P3 route stack): GeoJSON-ready, built from ``RouteOptions`` (M6) or samples.
struct MapRouteModel: Equatable, Sendable {
    struct Avoided: Equatable, Sendable { var id: String; var shape: [LatLon]; var reason: String }
    struct HazardPoint: Equatable, Sendable { var type: HazardType; var at: LatLon }
    /// A train or metro leg (styles: `leg-train`, `leg-metro` with the line colour), through its stops.
    struct Leg: Equatable, Sendable { var metro: Bool; var line: [LatLon]; var color: String? }

    var best: [LatLon]
    var alternatives: [[LatLon]] = []
    var avoided: [Avoided] = []
    /// Striped tubes: the stretch of each hazard on the route (±14 m around a point, its length for lines).
    var tubes: [[LatLon]] = []
    var hazards: [HazardPoint] = []
    var start: LatLon?
    var end: LatLon?
    var endName: String?
    var puck: LatLon?
    var heading: Double = 0
    /// Bike + transit: the ride after the train (drawn like Best) and the train or metro leg.
    var rides: [[LatLon]] = []
    var legs: [Leg] = []
    /// Riding: the stretch of Best around the rider (drawn after `best`, which then holds the rest), and the share of it
    /// already ridden, faded out on the map (a line-gradient).
    var near: [LatLon]?
    var travelled: Double?

    /// Marker collision priority (docs/DECISIONS.md, 15 Oct): lower draws first and wins.
    static let rank: [HazardType: Int] = [.tram: 1, .along: 2, .steps: 3, .gap: 4, .lane: 5, .cobbles: 6, .dismount: 7,
                                          .door: 8, .descent: 9, .climb: 10]
    /// Half-length of a point hazard's tube (P3: ±14 m).
    static let tubeHalf = 14.0

    /// `clipBefore`: no tube before this distance along `best` (riding: the stretch behind the rider). `types`: the
    /// hazards drawn (``HazardType/onRoute``: none since 29 Oct; tests pass all of them).
    init(best: [LatLon], alternatives: [[LatLon]] = [], avoided: [Avoided] = [], hazards: [RouteHazard] = [], endName: String? = nil,
         clipBefore: Double = 0, types: Set<HazardType> = HazardType.onRoute) {
        self.best = best
        self.alternatives = alternatives
        self.avoided = avoided
        self.start = best.first
        self.end = best.last
        self.endName = endName
        let along = RouteAnalyzer.cumulative(best)
        for h in hazards where types.contains(h.type) {
            let a = h.lengthM > 1 ? h.distanceAlong : h.distanceAlong - Self.tubeHalf
            let b = h.lengthM > 1 ? h.distanceAlong + h.lengthM : h.distanceAlong + Self.tubeHalf
            let from = max(0, a, clipBefore), to = min(along.last ?? 0, b)
            let tube = from < to ? RuleChecker.trimmed(best, from: from, to: to) : []
            if tube.count > 1 { tubes.append(tube) }
            let mid = h.lengthM > 1 ? h.distanceAlong + h.lengthM / 2 : h.distanceAlong
            self.hazards.append(.init(type: h.type, at: RuleChecker.point(at: mid, on: best, along: along)))
        }
    }

    /// Everything given directly (samples, tests).
    init(best: [LatLon], alternatives: [[LatLon]], avoided: [Avoided], tubes: [[LatLon]], hazards: [HazardPoint],
         start: LatLon?, end: LatLon?, endName: String?, puck: LatLon?, heading: Double) {
        self.best = best; self.alternatives = alternatives; self.avoided = avoided; self.tubes = tubes; self.hazards = hazards
        self.start = start; self.end = end; self.endName = endName; self.puck = puck; self.heading = heading
    }

    /// From the planner: Best, Fastest as the alternative, the avoided roads and Best's hazards.
    init(options: RouteOptions, endName: String? = nil) {
        self.init(best: options.best.analysis.shape,
                  alternatives: options.fastest.map { [$0.analysis.shape] } ?? [],
                  avoided: options.avoided.enumerated().map { .init(id: "a\($0.offset)", shape: $0.element.shape, reason: $0.element.reason) },
                  hazards: options.best.analysis.hazards, endName: endName)
    }

    /// Bike + transit (P4 S3e): both rides in accent with their hazards, the run through its stops.
    init(transit p: TransitPlan, endName: String? = nil) {
        self.init(best: p.rideIn.analysis.shape, hazards: p.rideIn.analysis.hazards, endName: endName)
        let out = MapRouteModel(best: p.rideOut.analysis.shape, hazards: p.rideOut.analysis.hazards)
        rides = [p.rideOut.analysis.shape]
        tubes += out.tubes
        hazards += out.hazards
        end = p.rideOut.analysis.shape.last
        legs = [Leg(metro: p.departure.route.mode == .metro, line: p.stops.map(\.stop.location),
                    color: p.departure.route.mode == .metro ? p.departure.route.color.map { "#\($0)" } : nil)]
    }

    // MARK: GeoJSON

    func routeGeoJSON() -> Data {
        var f: [[String: Any]] = []
        for a in avoided { f.append(line(a.shape, ["role": "avoided"])) }
        for alt in alternatives { f.append(line(alt, ["role": "alt"])) }
        if best.count > 1 { f.append(line(best, ["role": "best"])) }
        for r in rides where r.count > 1 { f.append(line(r, ["role": "best"])) }
        for l in legs where l.line.count > 1 {
            // A metro leg takes its line colour from the GTFS; without one it is drawn like a train leg.
            if l.metro, let color = l.color { f.append(line(l.line, ["role": "leg-metro", "color": color])) }
            else { f.append(line(l.line, ["role": "leg-train"])) }
        }
        if let near, near.count > 1 { f.append(line(near, ["role": "best-near"])) }
        for t in tubes { f.append(line(t, ["role": "tube"])) }
        return collection(f)
    }

    func hazardsGeoJSON() -> Data {
        collection(hazards.map { point($0.at, ["hazard": $0.type.rawValue, "rank": Self.rank[$0.type] ?? 9]) })
    }

    func markersGeoJSON() -> Data {
        var f: [[String: Any]] = []
        if let start { f.append(point(start, ["role": "start"])) }
        if let end { f.append(point(end, ["role": "end", "name": endName ?? ""])) }
        for a in avoided where a.shape.count > 1 {
            f.append(point(RuleChecker.point(at: Geo.length(a.shape) / 2, on: a.shape, along: RouteAnalyzer.cumulative(a.shape)),
                           ["role": "avoided-tag", "id": a.id]))
        }
        if let puck { f.append(point(puck, ["role": "puck", "heading": heading])) }
        return collection(f)
    }

    private func line(_ c: [LatLon], _ props: [String: Any]) -> [String: Any] {
        ["type": "Feature", "properties": props, "geometry": ["type": "LineString", "coordinates": c.map { [$0.lon, $0.lat] }]]
    }

    private func point(_ c: LatLon, _ props: [String: Any]) -> [String: Any] {
        ["type": "Feature", "properties": props, "geometry": ["type": "Point", "coordinates": [c.lon, c.lat]]]
    }

    private func collection(_ f: [[String: Any]]) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["type": "FeatureCollection", "features": f])) ?? Data()
    }
}
