import Foundation
import SQLite3
import Testing
@testable import Velix

/// A small `transit.sqlite` in the pipeline's schema 1: the Monza trains of a weekday, a Sunday run, an M1 run and a
/// line that refuses bikes.
enum TransitFixture {
    static let rome = TimeZone(identifier: "Europe/Rome")!
    static let portaVenezia = LatLon(lat: 45.4746, lon: 9.2050)
    static let villaReale = LatLon(lat: 45.5885, lon: 9.2740)

    /// Thursday 22 Oct 2026 (weekday service) at hh:mm, Rome time.
    static func thursday(_ h: Int, _ m: Int) -> Date { date(2026, 10, 22, h, m) }
    static func sunday(_ h: Int, _ m: Int) -> Date { date(2026, 10, 25, h, m) }

    static func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ m: Int) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = rome
        return c.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: m))!
    }

    static func store() throws -> TransitStore {
        let url = FileManager.default.temporaryDirectory.appending(path: "transit-\(UUID().uuidString).sqlite")
        var db: OpaquePointer?
        sqlite3_open(url.path, &db)
        defer { sqlite3_close(db) }
        let t = { (h: Int, m: Int) in h * 3600 + m * 60 }
        var sql = """
            CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE routes (id TEXT PRIMARY KEY, feed TEXT NOT NULL, short_name TEXT, long_name TEXT, mode TEXT NOT NULL, color TEXT);
            CREATE TABLE stops (id TEXT PRIMARY KEY, feed TEXT NOT NULL, name TEXT NOT NULL, lat REAL, lon REAL, parent TEXT, is_station INTEGER NOT NULL);
            CREATE TABLE trips (id TEXT PRIMARY KEY, feed TEXT NOT NULL, route TEXT NOT NULL, service TEXT NOT NULL, headsign TEXT,
                                short_name TEXT, direction INTEGER, bikes_allowed INTEGER NOT NULL);
            CREATE TABLE stop_times (trip TEXT NOT NULL, seq INTEGER NOT NULL, stop TEXT NOT NULL, arr INTEGER NOT NULL, dep INTEGER NOT NULL);
            CREATE TABLE service_dates (service TEXT NOT NULL, date INTEGER NOT NULL, projected INTEGER NOT NULL);
            CREATE TABLE bike_rules (id INTEGER PRIMARY KEY, operator TEXT NOT NULL, routes TEXT NOT NULL, weekdays TEXT NOT NULL,
                                     start INTEGER NOT NULL, "end" INTEGER NOT NULL, status TEXT NOT NULL, carriage TEXT, note TEXT,
                                     source TEXT NOT NULL, checked TEXT NOT NULL);
            INSERT INTO meta VALUES ('schema','1'), ('timezone','Europe/Rome');
            INSERT INTO routes VALUES ('trenord:RE8','trenord','RE8','Milano-Monza-Lecco','rail','94C120'),
                                      ('trenord:S9','trenord','S9','Saronno-Albairate','rail','94C120'),
                                      ('atm:M1','atm','M1','Sesto - Rho','metro','E1001B');
            INSERT INTO stops VALUES ('trenord:S01700','trenord','Milano Centrale',45.487012,9.20329,NULL,0),
                                     ('trenord:S01650','trenord','Sesto San Giovanni',45.5367,9.2385,NULL,0),
                                     ('trenord:S01322','trenord','Monza',45.578009,9.272752,NULL,0),
                                     ('atm:P.TA VENEZIA','atm','P.TA VENEZIA',45.4745,9.2048,NULL,0),
                                     ('atm:SESTO 1 MAGGIO FS','atm','SESTO 1 MAGGIO FS',45.5422,9.2385,NULL,0);
            INSERT INTO service_dates VALUES ('WK',20261022,0), ('SUN',20261025,0);
            INSERT INTO bike_rules VALUES
              (1,'atm','["M1", "M2", "M3"]','1111111',0,108000,'allowed','2nd or 5th carriage (doors with the bike sign), max 4 bikes per door','','atm','2026-10-14'),
              (2,'trenord','["S9"]','1111111',0,108000,'not_allowed',NULL,NULL,'test','2026-10-23'),
              (3,'trenord','["*"]','1111111',0,108000,'check','Carriage with the bike area','Only some trains','trenord','2026-10-14');
            """
        // Weekday Monza trains (the real pack's 22 Oct runs), a Sunday one, an S9 that refuses bikes, an M1 run.
        let runs: [(String, String, String, String, String, [(String, Int)])] = [
            ("trenord:2816", "trenord:RE8", "WK", "2816", "Lecco", [("trenord:S01700", t(8, 20)), ("trenord:S01650", t(8, 27)), ("trenord:S01322", t(8, 31))]),
            ("trenord:25510", "trenord:RE8", "WK", "25510", "Monza", [("trenord:S01700", t(8, 43)), ("trenord:S01322", t(8, 52))]),
            ("trenord:2860", "trenord:RE8", "WK", "2860", "Lecco", [("trenord:S01700", t(9, 20)), ("trenord:S01322", t(9, 31))]),
            ("trenord:9001", "trenord:RE8", "SUN", "9001", "Lecco", [("trenord:S01700", t(10, 0)), ("trenord:S01322", t(10, 12))]),
            ("trenord:7001", "trenord:S9", "WK", "7001", "Monza", [("trenord:S01700", t(8, 18)), ("trenord:S01322", t(8, 26))]),
            ("atm:m1-1", "atm:M1", "WK", "", "Sesto 1 Maggio", [("atm:P.TA VENEZIA", t(8, 10)), ("atm:SESTO 1 MAGGIO FS", t(8, 24))]),
        ]
        for (id, route, service, name, head, calls) in runs {
            sql += "INSERT INTO trips VALUES ('\(id)','\(id.split(separator: ":")[0])','\(route)','\(service)','\(head)','\(name)',0,0);\n"
            for (i, c) in calls.enumerated() { sql += "INSERT INTO stop_times VALUES ('\(id)',\(i + 1),'\(c.0)',\(c.1),\(c.1));\n" }
        }
        sqlite3_exec(db, sql, nil, nil, nil)
        return try TransitStore(path: url)
    }
}

