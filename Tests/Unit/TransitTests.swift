import CoreLocation
import Foundation
import Testing
@testable import Velix

/// Recorded Transitous answers (`Fixtures/transitous-*.json`, 26 Nov 2026, for Thursday 3 Dec 2026): Porta Venezia →
/// Villa Reale (Monza) at 08:05, Marienplatz → Freising and Amsterdam Centraal → Haarlem at 10:05 and at 08:05 (rush
/// hour, when the S-Bahn München and NS take no bikes).
enum TransitFixture {
    static let rome = TimeZone(identifier: "Europe/Rome")!
    static let portaVenezia = LatLon(lat: 45.4746, lon: 9.2050)
    static let villaReale = LatLon(lat: 45.5885, lon: 9.2740)
    static let marienplatz = LatLon(lat: 48.1374, lon: 11.5755)
    static let freising = LatLon(lat: 48.4029, lon: 11.7488)
    static let amsterdam = LatLon(lat: 52.3791, lon: 4.9003)
    static let haarlem = LatLon(lat: 52.3812, lon: 4.6366)

    /// Thursday 3 Dec 2026 at hh:mm, in `zone` (Rome by default).
    static func thursday(_ h: Int, _ m: Int, _ zone: String = "Europe/Rome") -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        return c.date(from: DateComponents(year: 2026, month: 12, day: 3, hour: h, minute: m))!
    }

    private final class Token {}

    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle(for: Token.self).url(forResource: "transitous-\(name)", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    static func runs(_ name: String) throws -> [TransitConnection] { try TransitousSource.connections(plan: data("plan-\(name)")) }
}

struct TransitousDecodingTests {
    @Test func monzaRunsFromThePlan() throws {
        let runs = try TransitFixture.runs("monza")
        #expect(runs.count == 11)
        let re8 = try #require(runs.first)
        #expect(re8.departure.name == "Trenord RE8 2816")
        #expect(re8.departure.board.name == "Milano Centrale" && re8.departure.alight.name == "Monza")
        #expect(re8.departure.departs == TransitFixture.thursday(8, 20))
        #expect(re8.departure.scheduledDeparts == TransitFixture.thursday(8, 20) && !re8.departure.realTime)
        #expect(re8.departure.timeZone.identifier == "Europe/Rome" && re8.departure.inItaly)
        #expect(re8.departure.route.mode == .rail && re8.departure.route.color == "e40314")
        #expect(re8.stops.count == 2 && re8.stops.first?.departs == re8.departure.departs)
        #expect(re8.line.count > 10)                                   // precision 6, the track to Monza
        #expect(abs(re8.line.first!.lat - re8.departure.board.location.lat) < 0.01)
        #expect(!re8.feedAllowsBikes)                                  // Transitous: Italian trains "bikes: false"
        let s8 = runs[1]
        #expect(s8.departure.route.shortName == "S8" && s8.stops.count == 4)   // two calls between Garibaldi and Monza
    }

    @Test func munichAndAmsterdam() throws {
        let munich = try #require(try TransitFixture.runs("munich").first)
        #expect(munich.departure.route.shortName == "S1" && munich.departure.board.name == "Marienplatz")
        #expect(munich.departure.timeZone.identifier == "Europe/Berlin" && !munich.departure.inItaly)
        #expect(munich.departure.route.operatorLabel == "DB Regio")
        let ns = try #require(try TransitFixture.runs("amsterdam").first)
        #expect(ns.departure.route.operatorName == "NS" && ns.feedAllowsBikes)
        #expect(TransitCopy.clock(ns.departure.departs, ns.departure.timeZone) == "10:11")
    }

    @Test func polylineAtItsPrecision() {
        // Google's example, precision 5.
        let p = Polyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@", precision: 5)
        #expect(p.count == 3)
        #expect(abs(p[0].lat - 38.5) < 1e-6 && abs(p[0].lon + 120.2) < 1e-6)
        #expect(abs(p[2].lat - 43.252) < 1e-6 && abs(p[2].lon + 126.453) < 1e-6)
    }

