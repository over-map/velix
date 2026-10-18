import Foundation
import Testing
@testable import Velix

/// In-memory stand-in for the pack's hazards.sqlite.
struct FakeHazards: HazardSource {
    var lines: [HazardRecord] = []
    var points: [HazardRecord] = []
    var lit: [Int64: (lit: Bool?, path: Bool)] = [:]
    var walk: Set<Int64> = []

    func lineHazards(onWays ways: some Collection<Int64>) -> [HazardRecord] {
        let set = Set(ways)
        return lines.filter { $0.wayId.map(set.contains) ?? false }
    }

    func pointHazards(in box: (Double, Double, Double, Double)) -> [HazardRecord] {
        points.filter { $0.lat >= box.0 && $0.lat <= box.2 && $0.lon >= box.1 && $0.lon <= box.3 }
    }

    func lighting(ofWays ways: some Collection<Int64>) -> [Int64: (lit: Bool?, path: Bool)] {
        lit.filter { Set(ways).contains($0.key) }
    }

    func walkWays(among ways: some Collection<Int64>) -> Set<Int64> {
        walk.intersection(ways)
    }

    static func line(_ type: HazardType, way: Int64, length: Double) -> HazardRecord {
        HazardRecord(id: way * 10 + Int64(type.rawValue.count), type: type, isLine: true, lat: 0, lon: 0,
                     lengthM: length, polyline6: "", detail: "", osm: "w\(way)", heading: nil)
    }

    static func point(_ type: HazardType, id: Int64, at p: LatLon, heading: Double? = nil) -> HazardRecord {
        HazardRecord(id: id, type: type, isLine: false, lat: p.lat, lon: p.lon, lengthM: 0, polyline6: "",
                     detail: "", osm: "n\(id)", heading: heading)
    }
}

/// A straight route east along a latitude, one shape point every 100 m, one edge per 100 m step.
func eastwardRoute(_ edges: [(way: Int64, edit: (inout RouteEdge) -> Void)]) -> (shape: [LatLon], edges: [RouteEdge]) {
    let step = 100 / (111_320 * cos(45.47 * .pi / 180))
    let shape = (0 ... edges.count).map { LatLon(lat: 45.47, lon: 9.20 + Double($0) * step) }
    let built = edges.enumerated().map { i, spec -> RouteEdge in
        var e = RouteEdge(wayId: spec.way, lengthKm: 0.1, beginShapeIndex: i, endShapeIndex: i + 1)
        spec.edit(&e)
        return e
    }
    return (shape, built)
}

func edge(use: String = "road", lane: String = "none", road: String = "residential", unpaved: Bool = false,
          up: Int = 0, down: Int = 0, name: String? = nil, elevation: Double? = nil) -> (inout RouteEdge) -> Void {
    { e in
        e = RouteEdge(wayId: e.wayId, lengthKm: e.lengthKm, use: use, cycleLane: lane, roadClass: road, unpaved: unpaved,
                      maxUpwardGrade: up, maxDownwardGrade: down, weightedGrade: Double(up > 0 ? up : -down),
                      meanElevation: elevation, names: name.map { [$0] } ?? [],
                      beginShapeIndex: e.beginShapeIndex, endShapeIndex: e.endShapeIndex)
    }
}

struct RuleSetTests {
    @Test func cityDefaultsFollowTheDesign() {
        #expect(RuleSet.defaults(for: .city).active == [.noCobbles, .neverAlongTramRails, .noStepsOrGaps])
        #expect(RuleSet.defaults(for: .cargo).active.count == 5)
        #expect(RuleSet.defaults(for: .gravel).active == [.neverAlongTramRails])
    }

    @Test func litStreetsOnlyComesLast() {
        var rules = RuleSet.defaults(for: .road)
        rules.litStreetsOnly = true
        #expect(rules.active == [.pavedOnly, .noCobbles, .neverAlongTramRails, .litStreetsOnly])
    }

