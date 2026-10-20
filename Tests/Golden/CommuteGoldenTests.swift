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

    /// Filippo's trip: Via Soave 20 → Piazza Santo Stefano. With walking stretches on (City), Best is his own route
    /// (Patellani → Oriani → Giardino Oriana Fallaci → Quadronno → Via Gaetano Pini → Calimero → Sforza → Laghetto,
    /// 20 Oct); Fastest is its own card through Ripamonti and Porta Romana, walking stretches on or off.
    @Test func soaveToSantoStefano() async throws {
        let planner = try #require(GoldenPack.planner).get()
        let from = LatLon(lat: 45.447767, lon: 9.1963936), to = LatLon(lat: 45.4621338, lon: 9.194385)
        var walking = RuleSet.defaults(for: .city)
        walking.enabled.insert(.walkingStretches)
        guard case let .options(o) = try await planner.plan(from: from, to: to, rules: walking) else { Issue.record("no options"); return }
        let names = Set(o.best.analysis.edges.compactMap(\.name))
        #expect(names.isSuperset(of: ["Via Carlo Patellani", "Via Alfredo Oriani", "Via Gaetano Pini", "Via San Calimero", "Via Laghetto"]),
                "Best \(o.best.analysis.edges.compactMap(\.name))")
        #expect(!names.contains("Via Bianca di Savoia"))
        #expect(o.best.analysis.meters(.cobbles) < 40)
        for plan in [o, try await { () async throws -> RouteOptions? in
            if case let .options(d) = try await planner.plan(from: from, to: to, rules: .defaults(for: .city)) { return d }
            return nil
        }()].compactMap({ $0 }) {
            let fastest = try #require(plan.fastest, "Fastest must have its own card")
            let fastNames = Set(fastest.analysis.edges.compactMap(\.name))
            #expect(fastNames.isSuperset(of: ["Via Giuseppe Ripamonti", "Corso di Porta Romana"]))
            #expect(fastest.seconds < plan.best.seconds)
        }
    }
}