    @Test func theQueryAsksForDirectRunsWithABikeAtEachEnd() {
        let q = Dictionary(uniqueKeysWithValues: TransitousSource.planQuery(from: TransitFixture.portaVenezia, to: TransitFixture.villaReale,
                                                                             at: TransitFixture.thursday(8, 5)).map { ($0.name, $0.value ?? "") })
        #expect(q["maxTransfers"] == "0" && q["preTransitModes"] == "BIKE" && q["postTransitModes"] == "BIKE")
        #expect(q["transitModes"] == "RAIL,SUBURBAN,SUBWAY" && q["time"] == "2026-12-03T07:05:00Z")
        #expect(TransitousSource.userAgent.hasPrefix("Velix/") && TransitousSource.userAgent.contains("github.com/over-map/velix"))
    }

    @Test func aRefreshedRunTakesItsLiveTimes() throws {
        let re8 = try #require(try TransitFixture.runs("monza").first).departure
        let fresh = try #require(try TransitousSource.refreshed(re8, trip: TransitFixture.data("trip-monza")))
        #expect(fresh.departs == re8.departs && fresh.arrives == re8.arrives && fresh.trip == re8.trip)
        // A run that no longer calls at the boarding stop is gone.
        let elsewhere = TransitDeparture(trip: re8.trip, route: re8.route, tripName: nil, headsign: nil,
                                         board: TransitStop(id: "nowhere", feed: "trenord", name: "X", location: re8.board.location),
                                         alight: re8.alight, departs: re8.departs, arrives: re8.arrives, boardSeq: 0, alightSeq: 1)
        #expect(try TransitousSource.refreshed(elsewhere, trip: TransitFixture.data("trip-monza")) == nil)
    }
}

struct TransitOnlineTests {
    @Test func onlyOnlineAndFromFiveKilometres() {
        #expect(RouteOptionsModel.asksTransit(online: true, bikeMeters: 18_800))
        #expect(!RouteOptionsModel.asksTransit(online: false, bikeMeters: 18_800))
        #expect(!RouteOptionsModel.asksTransit(online: true, bikeMeters: 4_900))
    }

    @Test func offlineGivesNoPlan() async throws {
        let source = FixedTransitSource(connections: try TransitFixture.runs("monza"), offline: true)
        await #expect(throws: TransitSourceError.offline) {
            try await source.connections(from: TransitFixture.portaVenezia, to: TransitFixture.villaReale, at: TransitFixture.thursday(8, 5))
        }
    }
}

struct BikeRulesTests {
    let rules = BikeRules.bundled

    @Test func theBundledRules() throws {
        #expect(rules.entries.count == 7)
        let runs = try TransitFixture.runs("monza")
        let trenord = rules.rule(for: runs[0].departure)
        #expect(trenord.status == .check && trenord.offered)          // Trenord "check": offered (23 Oct)
        #expect(trenord.carriage == "Carriage with the bike area")
        var m1 = TransitRoute(id: "atm:1", feed: "atm", shortName: "M1", longName: "", mode: .metro, color: nil)
        m1.operatorName = "ATM"
        let d = TransitDeparture(trip: "m1", route: m1, tripName: nil, headsign: nil, board: runs[0].departure.board,
                                 alight: runs[0].departure.alight, departs: TransitFixture.thursday(8, 10),
                                 arrives: TransitFixture.thursday(8, 24), boardSeq: 0, alightSeq: 1)
        #expect(rules.rule(for: d).status == .allowed)
        #expect(rules.rule(for: d).carriage?.hasPrefix("2nd or 5th carriage") == true)
    }

    @Test func rushHourKeepsBikesOffTheSBahnAndNS() throws {
        let sbahnRush = try TransitFixture.runs("munich-rush").filter {
            $0.departure.route.shortName == "S1" && $0.departure.departs < TransitFixture.thursday(9, 0, "Europe/Berlin")
        }
        #expect(!sbahnRush.isEmpty && sbahnRush.allSatisfy { !rules.rule(for: $0.departure).offered })
        let sbahn = try TransitFixture.runs("munich").filter { $0.departure.route.shortName == "S1" }
        #expect(sbahn.allSatisfy { rules.rule(for: $0.departure).status == .check })
        let nsRush = try TransitFixture.runs("amsterdam-rush").filter { $0.departure.departs < TransitFixture.thursday(9, 0, "Europe/Amsterdam") }
        #expect(!nsRush.isEmpty && nsRush.allSatisfy { !rules.rule(for: $0.departure, feedAllowsBikes: $0.feedAllowsBikes).offered })
        // Off peak the feed's own flag (the Netherlands) means allowed.
        let ns = try TransitFixture.runs("amsterdam")
        #expect(ns.allSatisfy { rules.rule(for: $0.departure, feedAllowsBikes: $0.feedAllowsBikes).status == .allowed })
    }

