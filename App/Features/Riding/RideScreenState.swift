@preconcurrency import FerrostarCore
@preconcurrency import FerrostarCoreFFI
import Foundation

/// The turn ahead and what is left of the trip, from Ferrostar's navigation state (fixtures in snapshot tests).
struct RideTurn: Equatable, Sendable {
    struct Then: Equatable, Sendable { var maneuver: Maneuver; var street: String }
    var maneuver: Maneuver
    /// To the maneuver.
    var meters: Double
    var street: String
    var then: Then?
    var secondsLeft: Double
    var metersLeft: Double

    init(maneuver: Maneuver, meters: Double, street: String, then: Then? = nil, secondsLeft: Double, metersLeft: Double) {
        self.maneuver = maneuver; self.meters = meters; self.street = street; self.then = then
        self.secondsLeft = secondsLeft; self.metersLeft = metersLeft
    }

    /// Off route Ferrostar has no instruction: nil.
    init?(_ nav: NavigationState?) {
        guard let nav, let p = nav.currentProgress, let i = nav.currentVisualInstruction?.primaryContent else { return nil }
        maneuver = Maneuver(type: i.maneuverType, modifier: i.maneuverModifier)
        meters = p.distanceToNextManeuver
        street = Self.street(i.text) ?? maneuver.spoken
        secondsLeft = p.durationRemaining
        metersLeft = p.distanceRemaining
        // The step after the current one carries the following maneuver (P5 "Then").
        if let steps = nav.remainingSteps, steps.count > 1, let n = steps[1].visualInstructions.first?.primaryContent {
            then = Then(maneuver: Maneuver(type: n.maneuverType, modifier: n.maneuverModifier), street: Self.street(n.text) ?? "")
        }
    }

    /// On an unnamed way Valhalla's banner text is the instruction itself ("Turn right."): no street to show.
    static func street(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespaces)
        return t.isEmpty || t.hasSuffix(".") ? nil : t
    }
}

/// Everything S4 shows (P5 S4a–S4j), worked out from the ride: the banner, one hazard card, the ETA bar, the GPS
/// notice and the map of the route ahead. Pure, so every state can be snapshot-tested without a ride.
struct RideScreenState: Equatable {
    enum Top: Equatable {
        case turn(RideTurn, pill: RoadTypePill.Kind?, pillDistance: String?)
        case rerouting
    }
    struct Hazard: Equatable {
        var type: HazardType
        var advice: String
        var distance: String
        var approaching: Bool
    }

    var top: Top
    var hazard: Hazard?
    var eta: EtaBar.State
    var weakGPS: Bool
    var map: MapRouteModel
    /// The rest of the trip, for the overview (S4d).
    var ahead: [LatLon]
    /// Where the camera follows (on the line while near it) and the course it points along.
    var rider: LatLon?
    var course: Double

    /// Avoided roads show only this close to the rider (P5 S4f).
    static let avoidedWithin = 300.0
    /// Hazards stay on the map until this far behind the rider (P5 maps: `h.d > d − 4`).
    static let hazardsBehind = HazardTracker.passed

    struct Ride {
        var turn: RideTurn?
        var option: RouteOption
        var track: RouteTrack
        var next: HazardTracker.Next?
        var gps: GPSQuality = .good
        var rerouting = false
        var cannotFindRoute = false
        var arriving = false
        var destination: Place
        var avoided: [AvoidedRoad] = []
        var rider: LatLon?
        var heading: Double = 0
        /// The chevron overlay stands for the rider (2D / 3D follow): no map puck.
        var chevron = true
        var now = Date()
    }