    @Test(arguments: RideType.allCases)
    func everyTypeHasABestName(_ type: RideType) {
        #expect(!type.bestName.isEmpty && type.bestName != "Best and fastest")
    }
}

struct RouteAnalyzerTests {
    @Test func classifiesTheMix() {
        let none: Set<Int64> = []
        #expect(RouteAnalyzer.category(of: RouteEdge(wayId: 1, lengthKm: 0.1, use: "cycleway"), cobbleWays: none) == .protected)
        #expect(RouteAnalyzer.category(of: RouteEdge(wayId: 1, lengthKm: 0.1, cycleLane: "dedicated", roadClass: "primary"), cobbleWays: none) == .painted)
        #expect(RouteAnalyzer.category(of: RouteEdge(wayId: 1, lengthKm: 0.1, roadClass: "residential"), cobbleWays: none) == .quiet)
        #expect(RouteAnalyzer.category(of: RouteEdge(wayId: 1, lengthKm: 0.1, roadClass: "primary"), cobbleWays: none) == .mixed)
        #expect(RouteAnalyzer.category(of: RouteEdge(wayId: 1, lengthKm: 0.1, roadClass: "tertiary", speed: 30), cobbleWays: none) == .quiet)
        #expect(RouteAnalyzer.category(of: RouteEdge(wayId: 7, lengthKm: 0.1), cobbleWays: [7]) == .cobbles)
        #expect(RouteAnalyzer.category(of: RouteEdge(wayId: 1, lengthKm: 0.1, use: "cycleway", unpaved: true), cobbleWays: none) == .unpaved)
    }

    @Test func railsBesideASeparatedTrackAreNotAHazard() {
        let (shape, edges) = eastwardRoute([(1, edge(use: "cycleway")), (2, edge(road: "secondary"))])
        let source = FakeHazards(lines: [FakeHazards.line(.along, way: 1, length: 100), FakeHazards.line(.along, way: 2, length: 100)])
        let a = RouteAnalyzer.analyze(shape: shape, edges: edges, hazards: source)
        #expect(a.hazards.filter { $0.type == .along }.map(\.osm) == ["w2"])
    }

    @Test func findsHazardsOnTheRoute() {
        let (shape, edges) = eastwardRoute([(1, edge()), (2, edge(name: "Via Morgagni")), (3, edge(road: "primary", name: "Corso Buenos Aires")), (4, edge())])
        let tram = FakeHazards.point(.tram, id: 100, at: LatLon(lat: shape[1].lat + 0.00002, lon: shape[1].lon))
        let far = FakeHazards.point(.gap, id: 101, at: LatLon(lat: shape[1].lat + 0.001, lon: shape[1].lon))
        let laneWrongWay = FakeHazards.point(.lane, id: 102, at: shape[3], heading: 270)
        let laneRightWay = FakeHazards.point(.lane, id: 103, at: shape[2], heading: 85)
        let source = FakeHazards(lines: [FakeHazards.line(.cobbles, way: 2, length: 100)],
                                 points: [tram, far, laneWrongWay, laneRightWay])
        let a = RouteAnalyzer.analyze(shape: shape, edges: edges, hazards: source)
        #expect(a.meters(.cobbles) == 100)
        #expect(a.meters(.mixed) == 100)
        #expect(a.busyByName["Corso Buenos Aires"] == 100)
        #expect(a.hazards.map(\.osm).sorted() == ["n100", "n103", "w2"])
        let t = try! #require(a.hazards.first { $0.osm == "n100" })
        #expect(abs(t.distanceAlong - 100) < 2)
    }

    /// Edges with mean elevations climbing `rise` metres per 100 m edge, in the middle of a flat route.
    private func hill(rise: Double, edges n: Int = 8) -> [(way: Int64, edit: (inout RouteEdge) -> Void)] {
        let flat = 6
        return (0 ..< (flat + n + flat)).map { i in
            let e: Double = 120 + (i < flat ? 0 : Double(min(i - flat + 1, n)) * rise)
            return (Int64(i + 1), edge(elevation: e))
        }
    }