    @Test func noRuleAndNoFlagIsCheck() {
        let route = TransitRoute(id: "x", feed: "other", shortName: "R1", longName: "", mode: .rail, color: nil)
        let stop = TransitStop(id: "a", feed: "other", name: "A", location: TransitFixture.portaVenezia)
        let d = TransitDeparture(trip: "t", route: route, tripName: nil, headsign: nil, board: stop, alight: stop,
                                 departs: TransitFixture.thursday(12, 0), arrives: TransitFixture.thursday(12, 30), boardSeq: 0, alightSeq: 1)
        #expect(rules.rule(for: d).status == .check)
        #expect(rules.rule(for: d, feedAllowsBikes: true).status == .allowed)
    }
}

struct DirectPlannerTests {
    let rules = BikeRules.bundled

    @Test func monzaTakesTheFirstCatchableTrainWithBikes() throws {
        let runs = try TransitFixture.runs("monza")
        let c = DirectPlanner.candidates(runs, rules: rules, from: TransitFixture.portaVenezia, to: TransitFixture.villaReale,
                                         at: TransitFixture.thursday(8, 5))
        let first = try #require(c.first)
        #expect(first.departure.alight.name == "Monza")
        #expect(first.departure.departs >= TransitFixture.thursday(8, 5).addingTimeInterval(first.rideIn + 3 * 60))
        #expect(c.map(\.arrival) == c.map(\.arrival).sorted())
        // Ten minutes later the 08:20 RE8 can't be caught.
        let late = DirectPlanner.candidates(runs, rules: rules, from: TransitFixture.portaVenezia, to: TransitFixture.villaReale,
                                            at: TransitFixture.thursday(8, 14))
        #expect(!late.contains { $0.departure.departs == TransitFixture.thursday(8, 20) && $0.departure.route.shortName == "RE8" })
    }

    @Test func rushHourLeavesNoTrainInAmsterdam() throws {
        let rush = DirectPlanner.candidates(try TransitFixture.runs("amsterdam-rush"), rules: rules, from: TransitFixture.amsterdam,
                                            to: TransitFixture.haarlem, at: TransitFixture.thursday(8, 5, "Europe/Amsterdam"))
        #expect(rush.allSatisfy { $0.departure.departs >= TransitFixture.thursday(9, 0, "Europe/Amsterdam") })
        let calm = DirectPlanner.candidates(try TransitFixture.runs("amsterdam"), rules: rules, from: TransitFixture.amsterdam,
                                            to: TransitFixture.haarlem, at: TransitFixture.thursday(10, 5, "Europe/Amsterdam"))
        #expect(calm.first?.departure.alight.name == "Haarlem")
    }

    @Test func nextTrainsOfThePair() throws {
        let runs = try TransitFixture.runs("munich")
        let first = try #require(DirectPlanner.candidates(runs, rules: rules, from: TransitFixture.marienplatz, to: TransitFixture.freising,
                                                          at: TransitFixture.thursday(10, 5, "Europe/Berlin")).first)
        let next = DirectPlanner.later(runs, rules: rules, than: first.departure, count: 2)
        #expect(next.count == 2)
        #expect(next.allSatisfy { $0.departure.board.id == first.departure.board.id && $0.departure.departs > first.departure.departs })
        #expect(next[0].departure.departs.timeIntervalSince(first.departure.departs) == 20 * 60)   // the S1 every 20 min
    }

    @Test func theLineIsCutAtEachStop() throws {
        let s8 = try TransitFixture.runs("monza")[1]
        let hops = DirectPlanner.hops(s8.line, stops: s8.stops)
        #expect(hops.count == s8.stops.count - 1 && hops.allSatisfy { $0 != nil })
        for (h, pair) in zip(hops, zip(s8.stops, s8.stops.dropFirst())) {
            #expect(Geo.distance(h!.last!, pair.1.stop.location) < 300)
            #expect(Geo.distance(h!.first!, pair.0.stop.location) < 300)
        }
        #expect(DirectPlanner.hops([], stops: s8.stops).allSatisfy { $0 == nil })
    }
}

