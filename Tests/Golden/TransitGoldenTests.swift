import Foundation
import Testing
@testable import Velix

/// The M8 Monza scenario on the real pack: Porta Venezia → Villa Reale on a weekday morning suggests riding to a
/// Milan station, a Trenord train to Monza and riding into the park (P4 S3d). Runs: Transitous's recorded answer for
/// Thursday 3 Dec 2026 (`Tests/Unit/Fixtures`); bike legs: the pack.
@Suite(.enabled(if: GoldenPack.available, "Needs a region pack"), .serialized)
struct TransitGoldenTests {
    @Test func monzaSuggestsTheTrainToMonza() async throws {
        await GoldenPack.warmUp.value
        let planner = try #require(GoldenPack.planner).get()
        let from = AppSamples.portaVenezia, to = GoldenTrip.all[7].to
        let rules = RuleSet.defaults(for: .city)
        let now = TransitGolden.thursday(8, 5)

        guard case let .options(bike) = try await planner.plan(from: from, to: to, rules: rules) else {
            Issue.record("no bike route"); return
        }
        let transit = TransitPlanner(source: FixedTransitSource(connections: try TransitGolden.runs("monza")), planner: planner)
        var t0 = Date()
        let plan = try #require(await transit.plan(from: from, to: to, rules: rules, at: now))
        var ms = Date().timeIntervalSince(t0) * 1000
        // Like the 5 s route check (GoldenPack.bestTime): a slow plan is timed again, up to twice, and the fastest run
        // counts (CI took 12.7 s on 2 Nov for a plan the same pack makes in 1.4 s locally).
        for _ in 0..<2 where ms >= 4000 {
            t0 = Date()
            _ = await transit.plan(from: from, to: to, rules: rules, at: now)
            ms = min(ms, Date().timeIntervalSince(t0) * 1000)
        }

        #expect(plan.departure.route.mode == .rail)
        #expect(plan.departure.board.name.hasPrefix("Milano"))
        #expect(plan.departure.alight.name.hasPrefix("Monza"))
        #expect(plan.departure.departs >= now.addingTimeInterval(plan.rideIn.seconds))
        #expect(plan.stops.count >= 2)
        let outside = TransitGolden.city.map { !$0.contains(to) } ?? true
        #expect(TransitTrigger.shows(bike: .init(seconds: bike.best.seconds, meters: bike.best.meters, climb: bike.best.analysis.climbM),
                                     transit: plan, destinationOutsideCity: outside))
        #expect(ms < 4000, "transit plan took \(Int(ms)) ms")
        // The train is drawn on the rails: every hop of the run has its track, close to the straight distance.
        #expect(plan.track.count == plan.stops.count - 1 && plan.track.allSatisfy { $0 != nil })
        let rails = plan.track.compactMap { $0 }.reduce(0) { $0 + Geo.length($1) }
        let straight = Geo.distance(plan.departure.board.location, plan.departure.alight.location)
        #expect(rails > straight && rails < 1.6 * straight)
        print("Monza: \(plan.departure.name) \(plan.departure.departs) → \(plan.departure.alight.name), " +
              "\(Int(plan.seconds / 60)) min vs bike \(Int(bike.best.seconds / 60)) min, ride \(Int(plan.bikeSeconds / 60)) min, \(Int(ms)) ms")
    }

    /// 8 Nov: from south Milan no train was found at any time. Transitous finds the S9 from Scalo Romana.
    @Test func southMilanFindsATrainToMonza() async throws {
        await GoldenPack.warmUp.value
        let planner = try #require(GoldenPack.planner).get()
        let from = LatLon(lat: 45.448, lon: 9.196), to = GoldenTrip.all[7].to
        let rules = RuleSet.defaults(for: .city)
        let now = TransitGolden.thursday(8, 5)
        guard case let .options(bike) = try await planner.plan(from: from, to: to, rules: rules) else {
            Issue.record("no bike route"); return
        }
        let transit = TransitPlanner(source: FixedTransitSource(connections: try TransitGolden.runs("south-milan")), planner: planner)
        let plan = try #require(await transit.plan(from: from, to: to, rules: rules, at: now))
        #expect(plan.departure.route.mode == .rail)
        #expect(plan.departure.alight.name.hasPrefix("Monza"))
        let outside = TransitGolden.city.map { !$0.contains(to) } ?? true
        #expect(TransitTrigger.shows(bike: .init(seconds: bike.best.seconds, meters: bike.best.meters, climb: bike.best.analysis.climbM),
                                     transit: plan, destinationOutsideCity: outside))
        print("south Milan → Monza: \(plan.departure.name) from \(plan.departure.board.name) \(plan.departure.departs), " +
              "\(Int(plan.seconds / 60)) min vs bike \(Int(bike.best.seconds / 60)) min")
    }
}

/// The real Transitous API (M11 PR 4 acceptance: Monza, Munich and Amsterdam plan with a train). Opt-in, 3 requests:
/// `TEST_RUNNER_VELIX_TRANSITOUS=1`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["VELIX_TRANSITOUS"] == "1", "Set TEST_RUNNER_VELIX_TRANSITOUS=1"))
struct TransitousLiveTests {
    /// Next Thursday 10:05 local (outside the rush hours that keep bikes off the S-Bahn and NS).
    static func nextThursday(_ zone: String) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        var day = c.startOfDay(for: Date().addingTimeInterval(86_400))
        while c.component(.weekday, from: day) != 5 { day = c.date(byAdding: .day, value: 1, to: day)! }
        return c.date(bySettingHour: 10, minute: 5, second: 0, of: day)!
    }

    @Test(arguments: [("Monza", 45.4746, 9.2050, 45.5885, 9.2740, "Europe/Rome"),
                      ("Munich", 48.1374, 11.5755, 48.4029, 11.7488, "Europe/Berlin"),
                      ("Amsterdam", 52.3791, 4.9003, 52.3812, 4.6366, "Europe/Amsterdam")])
    func plansWithATrain(_ name: String, _ aLat: Double, _ aLon: Double, _ bLat: Double, _ bLon: Double, _ zone: String) async throws {
        let from = LatLon(lat: aLat, lon: aLon), to = LatLon(lat: bLat, lon: bLon), now = Self.nextThursday(zone)
        let runs = try await TransitousSource().connections(from: from, to: to, at: now)
        let c = DirectPlanner.candidates(runs, rules: .bundled, from: from, to: to, at: now)
        let first = try #require(c.first, "\(name): no direct run with bikes")
        #expect(first.departure.route.mode == .rail)
        print("\(name): \(first.departure.name) \(first.departure.board.name) → \(first.departure.alight.name) " +
              "\(TransitCopy.clock(first.departure.departs, first.departure.timeZone)), \(runs.count) runs")
    }
}

enum TransitGolden {
    /// h:m on Thursday 3 Dec 2026 (the recorded answers' day), Rome time.
    static func thursday(_ h: Int, _ m: Int) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c.date(from: DateComponents(year: 2026, month: 12, day: 3, hour: h, minute: m))!
    }

    /// A recorded Transitous answer from the unit tests' fixtures.
    static func runs(_ name: String) throws -> [TransitConnection] {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try TransitousSource.connections(plan: Data(contentsOf: repo.appending(path: "Tests/Unit/Fixtures/transitous-plan-\(name).json")))
    }

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
