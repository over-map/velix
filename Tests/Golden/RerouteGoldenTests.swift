@preconcurrency import FerrostarCore
@preconcurrency import FerrostarCoreFFI
import Foundation
import Testing
@testable import Velix

/// M7: reroutes go through the planner, so they keep the ride type's rules (P5 S4g), unlike Ferrostar's bare
/// Valhalla request before.
@Suite(.enabled(if: GoldenPack.available, "Set TEST_RUNNER_VELIX_PACK_DIR to an unpacked region pack"), .serialized)
struct RerouteGoldenTests {
    @Test func aRerouteKeepsTheRules() async throws {
        let planner = try #require(GoldenPack.planner).get()
        let rules = RuleSet.defaults(for: .city)
        let provider = PlannedRouteProvider(planner: planner, rules: rules, choice: .best)
        // 120 m off the Porta Venezia → Politecnico route, heading east (the M1 detour fixture's off-route point).
        var here = UserLocation(clCoordinateLocation2D: .init(latitude: 45.4752, longitude: 9.2101))
        here.courseOverGround = CourseOverGround(degrees: 90, accuracy: 20)
        let to = Waypoint(coordinate: GeographicCoordinate(lat: AppSamples.politecnico.lat, lng: AppSamples.politecnico.lon), kind: .break)
        let t = Date()
        let routes = try await provider.getRoutes(userLocation: here, waypoints: [to])
        let ms = Date().timeIntervalSince(t) * 1000
        let option = try #require(provider.lastOption)
        #expect(routes.count == 1)
        #expect(abs((routes.first?.distance ?? 0) - option.meters) < 5)
        let hard = RuleChecker.hardViolations(RuleChecker.violations(of: rules.active, in: option.analysis), rideType: .city)
        #expect(hard.isEmpty, "reroute breaks \(hard.map(\.rule))")
        #expect(ms < 3000, "reroute took \(Int(ms)) ms")
    }

    @Test func aFastestRideReroutesOnTheFastest() async throws {
        let planner = try #require(GoldenPack.planner).get()
        let provider = PlannedRouteProvider(planner: planner, rules: .defaults(for: .city), choice: .fastest)
        let here = UserLocation(clCoordinateLocation2D: .init(latitude: 45.447767, longitude: 9.1963936))   // Via Soave
        let to = Waypoint(coordinate: GeographicCoordinate(lat: 45.4621338, lng: 9.194385), kind: .break)
        _ = try await provider.getRoutes(userLocation: here, waypoints: [to])
        let names = Set(try #require(provider.lastOption).analysis.edges.compactMap(\.name))
        #expect(names.contains("Via Giuseppe Ripamonti"))
    }
}