@MainActor
struct TransitLiveTests {
    @Test func aDelayMovesThePlanAndACancellationMissesIt() throws {
        let p = try #require(AppSamples.monzaTransit().first)
        #expect(TransitRide.live(p.departure, for: p) == .same)
        let late = p.departure.moved(departs: p.departure.departs.addingTimeInterval(5 * 60),
                                     arrives: p.departure.arrives.addingTimeInterval(4 * 60), realTime: true)
        guard case let .moved(m) = TransitRide.live(late, for: p) else { Issue.record("not moved"); return }
        let moved = p.moved(m)
        #expect(moved.departure.departs == late.departs && moved.departure.realTime)
        #expect(moved.stops.first?.departs == late.departs && moved.stops.last?.arrives == late.arrives)
        #expect(moved.arrival == p.arrival.addingTimeInterval(4 * 60))
        #expect(TransitCopy.footnote(moved) == "Live · Transitous")
        #expect(TransitCopy.footnote(p) == "Timetable · Transitous")
        #expect(TransitRide.live(nil, for: p) == .cancelled)
        // Under a minute is noise.
        let ontime = p.departure.moved(departs: p.departure.departs.addingTimeInterval(30), arrives: p.departure.arrives, realTime: true)
        #expect(TransitRide.live(ontime, for: p) == .same)
    }

    @Test func aMissedTrainTakesTheNextRunOfThePair() throws {
        let runs = try TransitFixture.runs("munich")
        let p0 = try #require(AppSamples.monzaTransit().first)
        let first = TransitPlanner.plan(runs[0], rules: .bundled, rideIn: p0.rideIn, rideOut: p0.rideOut,
                                        planned: TransitFixture.thursday(10, 5, "Europe/Berlin"), runs: runs)
        let next = try #require(TransitRide.next(after: first, rules: .bundled))
        #expect(next.departure.departs == first.departure.departs.addingTimeInterval(20 * 60))
        #expect(next.track.count == next.stops.count - 1)
    }
}

struct TransitTriggerTests {
    private func shows(_ bikeMin: Double, _ km: Double, _ transitMin: Double, climb: Double = 0, outside: Bool = false) -> Bool {
        TransitTrigger.shows(bike: .init(seconds: bikeMin * 60, meters: km * 1000, climb: climb), transitSeconds: transitMin * 60,
                             transitClimb: 0, destinationOutsideCity: outside)
    }

    @Test func anyTriggerNeverUnderFiveKilometres() {
        #expect(shows(52, 14, 31))                 // P4 S3d: 21 min faster
        #expect(!shows(30, 4.9, 5))                // never under 5 km
        #expect(shows(30, 8, 20))                  // 33 % faster
        #expect(!shows(30, 8, 23))                 // 7 min, 23 %
        #expect(shows(50, 11, 39))                 // over 45 min and 11 min faster
        #expect(!shows(40, 11, 31))                // 9 min, 22 %, under 45 min and 12 km
        #expect(shows(30, 8, 28, climb: 220))      // avoids 220 m of climbing
        #expect(shows(30, 8, 29, outside: true))   // destination outside the city
        #expect(!shows(30, 8, 31, outside: true))  // never when it's slower
        #expect(!shows(38, 8.1, -449))             // a broken run (times going backwards) never shows (8 Nov)
    }

    @Test func cityAreaContains() {
        let square = CityArea(rings: [[LatLon(lat: 45.40, lon: 9.10), LatLon(lat: 45.40, lon: 9.30), LatLon(lat: 45.55, lon: 9.30),
                                       LatLon(lat: 45.55, lon: 9.10)]])
        #expect(square.contains(TransitFixture.portaVenezia))
        #expect(!square.contains(TransitFixture.villaReale))
    }
}

