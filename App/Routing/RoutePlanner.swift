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
    /// Milliseconds spent in route / trace / analysis (golden report, performance budget).
    var timings: [String: Double] = [:]
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
    /// Fastest's time, also when its card is hidden (it may then be slower than Best).
    var fastestSeconds: Double = 0
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
    /// "No route meets your <type> rules" + "<Rule> is on for <type>." `closest` is the attempt that came nearest
    /// (the design's map shows the approach with the blocking stretch tagged).
    case noRouteMeetsRules(Rule, RideType, closest: RouteOption?, remaining: [RuleViolation])
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
    /// valhalla-mobile slows down sharply with many polygons (≈ 0.1 s each on an M1): cap them.
    var maxExclusionPolygons = 60
    /// No new exclusion round starts after this (seconds since the plan started).
    var roundBudget = 1.2
    /// Soft ride types only try to remove rule-breaking worth more than this (seconds of penalty).
    var minPenaltyWorthARound = 60.0

    func plan(from origin: LatLon, to destination: LatLon, heading: Double? = nil, rules: RuleSet) async throws -> RoutePlan {
        let profile = try RideProfile.load(rules.rideType).adjusted(for: rules)
        let fastest = try await compute(profile.fastest, from: origin, to: destination, heading: heading, exclusions: [])
        let free = try await planOnce(from: origin, to: destination, heading: heading, rules: rules, fastest: fastest)
        guard !rules.respectOneways, needsOnewayCheck(free, rules: rules) else { return free }
        // One-ways ridden both ways (default) can lead Best into rule-breaking stretches the rounds don't clear:
        // plan once more following one-ways for Best and keep the better (never worse than before the setting
        // existed). Fastest stays the free one: pure fastest, whatever Best needed (Via Soave → Ripamonti, 20 Oct).
        var strictRules = rules
        strictRules.respectOneways = true
        let strict = try await planOnce(from: origin, to: destination, heading: heading, rules: strictRules, fastest: fastest,
                                        fewerLights: false)  // planning time: the re-plan only rescues Best
        return better(free, strict, rules: rules)
    }

    /// The free plan still breaks a rule enough to matter, or found nothing.
    private func needsOnewayCheck(_ plan: RoutePlan, rules: RuleSet) -> Bool {
        switch plan {
        case let .options(o):
            let v = RuleChecker.violations(of: rules.active, in: o.best.analysis)
            return rules.rideType == .cargo ? !RuleChecker.hardViolations(v, rideType: .cargo).isEmpty
                : penalty(RuleChecker.hardViolations(v, rideType: rules.rideType)) > minPenaltyWorthARound
        case .noRouteMeetsRules, .noRoute:
            return true
        }
    }

    private func better(_ a: RoutePlan, _ b: RoutePlan, rules: RuleSet) -> RoutePlan {
        switch (a, b) {
        case let (.options(x), .options(y)):
            let sx = x.best.seconds + penalty(RuleChecker.violations(of: rules.active, in: x.best.analysis))
            let sy = y.best.seconds + penalty(RuleChecker.violations(of: rules.active, in: y.best.analysis))
            return sy < sx ? b : a
        case (.options, _): return a
        case (_, .options): return b
        case (.noRouteMeetsRules, _): return a
        default: return b
        }
    }

    private func planOnce(from origin: LatLon, to destination: LatLon, heading: Double?, rules: RuleSet,
                          fastest: RouteOption?, fewerLights: Bool = true) async throws -> RoutePlan {
        let started = Date()
        let profile = try RideProfile.load(rules.rideType).adjusted(for: rules)
        guard let firstBest = try await compute(profile.best, from: origin, to: destination, heading: heading, exclusions: []) else {
            return fastest == nil ? .noRoute
                : .noRouteMeetsRules(rules.active.first ?? .noCobbles, rules.rideType, closest: fastest, remaining: [])
        }

        // Candidates: the plain Best, then reactive rounds that box out whatever still breaks a rule (few, small
        // polygons: Valhalla in valhalla-mobile slows down sharply with many). Cobbles are mostly avoided by the
        // costing itself (pack retags them, see pipeline/stages/prepare_routing.py). Then choose (see `choose`).
        var candidates = [firstBest]
        let firstViolations = RuleChecker.violations(of: rules.active, in: firstBest.analysis)
        var rounds = 0
        let worthTrying = rules.rideType == .cargo ? !firstViolations.isEmpty : penalty(firstViolations) > minPenaltyWorthARound
        if worthTrying {
            var current = firstBest
            var currentPenalty = penalty(firstViolations)
            // Cargo / kids is strict, so it gets two more rounds to find a way that meets every rule.
            let roundsAllowed = rules.rideType == .cargo ? maxRounds + 2 : maxRounds
            let budget = rules.rideType == .cargo ? roundBudget * 2 : roundBudget
            while rounds < roundsAllowed, Date().timeIntervalSince(started) < budget {
                let remaining = RuleChecker.violations(of: rules.active, in: current.analysis)
                    .sorted { Self.weight($0.rule) * $0.meters > Self.weight($1.rule) * $1.meters }
                let room = maxExclusionPolygons - current.exclusions.count
                let more = Array(remaining.flatMap(\.exclusions).prefix(max(room, 0)))
                guard !more.isEmpty else { break }
                rounds += 1
                var next = try await compute(profile.best, from: origin, to: destination, heading: heading,
                                             exclusions: current.exclusions + more)
                if next == nil {
                    // Valhalla refuses a request whose start or destination falls in an excluded box: keep the ends free.
                    let clear = (current.exclusions + more).filter { !Self.near($0, origin) && !Self.near($0, destination) }
                    next = try await compute(profile.best, from: origin, to: destination, heading: heading, exclusions: clear)
                }
                guard let next else { break }
                candidates.append(next)
                let nextPenalty = penalty(RuleChecker.violations(of: rules.active, in: next.analysis))
                // Stop when a round doesn't help: avoiding one stretch only led onto another.
                // Cargo / kids needs zero, so it keeps going on a tie.
                if nextPenalty > currentPenalty || (nextPenalty == currentPenalty && rules.rideType != .cargo) { break }
                current = next
                currentPenalty = nextPenalty
            }
        }
        // Fewer lights: Valhalla prefers lanes across busy signalised junctions over quiet streets that cross fewer.
        // Box out the lights of the leading candidate that Fastest doesn't also cross (those are on the direct line)
        // away from both ends; `choose` keeps it only if it's quicker once the waits count.
        let lead = choose(candidates, rules: rules).option
        let shared = fastest?.analysis.signalStops.map(\.location) ?? []
        let avoidable = lead.analysis.signalStops.filter { s in
            s.distanceAlong > Self.lightsEndMargin && s.distanceAlong < lead.analysis.lengthM - Self.lightsEndMargin
                && !shared.contains { Geo.distance($0, s.location) < RouteAnalyzer.junctionSpan }
        }
        // Valhalla slows down sharply with many polygons (≈ 1.2 s a request after a few rule rounds): skip it then.
        if fewerLights, !avoidable.isEmpty, lead.exclusions.count + min(avoidable.count, Self.maxLightBoxes) <= Self.maxPolygonsWithLights {
            let boxes = avoidable.prefix(Self.maxLightBoxes).map { Geo.box(around: [$0.location], padding: Self.lightBoxPadding) }
            if let next = try await compute(profile.best, from: origin, to: destination, heading: heading,
                                            exclusions: lead.exclusions + boxes) {
                candidates.append(next)
            }
        }
        // Fastest is a candidate too for the soft types: Best is never worse than Fastest on time + rule penalty.
        if let fastest, rules.rideType != .cargo { candidates.append(fastest) }
        let choice = choose(candidates, rules: rules)
        if let blocking = choice.blocking {
            return .noRouteMeetsRules(blocking, rules.rideType, closest: choice.option,
                                      remaining: RuleChecker.violations(of: rules.active, in: choice.option.analysis))
        }
        let best = choice.option
        let remaining = RuleChecker.violations(of: rules.active, in: best.analysis)

        let fastestOption = fastest ?? best
        let same = fastest == nil || sameRoute(best.analysis, fastestOption.analysis)
        let single = DifferenceCopy.showsSingleCard(bestSeconds: best.seconds, fastestSeconds: fastestOption.seconds,
                                                    sameRoute: same)
        let bestLine = single
            ? DifferenceCopy.singleCardLine(best: best.analysis, bestSeconds: best.seconds, fastest: fastestOption.analysis,
                                            fastestSeconds: fastestOption.seconds, rideType: rules.rideType)
            : DifferenceCopy.line(best: best.analysis, bestSeconds: best.seconds, fastest: fastestOption.analysis,
                                  fastestSeconds: fastestOption.seconds, rules: rules)
        let fastestLine = single ? nil
            : DifferenceCopy.fastestLine(best: best.analysis, bestSeconds: best.seconds, fastest: fastestOption.analysis,
                                         fastestSeconds: fastestOption.seconds, rideType: rules.rideType)
        var litLine: String?
        if rules.litStreetsOnly, firstBest.analysis.unlitPaths > best.analysis.unlitPaths {
            litLine = DifferenceCopy.litLine(unlitPathsAvoided: firstBest.analysis.unlitPaths - best.analysis.unlitPaths,
                                             extraSeconds: best.seconds - firstBest.seconds)
        }
        return .options(RouteOptions(
            rules: rules, best: best, fastest: single ? nil : fastestOption, fastestAnalysis: fastestOption.analysis,
            fastestSeconds: fastestOption.seconds,
            bestName: single ? "Best and fastest" : rules.rideType.bestName, bestLine: bestLine,
            fastestLine: fastestLine, litLine: litLine,
            avoided: Self.avoidedRoads(best: best.analysis, fastest: fastestOption.analysis, rideType: rules.rideType),
            unavoidable: remaining, rounds: rounds, milliseconds: Date().timeIntervalSince(started) * 1000))
    }

    /// Whether an exclusion ring comes within 150 m of a point.
    static func near(_ ring: [[Double]], _ p: LatLon) -> Bool {
        let pts = ring.map { LatLon(lat: $0[1], lon: $0[0]) }
        let (s, w, n, e) = Geo.bbox(pts, padding: 150)
        return p.lat >= s && p.lat <= n && p.lon >= w && p.lon <= e
    }

    /// Cargo / kids: the quickest candidate that meets every rule, or the rule that blocks.
    /// Other ride types: the lowest time + penalty (seconds per metre that breaks a rule); never blocked, and what
    /// remains is shown on the route (the design's City Best keeps 70 m of cobbles with "No cobbles" on).
    private func choose(_ candidates: [RouteOption], rules: RuleSet) -> (option: RouteOption, blocking: Rule?) {
        let scored = candidates.map { c in (c, RuleChecker.violations(of: rules.active, in: c.analysis)) }
        if rules.rideType == .cargo {
            if let ok = scored.filter({ RuleChecker.hardViolations($0.1, rideType: .cargo).isEmpty })
                .min(by: { $0.0.seconds + penalty($0.1) < $1.0.seconds + penalty($1.1) }) {
                return (ok.0, nil)
            }
            let closest = scored.min { penalty($0.1) < penalty($1.1) }!
            let broken = Set(closest.1.map(\.rule))
            return (closest.0, rules.active.first(where: broken.contains))
        }
        return (scored.min { $0.0.seconds + penalty($0.1) < $1.0.seconds + penalty($1.1) }!.0, nil)
    }

    /// Riding pace on passages (walk stretches), km/h.
    static let passagePace = 10.0
    /// Average wait at a signalised junction: about half the time you arrive on red, then wait ≈ 20 s.
    static let signalWait = 10.0
    /// Lights this close to the start or the destination are left alone by the fewer-lights candidate (metres).
    static let lightsEndMargin = 150.0
    static let maxLightBoxes = 6
    static let maxPolygonsWithLights = 12
    static let lightBoxPadding = 25.0

    /// Seconds of detour a metre of each broken rule is worth. Cobbles 3 s/m: Filippo takes a longer route to avoid
    /// them more than for anything else (300 m of cobbles ≈ worth a 15-min detour).
    static func weight(_ rule: Rule) -> Double {
        switch rule {
        case .noCobbles: 3.0
        case .neverAlongTramRails: 3.0
        case .noStepsOrGaps: 3.0
        case .pavedOnly: 1.2
        case .maxGrade6: 2.0
        case .bikeLanesOnly: 0.5
        case .litStreetsOnly: 0.7
        case .noWalking: 3.0
        case .walkingStretches: 0
        }
    }

    private func penalty(_ violations: [RuleViolation]) -> Double {
        violations.reduce(0) { $0 + Self.weight($1.rule) * $1.meters }
    }

    private func sameRoute(_ a: RouteAnalysis, _ b: RouteAnalysis) -> Bool {
        let shared = a.metersByWay.reduce(0.0) { $0 + min($1.value, b.metersByWay[$1.key] ?? 0) }
        return shared >= 0.95 * max(a.lengthM, b.lengthM)
    }

    // MARK: Valhalla

    func compute(_ costing: RoutingProfile, from origin: LatLon, to destination: LatLon, heading: Double?,
                 exclusions: [[[Double]]], vias: [LatLon] = []) async throws -> RouteOption? {
        var start = UserLocation(clCoordinateLocation2D: .init(latitude: origin.lat, longitude: origin.lon))
        if let heading { start.courseOverGround = CourseOverGround(degrees: UInt16(heading) % 360, accuracy: 30) }
        let request = try ValhallaOnDeviceProvider.requestJSON(
            from: start,
            waypoints: vias.map { Waypoint(coordinate: GeographicCoordinate(lat: $0.lat, lng: $0.lon), kind: .via) }
                + [Waypoint(coordinate: GeographicCoordinate(lat: destination.lat, lng: destination.lon), kind: .break)],
            profile: costing, excludePolygons: exclusions)
        var t = Date()
        var timings: [String: Double] = ["requestKB": Double(request.utf8.count) / 1024]
        func lap(_ key: String) { timings[key] = Date().timeIntervalSince(t) * 1000; t = Date() }
        guard let osrm = try? await engine.route(rawRequest: request),
              let route = try? JSONDecoder().decode(OSRMResponse.self, from: Data(osrm.utf8)).routes.first
        else { return nil }
        lap("route")
        let trace = try await engine.traceAttributes(rawRequest: Self.traceRequest(polyline: route.geometry, costing: costing))
        lap("trace")
        let attrs = try JSONDecoder().decode(TraceResponse.self, from: Data(trace.utf8))
        let analysis = RouteAnalyzer.analyze(shape: Geo.decodePolyline6(attrs.shape), edges: attrs.edges, hazards: hazards)
        lap("analyze")
        // Valhalla's bicycle costing never waits at traffic lights (a signal even lowers its turn stress): add the
        // average wait per signalised junction, so routes compare as Google's do (Filippo's Via Soave commute, 19 Oct).
        let waits = Double(analysis.signalStops.count) * Self.signalWait
        // Cobbles reach Valhalla as gravel (pack retag, so Best avoids them), which it rides at 40–75 % speed: time
        // them at riding pace (Filippo: pure fastest, cobbles at normal speed); the rules' penalties keep them out of Best.
        let cobbleWays = Set(analysis.hazards.filter { $0.type == .cobbles }.map(\.osm))
        let pace: Double = if case let .number(v) = costing.costingOptions["cycling_speed"] { v } else { 16 }
        let cobbleSaving = analysis.edges.filter { cobbleWays.contains("w\($0.wayId)") && $0.speed > 0 }.reduce(0.0) { sum, e in
            sum + max(0, e.meters / (Double(e.speed) / 3.6) - e.meters / (max(Double(e.speed), pace) / 3.6))
        }
        // Passages (hospital roads, garden paths, pedestrian streets) are ridden slowly (Filippo, 19 Oct): Valhalla times
        // them at full speed because the tiles open them with bicycle=yes.
        let passageExtra = analysis.walkEdges.filter { $0.speed > 0 }.reduce(0.0) { sum, e in
            sum + max(0, e.meters / (min(Double(e.speed), Self.passagePace) / 3.6) - e.meters / (Double(e.speed) / 3.6))
        }
        return RouteOption(costing: costing, osrmJSON: osrm, seconds: route.duration + waits - cobbleSaving + passageExtra,
                           meters: route.distance,
                           analysis: analysis, exclusions: exclusions, timings: timings)
    }

    static func traceRequest(polyline: String, costing: RoutingProfile) throws -> String {
        let attributes = ["edge.way_id", "edge.length", "edge.use", "edge.cycle_lane", "edge.road_class", "edge.surface",
                          "edge.unpaved", "edge.max_upward_grade", "edge.max_downward_grade", "edge.weighted_grade", "edge.mean_elevation",
                          "edge.names", "edge.speed", "edge.begin_shape_index", "edge.end_shape_index", "shape"]
        let body: JSONValue = .object([
            "encoded_polyline": .string(polyline),
            "costing": .string(costing.costing),
            "costing_options": .object([costing.costing: .object(costing.costingOptions)]),
            // edge_walk is exact for our own route shapes but fails on a few; walk_or_snap falls back to map matching.
            "shape_match": .string("walk_or_snap"),
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
                    ? "\(acc.reason) \(DifferenceCopy.distance(acc.meters))" : acc.reason
                return AvoidedRoad(name: name, meters: acc.meters, reason: tag, shape: acc.shape)
            }
            .sorted { $0.meters > $1.meters }
            .prefix(4).map { $0 }
    }
}

struct OSRMResponse: Decodable {
    struct Route: Decodable { let duration: Double; let distance: Double; let geometry: String }
    let routes: [Route]
}

struct TraceResponse: Decodable {
    let shape: String
    let edges: [RouteEdge]
}