    @Test func detectsSustainedSlopes() {
        let (shape, edges) = eastwardRoute(hill(rise: 9))
        let a = RouteAnalyzer.analyze(shape: shape, edges: edges, hazards: FakeHazards())
        let climb = try! #require(a.hazards.first { $0.type == .climb })
        #expect(climb.lengthM >= 300)
        #expect(a.maxGrade >= 8)
        #expect(!a.hazards.contains { $0.type == .descent })
    }

    @Test func ignoresRooftopSpikes() {
        // Flat street, one edge sampled on a 15 m roof (surface model): no slope.
        var specs: [(way: Int64, edit: (inout RouteEdge) -> Void)] = (0 ..< 10).map { (Int64($0 + 1), edge(elevation: 120)) }
        specs[5] = (6, edge(elevation: 135))
        let (shape, edges) = eastwardRoute(specs)
        let a = RouteAnalyzer.analyze(shape: shape, edges: edges, hazards: FakeHazards())
        #expect(a.maxGrade <= 1)
        #expect(!a.hazards.contains { $0.type == .climb || $0.type == .descent })
    }

    @Test func countsUnlitPaths() {
        let (shape, edges) = eastwardRoute([(1, edge(use: "cycleway")), (2, edge(use: "path")), (3, edge())])
        let source = FakeHazards(lit: [1: (true, true), 2: (nil, true), 3: (nil, false)])
        let a = RouteAnalyzer.analyze(shape: shape, edges: edges, hazards: source)
        #expect(a.unlitPaths == 1)
        #expect(a.unlitMeters == 100)
    }
}

struct RuleCheckerTests {
    private func analysis(_ specs: [(way: Int64, edit: (inout RouteEdge) -> Void)], cobbles: [Int64] = [],
                          walk: Set<Int64> = []) -> RouteAnalysis {
        let (shape, edges) = eastwardRoute(specs)
        return RouteAnalyzer.analyze(shape: shape, edges: edges,
                                     hazards: FakeHazards(lines: cobbles.map { FakeHazards.line(.cobbles, way: $0, length: 100) },
                                                          walk: walk))
    }

    @Test func walkingStretchesBreakNoWalkingAndGetExcluded() throws {
        let a = analysis([(1, edge()), (2, edge(use: "footway")), (3, edge())], walk: [2])
        #expect(a.walkEdges.map(\.wayId) == [2])
        let v = try #require(RuleChecker.violation(of: .noWalking, in: a))
        #expect(v.meters == 100)
        #expect(!v.exclusions.isEmpty)
        #expect(RuleChecker.hardViolations([v], rideType: .city) == [v])
        #expect(RuleChecker.violation(of: .noWalking, in: analysis([(1, edge()), (2, edge())])) == nil)
    }

    @Test func cobblesMidRouteBreakTheRuleAndGetExcluded() throws {
        let a = analysis([(1, edge()), (2, edge()), (3, edge())], cobbles: [2])
        let v = try #require(RuleChecker.violation(of: .noCobbles, in: a))
        #expect(v.meters == 100)
        #expect(!v.exclusions.isEmpty)
    }

    @Test func cobbledDoorstepDoesNotCount() {
        // The last edge ends at the destination; only its last 50 m would be tolerated, so use a short last edge.
        var a = analysis([(1, edge()), (2, edge())], cobbles: [])
        a.edges[1] = RouteEdge(wayId: 9, lengthKm: 0.04, beginShapeIndex: 1, endShapeIndex: 2)
        a.shape[2] = LatLon(lat: a.shape[1].lat, lon: a.shape[1].lon + 40 / (111_320 * cos(45.47 * .pi / 180)))
        a.hazards = [RouteHazard(type: .cobbles, distanceAlong: 100, lengthM: 40, street: nil, detail: "", osm: "w9")]
        #expect(RuleChecker.violation(of: .noCobbles, in: a) == nil)
    }