@MainActor
struct TransitCopyTests {
    @Test func theP4StringsFromAPlan() throws {
        let p = try #require(AppSamples.monzaTransit().first)
        let dest = AppSamples.villaReale
        #expect(TransitCopy.rowTitle(p) == "Long ride? Hop on the train with your bike")
        #expect(TransitCopy.rowSubtitle(p, bikeSeconds: 52 * 60, destination: dest)
                == "**21 min faster** · ride to Centrale, train to Monza, ride into the park")
        #expect(TransitCopy.cardSubtitle(p) == "13 min by bike · arrive 08:36")
        #expect(TransitCopy.trainLine(p) == "Trenord R 10834 · 08:16 → Monza 08:27")
        #expect(TransitCopy.detail(p, destination: dest)
                == "Ride 7 min to Centrale · platform planned: check the board · bikes allowed · ride 6 min into the park")
        #expect(TransitCopy.bikeOnly(best: 52 * 60, fastest: 45 * 60) == "Bike only · **52 min** Best · 45 min Fastest")
        #expect(TransitCopy.segments(p).map(\.label) == ["Ride 7", "Train 11", "Ride 6"])               // bike and train only
        #expect(TransitCopy.ticket(p)?.label == "Ticket · Trenitalia app")
        #expect(TransitCopy.ticket(p)?.app?.scheme == "trenitalia")
        #expect(TransitCopy.minutes(p.seconds) == 31)
    }

    @Test func theModelOffersTheCardAndTheNextTrains() throws {
        let m = RouteOptionsModel(destination: AppSamples.villaReale, state: .options(AppSamples.monzaOptions()),
                                  transit: AppSamples.monzaTransit())
        #expect(m.transitRow?.title == "Long ride? Hop on the train with your bike")
        m.transitSelected = true
        #expect(m.transitCard?.departures == ["08:16", "08:46", "09:16"])
        m.departureIndex = 1
        #expect(m.transitCard?.train == "Trenord R 10838 · 08:46 → Monza 08:57")
        #expect(m.mapRoute?.legs.first?.line.count == 3)
        #expect(m.mapRoute?.rides.count == 1)
    }

    /// Back on S3e returns to the bike routes (S3d); a second Back leaves route options.
    @Test func backFromTheTransitCardShowsTheBikeRoutes() {
        let m = RouteOptionsModel(destination: AppSamples.villaReale, state: .options(AppSamples.monzaOptions()),
                                  transit: AppSamples.monzaTransit())
        m.transitSelected = true
        #expect(m.back())
        #expect(!m.transitSelected)
        #expect(m.transitRow != nil)
        #expect(!m.back())
    }
}

struct TrainCatchTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }
    private var departs: Date { at(10 * 60) }     // the train leaves 10 min from now; boarding 3 min

    @Test func paceMakesASlowRiderLateEarlier() {
        #expect(TrainCatch.eta(remaining: 300, riddenFor: 30, plannedForRidden: 20) == 300)       // too soon to tell
        #expect(TrainCatch.eta(remaining: 300, riddenFor: 180, plannedForRidden: 120) == 450)     // 1.5× slower
        #expect(TrainCatch.eta(remaining: 300, riddenFor: 100, plannedForRidden: 200) == 300)     // faster: never optimistic
        #expect(TrainCatch.eta(remaining: 300, riddenFor: 900, plannedForRidden: 100) == 600)     // at most twice
        #expect(TrainCatch.spare(departs: departs, now: t0, eta: 360, boarding: 180) == 60)
    }

    @Test func lateSwitchesToFastestAfterTwoFixes() {
        var c = TrainCatch()
        // ETA 7.5 min + 3 boarding = 0.5 min late on Best; Fastest 6 min makes it.
        #expect(c.evaluate(now: t0, departs: departs, boarding: 180, eta: 450, bestETA: 450, fastestETA: 360) == .none)
        #expect(c.evaluate(now: at(1), departs: departs, boarding: 180, eta: 449, bestETA: 449, fastestETA: 359) == .switchToFastest)
        #expect(c.onFastest)
    }

    @Test func missedWhenEvenFastestIsLateThenBackToBest() {
        var c = TrainCatch()
        _ = c.evaluate(now: t0, departs: departs, boarding: 180, eta: 600, bestETA: 600, fastestETA: 500)
        #expect(c.evaluate(now: at(1), departs: departs, boarding: 180, eta: 600, bestETA: 600, fastestETA: 500) == .nextTrain)
        // The next train leaves in 30 min: plenty of time, but the coordinator only goes back to Best from Fastest.
        #expect(!c.onFastest)
        let later = at(30 * 60)
        #expect(c.evaluate(now: at(40), departs: later, boarding: 180, eta: 600, bestETA: 600, fastestETA: 500) == .none)
    }

    @Test func backToBestOnceThereIsTimeAgain() {
        var c = TrainCatch()
        _ = c.evaluate(now: t0, departs: departs, boarding: 180, eta: 450, bestETA: 450, fastestETA: 360)
        _ = c.evaluate(now: at(1), departs: departs, boarding: 180, eta: 449, bestETA: 449, fastestETA: 359)
        #expect(c.onFastest)
        // Missed anyway on Fastest: next train, still on Fastest.
        _ = c.evaluate(now: at(40), departs: departs, boarding: 180, eta: 500, bestETA: 560, fastestETA: 500)
        #expect(c.evaluate(now: at(41), departs: departs, boarding: 180, eta: 500, bestETA: 560, fastestETA: 500) == .nextTrain)
        #expect(c.onFastest)
        // The 30-min-later train: Best leaves 20 min spare: back to Best after 2 fixes and 30 s.
        let next = at(41 + 30 * 60)
        #expect(c.evaluate(now: at(50), departs: next, boarding: 180, eta: 400, bestETA: 500, fastestETA: 400) == .none)
        #expect(c.evaluate(now: at(72), departs: next, boarding: 180, eta: 400, bestETA: 500, fastestETA: 400) == .backToBest)
        #expect(!c.onFastest)
    }

    @Test func oneLateFixIsNotEnough() {
        var c = TrainCatch()
        _ = c.evaluate(now: t0, departs: departs, boarding: 180, eta: 450, bestETA: 450, fastestETA: 360)
        #expect(c.evaluate(now: at(1), departs: departs, boarding: 180, eta: 300, bestETA: 300, fastestETA: 250) == .none)
    }
}