    init(_ r: Ride) {
        let ahead = r.track.ahead
        self.ahead = ahead
        rider = r.rider
        course = r.heading
        weakGPS = r.gps == .weak

        if r.rerouting {
            top = .rerouting
        } else if r.arriving {
            // S4i: the door, no "Then", no pill.
            top = .turn(RideTurn(maneuver: .arrive, meters: r.track.remaining, street: r.destination.name,
                                 secondsLeft: r.turn?.secondsLeft ?? 0, metersLeft: r.track.remaining), pill: nil, pillDistance: nil)
        } else {
            let turn = r.turn ?? RideTurn(maneuver: .straight, meters: r.track.remaining, street: r.destination.name,
                                          secondsLeft: r.option.seconds * r.track.remaining / max(1, r.track.length), metersLeft: r.track.remaining)
            let run = Self.roadType(r.option.analysis, at: r.track.position)
            top = .turn(turn, pill: run.map { .mix($0.category) }, pillDistance: run.map { RideSession.distance($0.meters) })
        }

        // One card, the next hazard; it steps aside for the weak-GPS notice, rerouting and arriving (P5 S4g–S4i).
        if let n = r.next, !r.rerouting, !r.arriving, r.gps == .good {
            hazard = Hazard(type: n.hazard.type, advice: HazardPrompt.advice(n.hazard), distance: RideSession.distance(n.distance),
                            approaching: n.approaching)
        }

        if r.rerouting {
            eta = .rerouting(cannotFind: r.cannotFindRoute)
        } else if r.arriving {
            eta = .arriving
        } else {
            let seconds = r.turn?.secondsLeft ?? r.option.seconds * (r.track.remaining / max(1, r.track.length))
            let meters = r.turn?.metersLeft ?? r.track.remaining
            eta = .normal(arrival: r.now.addingTimeInterval(seconds).formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)),
                          minutes: "\(max(1, Int((seconds / 60).rounded())))",
                          km: String(format: "%.1f", meters / 1000))
        }

        // Placed on the whole route, so the hazards' coordinates stay the same from fix to fix (the map only
        // re-uploads what changed).
        let full = r.track.shape
        var map = MapRouteModel(best: full, avoided: Self.avoidedNear(r.rider, r.avoided),
                                hazards: Self.hazardsAhead(r.option.analysis.hazards, from: r.track.position),
                                endName: r.destination.name)
        // The line stays whole (no upload per fix); its ridden part fades at the rider.
        map.travelled = r.track.length > 0 ? r.track.position / r.track.length : nil
        map.start = nil
        map.end = r.destination.location
        if !r.chevron, let rider = r.rider { map.puck = rider; map.heading = r.heading }
        self.map = map
    }

    /// The route's hazards not yet passed (until 4 m beyond their end), measured along the whole route.
    static func hazardsAhead(_ hazards: [RouteHazard], from position: Double) -> [RouteHazard] {
        hazards.filter { $0.distanceAlong + max($0.lengthM, 0) > position - hazardsBehind }
    }

    /// Avoided roads within 300 m of the rider, tagged "Skipping Viale Piave: rails" (P5 S4f).
    static func avoidedNear(_ rider: LatLon?, _ roads: [AvoidedRoad]) -> [MapRouteModel.Avoided] {
        guard let rider else { return [] }
        return roads.enumerated().compactMap { i, a in
            let d = a.shape.count == 1 ? Geo.distance(rider, a.shape[0])
                : zip(a.shape, a.shape.dropFirst()).map { Geo.distance(from: rider, toSegment: $0, $1).meters }.min() ?? .infinity
            guard d <= avoidedWithin else { return nil }
            return .init(id: "r\(i)", shape: a.shape, reason: a.ridingTag)
        }
    }

    /// What the rider is on now and how far it goes on (P5 pill "Quiet · 160 m").
    static func roadType(_ a: RouteAnalysis, at position: Double) -> (category: MixCategory, meters: Double)? {
        guard !a.edges.isEmpty, a.shape.count > 1 else { return nil }
        let along = RouteAnalyzer.cumulative(a.shape)
        let cobbleWays = Set(a.hazards.filter { $0.type == .cobbles }.compactMap { Int64($0.osm.dropFirst()) })
        func end(_ e: RouteEdge) -> Double { along[min(max(e.endShapeIndex, 0), along.count - 1)] }
        // An edge ending within 10 m is already behind for the pill: show what comes next.
        guard let i = a.edges.firstIndex(where: { end($0) > position + 10 }) else { return nil }
        let category = RouteAnalyzer.category(of: a.edges[i], cobbleWays: cobbleWays)
        var j = i
        while j + 1 < a.edges.count, RouteAnalyzer.category(of: a.edges[j + 1], cobbleWays: cobbleWays) == category { j += 1 }
        return (category, max(0, end(a.edges[j]) - position))
    }
}

extension AvoidedRoad {
    /// Riding tag (P5 S4f): "Skipping Viale Piave: rails".
    var ridingTag: String {
        let short: String
        if reason.hasPrefix("Rails") { short = "rails" }
        else if reason.hasPrefix("Cobbles") { short = "cobbles" }
        else if reason.hasPrefix("Steps") { short = "steps" }
        else if reason.hasPrefix("Mixed traffic") { short = "traffic" }
        else if reason.hasPrefix("Unpaved") { short = "unpaved" }
        else { short = reason.lowercased() }
        return reason.hasPrefix(name) ? "Skipping \(short)" : "Skipping \(name): \(short)"
    }
}

extension MixCategory {
    /// Riding pill copy (P5 "Quiet · 160 m").
    var ridingLabel: String {
        switch self {
        case .protected: "Protected"
        case .painted: "Painted"
        case .quiet: "Quiet"
        case .mixed: "Mixed"
        case .cobbles: "Cobbles"
        case .unpaved: "Unpaved"
        }
    }
}
