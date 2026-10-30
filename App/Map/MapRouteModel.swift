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
    /// Routes tab (P7 S7): the listed routes with their key numbers; one in focus, or the others grey (S7c).
    var listed: [Listed] = []

    struct Listed: Equatable {
        enum State: String { case plain = "list", focus, grey = "list-grey" }
        var id: Int64
        var key: Int
        var line: [LatLon]
        /// Drawn piece by piece when given (a relation's pieces needn't join).
        var pieces: [[LatLon]] = []
        var state: State
    }
    var legs: [Leg] = []
    /// Bike + transit: where the ride meets the train or metro (getting on, getting off), marked on the map.
    var changes: [Change] = []
    /// The place itself when the route can't reach it (a park's centre, a building): the end marker goes there,
    /// with a dotted line from the route's end (Filippo, 30 Oct).
    var place: LatLon?
    /// Dotted lines from where a ride ends to where the rider goes on foot: the station, the destination.
    var connectors: [[LatLon]] = []
    /// Shorter than this, the route reaches the place: no dotted line.
    static let connectorMin = 8.0

    struct Change: Equatable {
        var at: LatLon
        var metro: Bool
    }

    /// Riding: the stretch of Best around the rider (drawn after `best`, which then holds the rest), and the share of it
    /// already ridden, faded out on the map (a line-gradient).
    /// Riding: the stretches around the rider whose ridden part fades (``RideScreenState``), and where the rider is,
    /// in metres along the route.
    var nearWindows: [NearWindow] = []
    var position: Double?

    /// A 400 m stretch of Best from `start` metres, drawn in one of two slots (style roles `best-near`, `best-near-b`):
    /// a new stretch takes the other slot, so the one on screen keeps its fade until the new one has been drawn.
    struct NearWindow: Equatable {
        var slot: Int
        var start: Double
        var length: Double
        var line: [LatLon]
    }

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
    /// `riding`: the train / metro leg only where its track is known (no straight line across the city while
    /// navigating); overviews join the stops where it isn't (Filippo, 30 Oct).
    init(transit p: TransitPlan, endName: String? = nil, riding: Bool = false) {
        self.init(best: p.rideIn.analysis.shape, hazards: p.rideIn.analysis.hazards, endName: endName)
        let out = MapRouteModel(best: p.rideOut.analysis.shape, hazards: p.rideOut.analysis.hazards)
        rides = [p.rideOut.analysis.shape]
        tubes += out.tubes
        hazards += out.hazards
        end = p.rideOut.analysis.shape.last
        let metro = p.departure.route.mode == .metro
        let color = metro ? p.departure.route.color.map { "#\($0)" } : nil
        legs = p.legLines(straightGaps: !riding).map { Leg(metro: metro, line: $0, color: color) }
        // At the stations, with a dotted line from where the bike legs end and start (the router stops at the road).
        let board = p.departure.board.location, alight = p.departure.alight.location
        changes = [Change(at: board, metro: metro), Change(at: alight, metro: metro)]
        connectors = [[p.rideIn.analysis.shape.last, board], [alight, p.rideOut.analysis.shape.first]].compactMap { pair in
            guard let a = pair[0], let b = pair[1], Geo.distance(a, b) >= Self.connectorMin else { return nil }
            return [a, b]
        }
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
        for w in nearWindows where w.line.count > 1 { f.append(line(w.line, ["role": w.slot == 0 ? "best-near" : "best-near-b"])) }
        for t in tubes { f.append(line(t, ["role": "tube"])) }
        for c in allConnectors { f.append(line(c, ["role": "connector"])) }
        // Focus last: drawn on top (the style orders the roles too).
        for l in listed.sorted(by: { ($0.state == .focus ? 1 : 0) < ($1.state == .focus ? 1 : 0) }) where l.line.count > 1 {
            for piece in l.pieces.isEmpty ? [l.line] : l.pieces where piece.count > 1 {
                f.append(line(piece, ["role": l.state.rawValue, "id": l.id]))
            }
        }
        return collection(f)
    }

    func hazardsGeoJSON() -> Data {
        collection(hazards.map { point($0.at, ["hazard": $0.type.rawValue, "rank": Self.rank[$0.type] ?? 9]) })
    }

    func markersGeoJSON() -> Data {
        var f: [[String: Any]] = []
        if let start { f.append(point(start, ["role": "start"])) }
        if let at = place ?? end { f.append(point(at, ["role": "end", "name": endName ?? ""])) }
        for c in changes { f.append(point(c.at, ["role": "change", "mode": c.metro ? "metro" : "train"])) }
        for a in avoided where a.shape.count > 1 {
            f.append(point(RuleChecker.point(at: Geo.length(a.shape) / 2, on: a.shape, along: RouteAnalyzer.cumulative(a.shape)),
                           ["role": "avoided-tag", "id": a.id]))
        }
        for l in listed where l.state != .grey && l.line.count > 1 {
            // On the longest piece: a third along the chained line can fall on a gap between pieces.
            let on = l.pieces.max { Geo.length($0) < Geo.length($1) } ?? l.line
            f.append(point(Self.keyPoint(on.count > 1 ? on : l.line), ["role": "key", "key": l.key, "focus": l.state == .focus]))
        }
        if let puck { f.append(point(puck, ["role": "puck", "heading": heading])) }
        return collection(f)
    }

    /// The connectors, with the one from the route's end to the place.
    var allConnectors: [[LatLon]] {
        guard let place, let end, Geo.distance(end, place) >= Self.connectorMin else { return connectors }
        return connectors + [[end, place]]
    }

    /// Where a route's key tile sits: a third of the way along (clear of the ends, where routes meet).
    static func keyPoint(_ line: [LatLon]) -> LatLon {
        RuleChecker.point(at: Geo.length(line) / 3, on: line, along: RouteAnalyzer.cumulative(line))
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