@MainActor
struct RidingWithTransitCopyTests {
    @Test func lateAndMissedNameTheCost() throws {
        let plans = AppSamples.monzaTransit()
        let p = try #require(plans.first)
        var best = RouteAnalysis(), fastest = RouteAnalysis()
        best.mix = [.quiet: 2000]
        fastest.mix = [.quiet: 1800, .cobbles: 120]
        #expect(TransitCopy.lateCost(best: best, fastest: fastest) == "120 m of cobbles")
        let late = TransitCopy.late(p.departure, cost: "120 m of cobbles")
        #expect(late.message == "Switched to the fastest route to catch the 08:16. It adds 120 m of cobbles.")   // P6 S5b
        #expect(late.short == "Fastest route to catch the 08:16. +120 m cobbles.")                                // P6 D7
        let missed = TransitCopy.missed(p.departure, next: plans[1])
        #expect(missed.title == "You’d miss the 08:16")
        #expect(missed.message == "Moved you to the 08:46. Arrival 09:06.")
    }

    @Test func theStationEtaCountsTheSpareTime() throws {
        let p = try #require(AppSamples.monzaTransit().first)
        let now = AppClock.parse("2026-10-22T08:05", today: Date())!
        // Ride 7 min: at Centrale 08:12, train 08:16, boarding 3 → 1 min to spare, tight.
        #expect(TransitCopy.stationEta(p, now: now, eta: 7 * 60)
                == .transit(arrival: "08:12", at: "Centrale", train: "08:16 ·", spare: "1 min to spare", tight: true))
        #expect(TransitCopy.stationEta(p, now: now, eta: 10 * 60)
                == .transit(arrival: "08:15", at: "Centrale", train: "08:16 ·", spare: "Late", tight: true))
    }

    @Test func onTheTrainCountsDownToTheStop() throws {
        let p = try #require(AppSamples.monzaTransit().first)
        let card = TransitCopy.onTrain(p, now: AppClock.parse("2026-10-22T08:21", today: Date())!, destination: AppSamples.villaReale)
        #expect(card.train == "Trenord R 10834 to Monza")
        #expect(card.minutes == 6)
        #expect(card.stopsLeft == "1 stop before yours")                    // P6 S5d: Sesto still to come
        #expect(card.stops.map(\.state) == [.departed, .next, .end])
        #expect(card.carriages == nil && card.carriageNote == "Carriage with the bike area")
        let early = TransitCopy.onTrain(p, now: AppClock.parse("2026-10-22T08:13", today: Date())!, destination: AppSamples.villaReale)
        #expect(early.stopsLeft == "Leaves at 08:16")
        let m1 = TransitRoute(id: "atm:M1", feed: "atm", shortName: "M1", longName: "", mode: .metro, color: "E1001B")
        #expect(BikeCarriages.positions(m1) == [false, true, false, false, true, false])
        #expect(BikeCarriages.note([false, true, false, false, true, false]) == "Bikes in the 2nd and 5th carriage")
    }

    /// Transitous names the operator; outside Italy the ticket link is the operator's site, none when it has none.
    @Test func theOperatorAndTicketComeFromTransitous() throws {
        var reg = TransitRoute(id: "trenitalia:REG", feed: "trenitalia", shortName: "REG", longName: "Regionale", mode: .rail, color: nil)
        #expect(reg.operatorLabel == "Trenord")
        reg.operatorName = "Trenitalia"
        #expect(reg.operatorLabel == "Trenitalia")
        #expect(TransitNames.displayName("TORINO PORTA NUOVA") == "Torino Porta Nuova")
        #expect(TransitNames.displayName("CENTRALE FS") == "Centrale FS")
        #expect(TransitNames.displayName("P.TA VENEZIA") == "P.ta Venezia")
        #expect(TransitNames.displayName("Milano Centrale") == "Milano Centrale")
        #expect(TransitNames.trainNumber("RE_80 - 25510") == "25510" && TransitNames.trainNumber("") == nil)
        #expect(TransitNames.metroLine("1") == "M1" && TransitNames.metroLine("U3") == "U3")
        var gtt = TransitRoute(id: "gtt:M1", feed: "gtt", shortName: "M1", longName: "", mode: .metro, color: nil)
        gtt.operatorName = "GTT"
        #expect(BikeCarriages.positions(gtt) == nil)
        let p0 = try #require(AppSamples.monzaTransit().first)
        let ns = try #require(try TransitFixture.runs("amsterdam").first)
        let nsPlan = TransitPlan(rideIn: p0.rideIn, departure: ns.departure, rule: p0.rule, stops: ns.stops, rideOut: p0.rideOut, planned: p0.planned)
        #expect(TransitCopy.ticket(nsPlan) == .init(label: "Ticket · NS", app: nil, fallback: URL(string: "http://www.ns.nl")!))
        let munich = try #require(try TransitFixture.runs("munich").first)
        let mPlan = TransitPlan(rideIn: p0.rideIn, departure: munich.departure, rule: p0.rule, stops: munich.stops, rideOut: p0.rideOut,
                                planned: p0.planned)
        #expect(TransitCopy.ticket(mPlan) == nil)                               // the feed has no operator site
        #expect(TransitCopy.trainLine(mPlan).contains("→ Freising"))
    }
}

