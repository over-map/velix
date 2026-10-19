import Foundation
import SQLite3
import Testing
@testable import Velix

/// Golden route tests: 10 trips × 6 ride types on a real region pack (docs/TEST_TRIPS.md).
/// Needs an unpacked pack folder (valhalla_tiles.tar + hazards.sqlite) in VELIX_PACK_DIR
/// (pass TEST_RUNNER_VELIX_PACK_DIR=… to xcodebuild). Writes GeoJSON per case to VELIX_GOLDEN_OUT for review.
struct GoldenTrip: Sendable, CustomStringConvertible {
    let id: Int
    let name: String
    let from: LatLon
    let to: LatLon
    var description: String { "\(id) \(name)" }

    static let all: [GoldenTrip] = [
        .init(id: 1, name: "Porta Venezia → Politecnico", from: .init(lat: 45.4746, lon: 9.2050), to: .init(lat: 45.4781, lon: 9.2272)),
        .init(id: 2, name: "Duomo → Bicocca", from: .init(lat: 45.4642, lon: 9.1900), to: .init(lat: 45.5140, lon: 9.2110)),
        .init(id: 3, name: "Darsena → Città Studi", from: .init(lat: 45.4520, lon: 9.1757), to: .init(lat: 45.4760, lon: 9.2350)),
        .init(id: 4, name: "Stazione Centrale → Brera (Via Fiori Chiari)", from: .init(lat: 45.4855, lon: 9.2035), to: .init(lat: 45.4720, lon: 9.1865)),
        .init(id: 5, name: "Porta Romana → Arco della Pace", from: .init(lat: 45.4520, lon: 9.2030), to: .init(lat: 45.4757, lon: 9.1725)),
        .init(id: 6, name: "San Siro → Duomo", from: .init(lat: 45.4781, lon: 9.1240), to: .init(lat: 45.4642, lon: 9.1900)),
        .init(id: 7, name: "Darsena → Abbiategrasso (Naviglio Grande)", from: .init(lat: 45.4520, lon: 9.1757), to: .init(lat: 45.3986, lon: 8.9188)),
        .init(id: 8, name: "Stazione Centrale → Villa Reale, Monza", from: .init(lat: 45.4855, lon: 9.2035), to: .init(lat: 45.5885, lon: 9.2740)),
        .init(id: 9, name: "Bovisa → Parco Nord", from: .init(lat: 45.5020, lon: 9.1590), to: .init(lat: 45.5300, lon: 9.1960)),
        .init(id: 10, name: "Bergamo FS → Città Alta", from: .init(lat: 45.6905, lon: 9.6750), to: .init(lat: 45.7037, lon: 9.6625)),
    ]
}

enum GoldenPack {
    static let directory: URL? = ProcessInfo.processInfo.environment["VELIX_PACK_DIR"].map { URL(filePath: $0) }
    /// Needs the tiles and a hazards sidecar of schema ≥ 2 (lighting table, M3); older packs skip the suite.
    static var available: Bool {
        guard let d = directory, FileManager.default.fileExists(atPath: d.appending(path: "valhalla_tiles.tar").path)
        else { return false }
        return hazardsSchema(d.appending(path: "hazards.sqlite")) >= 2
    }

    private static func hazardsSchema(_ url: URL) -> Int {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key = 'schema'", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
    }

    /// One engine for the whole run (building it maps 360 MB of tiles).
    static let planner: Result<RoutePlanner, Error>? = {
        guard available, let d = directory else { return nil }
        return Result {
            let engine = try ValhallaOnDeviceProvider(tileExtract: d.appending(path: "valhalla_tiles.tar"),
                                                      profile: RideProfile.load(.city).best)
            return RoutePlanner(engine: engine, hazards: try HazardStore(path: d.appending(path: "hazards.sqlite")))
        }
    }()

    static let outDir: URL? = ProcessInfo.processInfo.environment["VELIX_GOLDEN_OUT"].map { URL(filePath: $0) }
}

@Suite(.enabled(if: GoldenPack.available, "Set TEST_RUNNER_VELIX_PACK_DIR to an unpacked region pack (hazards schema ≥ 2)"), .serialized)
struct GoldenRouteTests {
    static let cases: [(GoldenTrip, RideType)] = GoldenTrip.all.flatMap { t in RideType.allCases.map { (t, $0) } }

