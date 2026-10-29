import Foundation
import Testing
@testable import Velix

/// The M8 Monza scenario on the real pack: Porta Venezia → Villa Reale on a weekday morning suggests riding to
/// Centrale, a Trenord train to Monza and riding into the park (P4 S3d; times from the pack, not P6's sample).
@Suite(.enabled(if: GoldenPack.available && TransitGolden.store != nil, "Needs a pack with transit.sqlite"), .serialized)
struct TransitGoldenTests {
    @Test func monzaSuggestsTheTrainToMonza() async throws {
        await GoldenPack.warmUp.value
        let planner = try #require(GoldenPack.planner).get()
        let store = try #require(TransitGolden.store)
        let from = AppSamples.portaVenezia, to = GoldenTrip.all[7].to
        let rules = RuleSet.defaults(for: .city)
        // A Thursday inside the pack's 60-day timetable window.
        let now = TransitGolden.rome(2026, 11, 5, 8, 5)

        guard case let .options(bike) = try await planner.plan(from: from, to: to, rules: rules) else {
            Issue.record("no bike route"); return
        }
        let t0 = Date()
        let plan = try #require(await TransitPlanner(store: store, planner: planner).plan(from: from, to: to, rules: rules, at: now))
        let ms = Date().timeIntervalSince(t0) * 1000

        #expect(plan.departure.route.mode == .rail)
        #expect(plan.departure.board.name == "Milano Centrale")
        #expect(plan.departure.alight.name.hasPrefix("Monza"))
        #expect(plan.departure.departs >= now.addingTimeInterval(plan.rideIn.seconds))
        #expect(plan.stops.count >= 2)
        let outside = TransitGolden.city.map { !$0.contains(to) } ?? true
        #expect(TransitTrigger.shows(bike: .init(seconds: bike.best.seconds, meters: bike.best.meters, climb: bike.best.analysis.climbM),
                                     transit: plan, destinationOutsideCity: outside))
        #expect(ms < 4000, "transit plan took \(Int(ms)) ms")
        print("Monza: \(plan.departure.name) \(plan.departure.departs) → \(plan.departure.alight.name), " +
              "\(Int(plan.seconds / 60)) min vs bike \(Int(bike.best.seconds / 60)) min, ride \(Int(plan.bikeSeconds / 60)) min, \(Int(ms)) ms")
    }
}

enum TransitGolden {
    static func rome(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ m: Int) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: m))!
    }

    static let store: TransitStore? = GoldenPack.directory.flatMap { try? TransitStore(path: $0.appending(path: "transit.sqlite")) }
    static let city: CityArea? = GoldenPack.directory.flatMap { try? Data(contentsOf: $0.appending(path: "city.geojson")) }
        .flatMap { try? CityArea(geoJSON: $0) }
}

/// M9 Routes on the real pack: the canals out of Milan are there, with their S7 mix.
@Suite(.enabled(if: RoutesGolden.store?.schema ?? 0 >= 2, "Needs a pack with routes.sqlite schema 2"))
struct RoutesGoldenTests {
    @Test func milanHasItsCanals() throws {
        let store = try #require(RoutesGolden.store)
        let milan = AppSamples.portaVenezia
        let routes = store.routes(in: Geo.bbox([milan], padding: 20_000), near: milan, limit: 200)
        let names = routes.map(\.name)
        #expect(names.contains { $0.contains("Naviglio Pavese") })
        #expect(names.contains { $0.contains("Martesana") })
        let pavese = try #require(routes.first { $0.name.contains("Naviglio Pavese") })
        #expect((pavese.mix?.unpaved ?? 1) < 0.1)
        #expect((pavese.climb ?? 999) < 60)
    }
}

enum RoutesGolden {
    static let store: RouteStore? = GoldenPack.directory.flatMap { try? RouteStore(path: $0.appending(path: "routes.sqlite")) }
}
