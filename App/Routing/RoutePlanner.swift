import Foundation
@preconcurrency import FerrostarCore
@preconcurrency import FerrostarCoreFFI

/// The two calls the planner needs from Valhalla. ``ValhallaOnDeviceProvider`` implements them.
protocol RoutingEngine: Sendable {
    func route(rawRequest json: String) async throws -> String
    func traceAttributes(rawRequest json: String) async throws -> String
}

extension ValhallaOnDeviceProvider: RoutingEngine {}

/// One computed route with everything S3 needs about it.
struct RouteOption: Sendable {
    let costing: RoutingProfile
    /// Valhalla OSRM-format response: Ferrostar builds the navigation `Route` from it on Start.
    let osrmJSON: String
    let seconds: Double
    let meters: Double
    let analysis: RouteAnalysis
    let exclusions: [[[Double]]]
}

/// A road Fastest uses and Best doesn't, with the reason (AvoidedRow: dashed lilac on the map + tag).
struct AvoidedRoad: Equatable, Sendable {
    let name: String
    let meters: Double
    /// Tag text, design/tools/p4gen.js: "Rails along lane", "Cobbles 300 m", …
    let reason: String
    let shape: [LatLon]
}

struct RouteOptions: Sendable {
    let rules: RuleSet
    let best: RouteOption
    /// nil when one "Best and fastest" card is shown.
    let fastest: RouteOption?
    let fastestAnalysis: RouteAnalysis
    let bestName: String
    let bestLine: String
    let fastestLine: String?
    let litLine: String?
    let avoided: [AvoidedRoad]
    /// Rule pieces Best could not avoid (within the soft tolerance), shown on the route.
    let unavoidable: [RuleViolation]
    let rounds: Int
    let milliseconds: Double
}

enum RoutePlan: Sendable {
    case options(RouteOptions)
    /// "No route meets your <type> rules" + "<Rule> is on for <type>." The design's map shows Fastest's approach.
    case noRouteMeetsRules(Rule, RideType, fastest: RouteOption?)
    case noRoute
}

/// Best (ride type costing + rules) vs Fastest (permissive), compared by difference. See docs/DECISIONS.md (M3).
struct RoutePlanner: Sendable {
    let engine: RoutingEngine
    let hazards: HazardSource
    /// Exclusion rounds after the first route (cobbles, rails, steps… boxed out and routed again).
    var maxRounds = 3
    /// Valhalla's limit (raised in ValhallaOnDeviceProvider) with a margin.
    var maxExclusionPerimeter = 50_000.0

    func plan(from origin: LatLon, to destination: LatLon, heading: Double? = nil, rules: RuleSet) async throws -> RoutePlan {
        let started = Date()
        let profile = try RideProfile.load(rules.rideType)
        let fastest = try await compute(profile.fastest, from: origin, to: destination, heading: heading, exclusions: [])
        guard let firstBest = try await compute(profile.best, from: origin, to: destination, heading: heading, exclusions: []) else {
            return fastest == nil ? .noRoute : .noRouteMeetsRules(rules.active.first ?? .noCobbles, rules.rideType, fastest: fastest)
        }

        // Rule loop: box out what breaks a rule and route again; keep the best attempt.
        var best = firstBest, rounds = 0
        var exclusions: [[[Double]]] = []
        var remaining = RuleChecker.violations(of: rules.active, in: best.analysis)
        while !remaining.isEmpty, rounds < maxRounds {
            let more = remaining.flatMap(\.exclusions)
            guard !more.isEmpty, RuleChecker.perimeter(exclusions + more) <= maxExclusionPerimeter else { break }
            exclusions += more
            rounds += 1
            guard let next = try await compute(profile.best, from: origin, to: destination, heading: heading,
                                               exclusions: exclusions)
            else { break }
            let nextRemaining = RuleChecker.violations(of: rules.active, in: next.analysis)
            if score(nextRemaining) <= score(remaining) {
                best = next
                remaining = nextRemaining
            }
        }
        if let blocking = RuleChecker.hardViolations(remaining, rideType: rules.rideType).first {
            return .noRouteMeetsRules(blocking.rule, rules.rideType, fastest: fastest)
        }

        let fastestOption = fastest ?? best
        let same = fastest == nil || sameRoute(best.analysis, fastestOption.analysis)
        let single = DifferenceLine.showsSingleCard(bestSeconds: best.seconds, fastestSeconds: fastestOption.seconds,
                                                    sameRoute: same)
        let bestLine = single
            ? DifferenceLine.singleCardLine(best: best.analysis, bestSeconds: best.seconds, fastest: fastestOption.analysis,
                                            fastestSeconds: fastestOption.seconds, rideType: rules.rideType)
            : DifferenceLine.line(best: best.analysis, bestSeconds: best.seconds, fastest: fastestOption.analysis,
                                  fastestSeconds: fastestOption.seconds, rules: rules)
        let fastestLine = single ? nil
            : DifferenceLine.fastestLine(best: best.analysis, bestSeconds: best.seconds, fastest: fastestOption.analysis,
                                         fastestSeconds: fastestOption.seconds, rideType: rules.rideType)
        var litLine: String?
        if rules.litStreetsOnly, rounds > 0, firstBest.analysis.unlitPaths > best.analysis.unlitPaths {
            litLine = DifferenceLine.litLine(unlitPathsAvoided: firstBest.analysis.unlitPaths - best.analysis.unlitPaths,
                                             extraSeconds: best.seconds - firstBest.seconds)
        }
        return .options(RouteOptions(
            rules: rules, best: best, fastest: single ? nil : fastestOption, fastestAnalysis: fastestOption.analysis,
            bestName: single ? "Best and fastest" : rules.rideType.bestName, bestLine: bestLine,
            fastestLine: fastestLine, litLine: litLine,
            avoided: Self.avoidedRoads(best: best.analysis, fastest: fastestOption.analysis, rideType: rules.rideType),
            unavoidable: remaining, rounds: rounds, milliseconds: Date().timeIntervalSince(started) * 1000))
    }

