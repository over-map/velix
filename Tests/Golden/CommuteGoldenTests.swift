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
}