    @Test(arguments: cases)
    func goldenRoute(_ trip: GoldenTrip, _ type: RideType) async throws {
        let planner = try #require(GoldenPack.planner).get()
        let rules = RuleSet.defaults(for: type)
        let plan = try await planner.plan(from: trip.from, to: trip.to, rules: rules)
        GoldenReport.write(trip: trip, type: type, plan: plan)

        switch plan {
        case .noRoute:
            Issue.record("no route at all for \(trip) \(type)")
        case let .noRouteMeetsRules(rule, _, _, _):
            #expect(rules.active.contains(rule), "blocking rule must be one of the active rules")
            #expect(type == .cargo, "only Cargo / kids is ever blocked")
            #expect(GoldenExpectations.mayBlock(trip: trip.id, type: type, rule: rule),
                    "\(trip) \(type): blocked by \(rule.title), not expected")
        case let .options(o):
            let bestV = RuleChecker.violations(of: rules.active, in: o.best.analysis)
            if type == .cargo {
                #expect(RuleChecker.hardViolations(bestV, rideType: .cargo).isEmpty, "Cargo Best breaks \(bestV.map(\.rule.title))")
            } else {
                // Rules are soft for the other types: Best is never worse than Fastest on time + rule penalty.
                func cost(_ seconds: Double, _ a: RouteAnalysis) -> Double {
                    seconds + RuleChecker.violations(of: rules.active, in: a).reduce(0) { $0 + RoutePlanner.weight($1.rule) * $1.meters }
                }
                let fastestSeconds = o.fastest?.seconds ?? o.best.seconds
                #expect(cost(o.best.seconds, o.best.analysis) <= cost(fastestSeconds, o.fastestAnalysis) + 1,
                        "\(trip) \(type): Best scores worse than Fastest")
            }
            #expect(o.fastestAnalysis.lengthM > 0)
            if let fastest = o.fastest {
                #expect(fastest.seconds <= o.best.seconds + 1, "Fastest must not be slower than Best")
                #expect(!DifferenceCopy.showsSingleCard(bestSeconds: o.best.seconds, fastestSeconds: fastest.seconds, sameRoute: false))
                #expect(o.bestLine.hasPrefix("+"), "difference line: \(o.bestLine)")
            } else {
                #expect(o.bestName == "Best and fastest")
            }
            #expect(o.milliseconds < 5000, "planning took \(Int(o.milliseconds)) ms")
            GoldenExpectations.check(trip: trip.id, type: type, options: o)
        }
    }
}

/// Trip-specific properties (docs/TEST_TRIPS.md). Robust to monthly OSM changes: no exact metres.
enum GoldenExpectations {
    static func mayBlock(trip: Int, type: RideType, rule: Rule) -> Bool {
        switch (trip, type, rule) {
        case (3, .cargo, .neverAlongTramRails): true // Darsena and the tram corridors to Città Studi
        case (7, .cargo, .neverAlongTramRails): true // Darsena start: tram rails along Ripa di Porta Ticinese
        case (8, .cargo, .noStepsOrGaps): true      // cycle barrier on the way into Monza (OSM n2704536133)
        case (4, .cargo, .noCobbles): true          // cobbled destination in Brera
        case (5, .cargo, _): true                    // through the cobbled, pedestrian centre
        case (10, .cargo, .maxGrade6): true          // Città Alta is steep
        case (10, .cargo, .bikeLanesOnly): true
        default: false
        }
    }

    /// Metres of unpaved Road Best may keep. Trip 6: 287 m of compacted paths at Castello Sforzesco; the only
    /// all-asphalt alternative is 10.7 km instead of 6.8 (DECISIONS 19 Oct).
    static func roadUnpavedAllowance(trip: Int) -> Double { trip == 6 ? 300 : 200 }

    static func check(trip: Int, type: RideType, options o: RouteOptions) {
        let best = o.best.analysis, fastest = o.fastestAnalysis
        switch type {
        case .road:
            #expect(best.meters(.unpaved) <= GoldenExpectations.roadUnpavedAllowance(trip: trip),
                    "Road Best on unpaved: \(Int(best.meters(.unpaved))) m")
        case .cargo:
            #expect(best.maxGrade <= 6 || best.edges.filter { $0.meters >= 30 }.allSatisfy { max($0.maxUpwardGrade, $0.maxDownwardGrade) <= 6 })
        case .gravel, .mtb:
            if trip == 7 || trip == 9 {
                #expect(best.meters(.unpaved) + best.pathMeters >= fastest.meters(.unpaved) + fastest.pathMeters - 1,
                        "\(type) should go at least as off-road as Fastest")
            }
        default: break
        }
        if trip == 2, type == .city {
            #expect((best.busyByName["Viale Fulvio Testi"] ?? 0) < 500, "City Best on Viale Fulvio Testi")
        }
        if type == .city {
            #expect(best.hazardCount(.steps) == 0 || best.hazards.filter { $0.type == .steps }.allSatisfy { $0.distanceAlong < 50 })
        }
    }
}