    /// Lower is better: hard-rule metres dominate.
    private func score(_ violations: [RuleViolation]) -> Double {
        violations.reduce(0) { $0 + $1.meters }
    }

    private func sameRoute(_ a: RouteAnalysis, _ b: RouteAnalysis) -> Bool {
        let shared = a.metersByWay.reduce(0.0) { $0 + min($1.value, b.metersByWay[$1.key] ?? 0) }
        return shared >= 0.95 * max(a.lengthM, b.lengthM)
    }

    // MARK: Valhalla

    func compute(_ costing: RoutingProfile, from origin: LatLon, to destination: LatLon, heading: Double?,
                 exclusions: [[[Double]]]) async throws -> RouteOption? {
        var start = UserLocation(clCoordinateLocation2D: .init(latitude: origin.lat, longitude: origin.lon))
        if let heading { start.courseOverGround = CourseOverGround(degrees: UInt16(heading) % 360, accuracy: 30) }
        let request = try ValhallaOnDeviceProvider.requestJSON(
            from: start,
            waypoints: [Waypoint(coordinate: GeographicCoordinate(lat: destination.lat, lng: destination.lon), kind: .break)],
            profile: costing, excludePolygons: exclusions)
        guard let osrm = try? await engine.route(rawRequest: request),
              let route = try? JSONDecoder().decode(OSRMResponse.self, from: Data(osrm.utf8)).routes.first
        else { return nil }
        let trace = try await engine.traceAttributes(rawRequest: Self.traceRequest(polyline: route.geometry, costing: costing))
        let attrs = try JSONDecoder().decode(TraceResponse.self, from: Data(trace.utf8))
        let analysis = RouteAnalyzer.analyze(shape: Geo.decodePolyline6(attrs.shape), edges: attrs.edges, hazards: hazards)
        return RouteOption(costing: costing, osrmJSON: osrm, seconds: route.duration, meters: route.distance,
                           analysis: analysis, exclusions: exclusions)
    }

    static func traceRequest(polyline: String, costing: RoutingProfile) throws -> String {
        let attributes = ["edge.way_id", "edge.length", "edge.use", "edge.cycle_lane", "edge.road_class", "edge.surface",
                          "edge.unpaved", "edge.max_upward_grade", "edge.max_downward_grade", "edge.mean_elevation",
                          "edge.names", "edge.begin_shape_index", "edge.end_shape_index", "shape"]
        let body: JSONValue = .object([
            "encoded_polyline": .string(polyline),
            "costing": .string(costing.costing),
            "costing_options": .object([costing.costing: .object(costing.costingOptions)]),
            "shape_match": .string("edge_walk"),
            "filters": .object(["attributes": .array(attributes.map(JSONValue.string)), "action": .string("include")]),
        ])
        return String(decoding: try JSONEncoder().encode(body), as: UTF8.self)
    }

    // MARK: Why this route

    static func avoidedRoads(best: RouteAnalysis, fastest: RouteAnalysis, rideType: RideType) -> [AvoidedRoad] {
        let cobbleWays = Set(fastest.hazards.filter { $0.type == .cobbles }.map(\.osm))
        let alongWays = Set(fastest.hazards.filter { $0.type == .along }.map(\.osm))
        let stepWays = Set(fastest.hazards.filter { $0.type == .steps }.map(\.osm))
        struct Acc { var meters = 0.0; var reason: String; var shape: [LatLon] = [] }
        var byName: [String: Acc] = [:]
        for e in fastest.edges where best.metersByWay[e.wayId] == nil {
            let osm = "w\(e.wayId)"
            let reason: String
            if alongWays.contains(osm) { reason = "Rails along lane" }
            else if cobbleWays.contains(osm) { reason = "Cobbles" }
            else if stepWays.contains(osm) || e.use == "steps" { reason = "Steps" }
            else if RouteAnalyzer.category(of: e, cobbleWays: []) == .mixed, !RouteAnalyzer.quietClasses.contains(e.roadClass) {
                reason = "Mixed traffic"
            } else if e.unpaved, !rideType.seeksUnpaved { reason = "Unpaved" }
            else { continue }
            let name = e.name ?? reason
            var acc = byName[name] ?? Acc(reason: reason)
            acc.meters += e.meters
            let lo = max(0, min(e.beginShapeIndex, fastest.shape.count - 1))
            let hi = max(lo, min(e.endShapeIndex, fastest.shape.count - 1))
            acc.shape += fastest.shape[lo ... hi]
            byName[name] = acc
        }
        return byName.filter { $0.value.meters >= 100 }
            .map { name, acc in
                let tag = acc.reason == "Cobbles" || acc.reason == "Mixed traffic" || acc.reason == "Unpaved"
                    ? "\(acc.reason) \(DifferenceLine.distance(acc.meters))" : acc.reason
                return AvoidedRoad(name: name, meters: acc.meters, reason: tag, shape: acc.shape)
            }
            .sorted { $0.meters > $1.meters }
            .prefix(4).map { $0 }
    }
}

private struct OSRMResponse: Decodable {
    struct Route: Decodable { let duration: Double; let distance: Double; let geometry: String }
    let routes: [Route]
}

private struct TraceResponse: Decodable {
    let shape: String
    let edges: [RouteEdge]
}