struct TrainStretchLogTests {
    @Test func theTrainIsLoggedButNotRidden() throws {
        let log = RideLog(directory: FileManager.default.temporaryDirectory.appending(path: "velix-log-\(UUID().uuidString)"))
        let t0 = Date()
        func fix(_ i: Int, _ lat: Double) -> CLLocation {
            CLLocation(coordinate: .init(latitude: lat, longitude: 9.2), altitude: 120, horizontalAccuracy: 5, verticalAccuracy: 5,
                       course: 0, speed: 5, timestamp: t0.addingTimeInterval(Double(i)))
        }
        log.fix(fix(0, 45.4800)); log.fix(fix(1, 45.48005))                 // riding: ≈ 5.6 m
        log.fix(fix(2, 45.5000), ridden: false); log.fix(fix(3, 45.5700), ridden: false)   // the train
        log.fix(fix(4, 45.5780)); log.fix(fix(5, 45.57805))                 // riding again: ≈ 5.6 m
        log.close()
        #expect(abs(log.stats.meters - 11.1) < 1)                         // not the 11 km between
        let gpx = try String(contentsOf: try log.gpx(name: "t"), encoding: .utf8)
        #expect(gpx.components(separatedBy: "<trkpt").count - 1 == 4)
    }
}

@MainActor
struct TransitLegLineTests {
    @Test func theLegFollowsTheTrackAndGapsOnlyJoinInOverviews() throws {
        var p = try #require(AppSamples.monzaTransit().first)
        let stops = p.stops.map(\.stop.location)
        try #require(stops.count >= 2)
        let mid = LatLon(lat: (stops[0].lat + stops[1].lat) / 2 + 0.002, lon: (stops[0].lon + stops[1].lon) / 2)
        // Known track for the first hop only.
        p.track = [[stops[0], mid, stops[1]]] + Array(repeating: nil, count: stops.count - 2)
        let overview = p.legLines(straightGaps: true)
        #expect(overview.count == 1)
        #expect(overview[0].contains(mid) && overview[0].last == stops.last)
        let riding = p.legLines(straightGaps: false)
        #expect(riding == [[stops[0], mid, stops[1]]])
        p.track = []
        #expect(p.legLines(straightGaps: false).isEmpty)
        #expect(MapRouteModel(transit: p, riding: true).legs.isEmpty)
        #expect(MapRouteModel(transit: p).legs.count == 1)
    }
}
