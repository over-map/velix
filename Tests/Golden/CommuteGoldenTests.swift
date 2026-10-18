import FerrostarCoreFFI
import Foundation
import Testing
@testable import Velix

/// M6 acceptance, minus the phone: Work → route options (real plan) → the route Start rides is the planned one.
@Suite(.enabled(if: GoldenPack.available, "Set TEST_RUNNER_VELIX_PACK_DIR to an unpacked region pack"), .serialized)
@MainActor
struct CommuteGoldenTests {
    @Test func workThenStartRidesThePlannedBestRoute() async throws {
        let planner = try #require(GoldenPack.planner).get()
        let plan = try await planner.plan(from: AppSamples.portaVenezia, to: AppSamples.politecnico.location,
                                          rules: .defaults(for: .city))
        guard case let .options(options) = plan else { Issue.record("no options: \(plan)"); return }
        let model = RouteOptionsModel(destination: AppSamples.politecnico, state: .options(options))
        let chosen = try #require(model.chosen)
        #expect(chosen.osrmJSON == options.best.osrmJSON)          // Best is preselected: tap 2 is Start
        let route = try RideSession.route(from: chosen)
        #expect(abs(route.distance - chosen.meters) < 5)            // Ferrostar rides the same route, no re-plan
        #expect(!route.steps.isEmpty)
        #expect(route.geometry.count > 10)
    }

    /// Filippo's trip (18 Oct): Via Soave 20 → Piazza Santo Stefano. Before one-ways were ridden both ways City Best
    /// detoured 4.3 km east with 122 m of cobbles; the direct ways north are one-way (contraflow legal on the street).
    @Test func soaveToSantoStefanoStaysDirectAndSmooth() async throws {
        let planner = try #require(GoldenPack.planner).get()
        let plan = try await planner.plan(from: LatLon(lat: 45.447767, lon: 9.1963936), to: LatLon(lat: 45.4621338, lon: 9.194385),
                                          rules: .defaults(for: .city))
        guard case let .options(o) = plan else { Issue.record("no options: \(plan)"); return }
        #expect(o.best.meters < 3800, "City Best \(Int(o.best.meters)) m")
        #expect(o.best.analysis.meters(.cobbles) < 60, "cobbles \(Int(o.best.analysis.meters(.cobbles))) m")
        var strict = RuleSet.defaults(for: .city)
        strict.respectOneways = true
        guard case let .options(s) = try await planner.plan(from: LatLon(lat: 45.447767, lon: 9.1963936),
                                                            to: LatLon(lat: 45.4621338, lon: 9.194385), rules: strict) else { return }
        #expect(s.best.meters > o.best.meters)   // the setting makes a difference here
    }
}