struct TransitStoreTests {
    @Test func namesAndRules() throws {
        let s = try TransitFixture.store()
        #expect(TransitStore.displayName("CENTRALE FS", feed: "atm") == "Centrale FS")
        #expect(TransitStore.displayName("P.TA VENEZIA", feed: "atm") == "P.ta Venezia")
        #expect(TransitStore.displayName("Milano Centrale", feed: "trenord") == "Milano Centrale")
        #expect(TransitStore.trainNumber("RE_80 - 25510") == "25510")
        #expect(TransitStore.trainNumber("") == nil)
        let runs = s.departures(from: ["atm:P.TA VENEZIA"], to: ["atm:SESTO 1 MAGGIO FS"],
                                after: TransitFixture.thursday(8, 0), before: TransitFixture.thursday(9, 0))
        #expect(runs.map(\.name) == ["M1"])
        #expect(s.bikeRule(for: runs[0]).status == .allowed)
        #expect(s.bikeRule(for: runs[0]).carriage?.hasPrefix("2nd or 5th carriage") == true)
    }

    @Test func departuresKeepToTheServiceDay() throws {
        let s = try TransitFixture.store()
        let weekday = s.departures(from: ["trenord:S01700"], to: ["trenord:S01322"],
                                   after: TransitFixture.thursday(8, 0), before: TransitFixture.thursday(11, 0))
        #expect(weekday.map(\.tripName) == ["7001", "2816", "25510", "2860"])
        #expect(weekday[1].name == "Trenord RE8 2816")
        let sunday = s.departures(from: ["trenord:S01700"], to: ["trenord:S01322"],
                                  after: TransitFixture.sunday(8, 0), before: TransitFixture.sunday(11, 0))
        #expect(sunday.map(\.tripName) == ["9001"])
        #expect(s.stopTimes(of: weekday[1]).map(\.stop.name) == ["Milano Centrale", "Sesto San Giovanni", "Monza"])
    }
}

struct DirectPlannerTests {
    @Test func monzaTakesTheFirstCatchableTrainWithBikes() throws {
        let s = try TransitFixture.store()
        // 08:05 at Porta Venezia: Centrale is ≈ 7 min away plus 3 to board, so the 08:20 RE8 (the 08:18 S9 refuses bikes).
        let c = DirectPlanner.candidates(s, from: TransitFixture.portaVenezia, to: TransitFixture.villaReale, at: TransitFixture.thursday(8, 5))
        #expect(c.first?.departure.name == "Trenord RE8 2816")
        #expect(c.first?.departure.board.name == "Milano Centrale" && c.first?.departure.alight.name == "Monza")
        #expect(!c.contains { $0.departure.route.shortName == "S9" })
        #expect(c.first?.rule.offered == true)                       // Trenord "check": offered (23 Oct)
        // Ten minutes later the 08:20 is gone.
        let late = DirectPlanner.candidates(s, from: TransitFixture.portaVenezia, to: TransitFixture.villaReale, at: TransitFixture.thursday(8, 14))
        #expect(late.first?.departure.tripName == "25510")
    }

    @Test func nextTrainsOfThePair() throws {
        let s = try TransitFixture.store()
        let first = try #require(DirectPlanner.candidates(s, from: TransitFixture.portaVenezia, to: TransitFixture.villaReale,
                                                          at: TransitFixture.thursday(8, 5)).first)
        #expect(DirectPlanner.later(s, than: first.departure, count: 2).map(\.tripName) == ["25510", "2860"])
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
        #expect(TransitCopy.segments(p).map(\.label) == ["Ride 7", "Wait 4", "Train 11", "", "Ride 6"])   // "Out 3" unlabelled
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
}