/// GeoJSON per case for the review map (tools/route-review).
enum GoldenReport {
    static func write(trip: GoldenTrip, type: RideType, plan: RoutePlan) {
        guard let dir = GoldenPack.outDir else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var features: [[String: Any]] = []
        func line(_ shape: [LatLon], _ props: [String: Any]) -> [String: Any] {
            ["type": "Feature", "properties": props,
             "geometry": ["type": "LineString", "coordinates": shape.map { [round($0.lon * 1e6) / 1e6, round($0.lat * 1e6) / 1e6] }]]
        }
        var summary: [String: Any] = ["trip": trip.id, "tripName": trip.name, "type": type.rawValue, "typeName": type.name]
        switch plan {
        case .noRoute:
            summary["result"] = "noRoute"
        case let .noRouteMeetsRules(rule, t, closest, remaining):
            summary["result"] = "blocked"
            summary["title"] = "No route meets your \(t.name) rules"
            summary["line"] = "\(rule.title) is on for \(t.name)."
            summary["unavoidable"] = remaining.map { "\($0.rule.title) \(Int($0.meters)) m" }
            if let c = closest {
                features.append(line(c.analysis.shape, ["role": "closest"]))
                summary["closestRounds"] = c.exclusions.count
                summary["closestLengthM"] = Int(c.analysis.lengthM)
                summary["closestGaps"] = c.analysis.hazards.filter { $0.type == .gap }.map { "\($0.detail) at \(Int($0.distanceAlong)) m (\($0.osm))" }
            }
        case let .options(o):
            summary["result"] = o.fastest == nil ? "single" : "two"
            summary["bestName"] = o.bestName
            summary["bestLine"] = o.bestLine
            summary["fastestLine"] = o.fastestLine ?? ""
            summary["bestMin"] = Int((o.best.seconds / 60).rounded())
            summary["bestKm"] = (o.best.meters / 100).rounded() / 10
            summary["fastestMin"] = o.fastest.map { Int(($0.seconds / 60).rounded()) } ?? summary["bestMin"]!
            summary["rounds"] = o.rounds
            summary["ms"] = Int(o.milliseconds)
            summary["timingsBest"] = o.best.timings.mapValues { Int($0) }
            summary["timingsFastest"] = (o.fastest ?? o.best).timings.mapValues { Int($0) }
            summary["mix"] = Dictionary(uniqueKeysWithValues: MixCategory.allCases.map { ($0.rawValue, Int(o.best.analysis.meters($0))) })
            summary["unavoidable"] = o.unavoidable.map { "\($0.rule.title) \(Int($0.meters)) m" }
            if let f = o.fastest { features.append(line(f.analysis.shape, ["role": "fastest"])) }
            features.append(line(o.best.analysis.shape, ["role": "best"]))
            for a in o.avoided { features.append(line(a.shape, ["role": "avoided", "name": a.name, "reason": a.reason])) }
            let along = RouteAnalyzer.cumulative(o.best.analysis.shape)
            for h in o.best.analysis.hazards {
                let i = along.firstIndex { $0 >= h.distanceAlong } ?? max(0, along.count - 1)
                let p = o.best.analysis.shape[min(i, o.best.analysis.shape.count - 1)]
                features.append(["type": "Feature", "properties": ["role": "hazard", "hazard": h.type.rawValue,
                                                                    "title": h.type.title, "street": h.street ?? "", "detail": h.detail,
                                                                    "along": Int(h.distanceAlong), "length": Int(h.lengthM)],
                                 "geometry": ["type": "Point", "coordinates": [p.lon, p.lat]]])
            }
        }
        let doc: [String: Any] = ["type": "FeatureCollection", "properties": summary, "features": features]
        if let data = try? JSONSerialization.data(withJSONObject: doc, options: [.sortedKeys]) {
            try? data.write(to: dir.appending(path: "\(trip.id)-\(type.rawValue).geojson"))
        }
    }
}
