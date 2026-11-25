import Foundation
import Testing
@testable import Velix

/// A route built from legs (bearing in degrees, metres), one edge per leg, a shape point every 5 m.
func legsRoute(_ legs: [(bearing: Double, meters: Double)], edit: (Int, inout RouteEdge) -> Void = { _, _ in })
    -> (shape: [LatLon], edges: [RouteEdge]) {
    var shape = [LatLon(lat: 45.47, lon: 9.20)]
    var edges: [RouteEdge] = []
    for (i, leg) in legs.enumerated() {
        let begin = shape.count - 1
        let steps = max(1, Int((leg.meters / 5).rounded()))
        let r = leg.bearing * .pi / 180
        for _ in 0 ..< steps {
            let p = shape.last!
            let d = leg.meters / Double(steps)
            shape.append(LatLon(lat: p.lat + d * cos(r) / 111_320, lon: p.lon + d * sin(r) / (111_320 * cos(p.lat * .pi / 180))))
        }
        var e = RouteEdge(wayId: Int64(i + 1), lengthKm: leg.meters / 1000, beginShapeIndex: begin, endShapeIndex: shape.count - 1)
        edit(i, &e)
        edges.append(e)
    }
    return (shape, edges)
}

struct TurnCountTests {
    private func turns(_ legs: [(bearing: Double, meters: Double)]) -> Int {
        let (shape, edges) = legsRoute(legs)
        return RouteAnalyzer.analyze(shape: shape, edges: edges, hazards: FakeHazards()).turns
    }

    @Test func straightRouteHasNoTurns() {
        #expect(turns([(90, 200), (90, 200), (92, 300)]) == 0)
    }

    @Test func gentleBendIsNotATurn() {
        #expect(turns([(90, 200), (120, 200)]) == 0)
    }

    @Test func rightAngleIsOneTurn() {
        #expect(turns([(90, 200), (90, 200), (0, 200), (0, 200)]) == 1)
    }

    @Test func turnThroughAShortLinkCountsOnce() {
        #expect(turns([(90, 200), (45, 8), (0, 200)]) == 1)
    }

    @Test func zigZagCountsEveryTurn() {
        #expect(turns([(90, 150), (0, 150), (90, 150), (0, 150), (90, 150)]) == 4)
    }
}

struct RouteChoiceTests {
    @Test func busyMetresLeaveOutLanesAndQuietStreets() {
        let (shape, edges) = legsRoute([(90, 100), (90, 100), (90, 100), (90, 100)]) { i, e in
            e = RouteEdge(wayId: e.wayId, lengthKm: e.lengthKm, cycleLane: i == 1 ? "dedicated" : "none",
                          roadClass: i == 2 ? "residential" : (i == 3 ? "secondary" : "primary"),
                          speed: 50, beginShapeIndex: e.beginShapeIndex, endShapeIndex: e.endShapeIndex)
        }
        let a = RouteAnalyzer.analyze(shape: shape, edges: edges, hazards: FakeHazards())
        #expect(abs(a.busyMeters - 200) < 1)  // the lane-less primary and secondary; not the lane, not the residential
    }

    @Test func cityPrefersAMainRoadWithALaneOverAZigZag() {
        let lane = legsRoute([(0, 1000), (0, 1000)]) { _, e in
            e = RouteEdge(wayId: e.wayId, lengthKm: e.lengthKm, cycleLane: "dedicated", roadClass: "primary",
                          beginShapeIndex: e.beginShapeIndex, endShapeIndex: e.endShapeIndex)
        }
        let zig = legsRoute((0 ..< 10).map { (($0 % 2 == 0) ? 0 : 90, 200) })
        let a = RouteAnalyzer.analyze(shape: lane.shape, edges: lane.edges, hazards: FakeHazards())
        let b = RouteAnalyzer.analyze(shape: zig.shape, edges: zig.edges, hazards: FakeHazards())
        let rules = RuleSet.defaults(for: .city)
        #expect(RoutePlanner.score(seconds: 600, analysis: a, rules: rules) < RoutePlanner.score(seconds: 600, analysis: b, rules: rules))
    }

    @Test func cityStillWeighsLanelessMainRoadsLightly() {
        let busy = legsRoute([(0, 1000)]) { _, e in
            e = RouteEdge(wayId: e.wayId, lengthKm: e.lengthKm, roadClass: "primary",
                          beginShapeIndex: e.beginShapeIndex, endShapeIndex: e.endShapeIndex)
        }
        let a = RouteAnalyzer.analyze(shape: busy.shape, edges: busy.edges, hazards: FakeHazards())
        let rules = RuleSet.defaults(for: .city)
        let extra = RoutePlanner.score(seconds: 0, analysis: a, rules: rules)
        #expect(extra > 0)
        #expect(extra < 120)  // a lane-less kilometre is worth less than a 2-min detour
    }

    @Test func otherRideTypesScoreTimeAndRulesOnly() {
        let zig = legsRoute((0 ..< 10).map { (($0 % 2 == 0) ? 0 : 90, 200) })
        let a = RouteAnalyzer.analyze(shape: zig.shape, edges: zig.edges, hazards: FakeHazards())
        for type in RideType.allCases where type != .city {
            #expect(RoutePlanner.score(seconds: 600, analysis: a, rules: .defaults(for: type)) == 600)
        }
    }
}