    @Test func softToleranceAppliesToCityNotToCargo() {
        let v = RuleViolation(rule: .noCobbles, meters: 70, exclusions: [])
        #expect(RuleChecker.hardViolations([v], rideType: .city).isEmpty)
        #expect(RuleChecker.hardViolations([v], rideType: .cargo) == [v])
    }

    @Test func bikeLanesOnlyAllowsShortMixedLinks() {
        let shortLink = analysis([(1, edge(use: "cycleway")), (2, edge(road: "primary")), (3, edge(use: "cycleway")), (4, edge(use: "cycleway"))])
        #expect(RuleChecker.violation(of: .bikeLanesOnly, in: shortLink) == nil)
        let longRun = analysis([(1, edge(use: "cycleway")), (2, edge(road: "primary")), (3, edge(road: "secondary")), (4, edge(use: "cycleway"))])
        #expect(RuleChecker.violation(of: .bikeLanesOnly, in: longRun)?.meters == 200)
    }

    @Test func maxGradeCountsSustainedSlopesEitherWay() {
        let down: [(way: Int64, edit: (inout RouteEdge) -> Void)] = (0 ..< 20).map { i in
            (Int64(i + 1), edge(elevation: 200 - Double(min(max(i - 5, 0), 9)) * 8))
        }
        #expect(RuleChecker.violation(of: .maxGrade6, in: analysis(down)) != nil)
        let flat: [(way: Int64, edit: (inout RouteEdge) -> Void)] = (0 ..< 14).map { (Int64($0 + 1), edge(elevation: 120)) }
        #expect(RuleChecker.violation(of: .maxGrade6, in: analysis(flat)) == nil)
    }
}

struct DifferenceCopyTests {
    private func analysis(cobbles: Double = 0, busy: [String: Double] = [:], lanes: Double = 0, length: Double = 5000,
                          along: [(String, Double)] = [], unpaved: Double = 0, paths: Double = 0) -> RouteAnalysis {
        var a = RouteAnalysis()
        a.lengthM = length
        a.mix = [.cobbles: cobbles, .protected: lanes, .unpaved: unpaved, .quiet: max(0, length - cobbles - lanes - unpaved)]
        a.busyByName = busy
        a.pathMeters = paths
        a.hazards = along.map { RouteHazard(type: .along, distanceAlong: 0, lengthM: $0.1, street: $0.0, detail: "", osm: "w1") }
        a.hazards += cobbles > 0 ? [RouteHazard(type: .cobbles, distanceAlong: 0, lengthM: cobbles, street: "Via Morgagni", detail: "", osm: "w2")] : []
        return a
    }

    @Test func matchesTheDesignExample() {
        let best = analysis()
        let fastest = analysis(cobbles: 300, busy: ["Corso Buenos Aires": 800])
        let line = DifferenceCopy.line(best: best, bestSeconds: 23 * 60, fastest: fastest, fastestSeconds: 18 * 60,
                                       rules: .defaults(for: .city))
        #expect(line == "+5 min · avoids 300 m cobbles and busy Corso Buenos Aires")
        let fast = DifferenceCopy.fastestLine(best: best, bestSeconds: 23 * 60, fastest: fastest, fastestSeconds: 18 * 60,
                                              rideType: .city)
        #expect(fast == "5 min quicker · 300 m cobbles on Via Morgagni, busy Corso Buenos Aires")
    }

    @Test func longBusyRoadsGiveTheDistance() {
        let line = DifferenceCopy.line(best: analysis(), bestSeconds: 52 * 60,
                                       fastest: analysis(busy: ["Viale Fulvio Testi": 3600]), fastestSeconds: 45 * 60,
                                       rules: .defaults(for: .city))
        #expect(line == "+7 min · avoids 3.6 km on busy Viale Fulvio Testi")
    }

    @Test func allLanesSaysSo() {
        let line = DifferenceCopy.line(best: analysis(lanes: 4800), bestSeconds: 30 * 60, fastest: analysis(cobbles: 300),
                                       fastestSeconds: 21 * 60, rules: .defaults(for: .cargo))
        #expect(line == "+9 min · bike lanes all the way, no steps, no cobbles")
    }

    @Test func gravelTalksAboutWhatItGains() {
        let line = DifferenceCopy.line(best: analysis(unpaved: 2100, paths: 900), bestSeconds: 40 * 60,
                                       fastest: analysis(), fastestSeconds: 34 * 60, rules: .defaults(for: .gravel))
        #expect(line == "+6 min · 2.1 km more off-road and 900 m of park path")
    }

    @Test func singleCardFollowsTheDesign() {
        #expect(DifferenceCopy.showsSingleCard(bestSeconds: 780, fastestSeconds: 750, sameRoute: false))
        #expect(!DifferenceCopy.showsSingleCard(bestSeconds: 780, fastestSeconds: 700, sameRoute: false))
        let line = DifferenceCopy.singleCardLine(best: analysis(), bestSeconds: 780,
                                                 fastest: analysis(along: [("Corso Buenos Aires", 200)]),
                                                 fastestSeconds: 750, rideType: .city)
        #expect(line == "Fastest is only 30 s quicker, with rails along Corso Buenos Aires. So there’s one route.")
    }

    @Test func litLine() {
        #expect(DifferenceCopy.litLine(unlitPathsAvoided: 2, extraSeconds: 110) == "Lit streets only: avoids 2 dark park paths, +2 min")
    }

    @Test func distances() {
        #expect(DifferenceCopy.distance(296) == "300 m")
        #expect(DifferenceCopy.distance(3600) == "3.6 km")
        #expect(DifferenceCopy.distance(2000) == "2 km")
    }
}

struct ProfileAdjustmentTests {
    private func avoid(_ p: RideProfile) -> Double? {
        if case let .number(v) = p.best.costingOptions["avoid_bad_surfaces"] { v } else { nil }
    }

    @Test func rulesSetHowHardBadSurfacesAreAvoided() throws {
        let city = try RideProfile.load(.city)
        #expect(avoid(city.adjusted(for: .defaults(for: .city))) == 0.8)
        var noCobbleRule = RuleSet.defaults(for: .city)
        noCobbleRule.enabled.remove(.noCobbles)
        #expect(avoid(city.adjusted(for: noCobbleRule)) == 0.3)
        #expect(avoid(try RideProfile.load(.road).adjusted(for: .defaults(for: .road))) == 1.0)
        #expect(avoid(try RideProfile.load(.gravel).adjusted(for: .defaults(for: .gravel))) == 0.0)
        #expect(avoid(try RideProfile.load(.cargo).adjusted(for: .defaults(for: .cargo))) == 1.0)
    }
}

struct AvoidedRoadTests {
    @Test func tagsRoadsFastestUsesAndBestDoesNot() {
        let (shape, edges) = eastwardRoute([(1, edge()), (2, edge(road: "primary", name: "Viale Piave")),
                                            (3, edge(road: "primary", name: "Viale Piave")), (4, edge(name: "Via Morgagni"))])
        let source = FakeHazards(lines: [FakeHazards.line(.along, way: 2, length: 100), FakeHazards.line(.cobbles, way: 4, length: 100)])
        let fastest = RouteAnalyzer.analyze(shape: shape, edges: edges, hazards: source)
        var best = RouteAnalysis()
        best.metersByWay = [1: 100]
        let avoided = RoutePlanner.avoidedRoads(best: best, fastest: fastest, rideType: .city)
        #expect(avoided.map(\.name) == ["Viale Piave", "Via Morgagni"])
        #expect(avoided.first?.reason == "Rails along lane")
        #expect(avoided.last?.reason == "Cobbles 100 m")
    }
}
