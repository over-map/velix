import Foundation
import SQLite3
import Testing
@testable import Velix

struct RouteStoreTests {
    /// Three routes near Milan, schema 2 (pipeline/stages/routes.py).
    static func store(schema: Int = 2) throws -> RouteStore {
        let url = FileManager.default.temporaryDirectory.appending(path: "routes-\(UUID().uuidString).sqlite")
        var db: OpaquePointer?
        sqlite3_open(url.path, &db)
        defer { sqlite3_close(db) }
        let v2 = schema >= 2
        func line(_ pts: [(Double, Double)]) -> String {
            "[\"" + Self.encode(pts.map { LatLon(lat: $0.0, lon: $0.1) }) + "\"]"
        }
        let cols = v2 ? ", car_free_share REAL, quiet_share REAL, unpaved_share REAL, climb_m REAL, descent_m REAL, description TEXT, \"from\" TEXT, \"to\" TEXT" : ""
        var sql = """
            CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            INSERT INTO meta VALUES ('schema', '\(schema)');
            CREATE TABLE routes (id INTEGER PRIMARY KEY, kind TEXT, network TEXT, name TEXT, ref TEXT, eurovelo INTEGER, operator TEXT,
                                 length_m REAL, paved_share REAL, polylines TEXT\(cols));
            CREATE VIRTUAL TABLE routes_rtree USING rtree(id, min_lon, max_lon, min_lat, max_lat);
            """
        let rows: [(Int, String, String, String, String, Int?, Double, Double, [(Double, Double)], String)] = [
            (1, "bicycle", "rcn", "Naviglio Pavese", "", nil, 33000, 1.0, [(45.45, 9.17), (45.30, 9.15)], "0.6, 0.4, 0.0, 8, 47, '', 'Milano', 'Pavia'"),
            (2, "bicycle", "icn", "EuroVelo 5", "EV5", 5, 178_000, 0.78, [(45.60, 9.30), (45.70, 9.40)], "0.28, 0.35, 0.22, 733, 682, 'Pilgrims', '', ''"),
            (3, "mtb", "", "Parco Nord MTB", "", nil, 12000, 0.3, [(45.52, 9.20), (45.53, 9.21)], "0.1, 0.2, 0.7, 60, 60, '', '', ''"),
        ]
        for r in rows {
            let lats = r.8.map(\.0), lons = r.8.map(\.1)
            sql += "INSERT INTO routes VALUES (\(r.0), '\(r.1)', '\(r.2)', '\(r.3)', '\(r.4)', \(r.5.map(String.init) ?? "NULL"), '', \(r.6), \(r.7), '\(line(r.8))'\(v2 ? ", " + r.9 : ""));"
            sql += "INSERT INTO routes_rtree VALUES (\(r.0), \(lons.min()!), \(lons.max()!), \(lats.min()!), \(lats.max()!));"
        }
        sqlite3_exec(db, sql, nil, nil, nil)
        return try RouteStore(path: url)
    }

    static func encode(_ pts: [LatLon]) -> String {
        var out = "", plat = 0, plon = 0
        func enc(_ v: Int) {
            var v = v < 0 ? ~(v << 1) : v << 1
            while v >= 0x20 { out.append(Character(UnicodeScalar(UInt8((0x20 | (v & 0x1f)) + 63)))); v >>= 5 }
            out.append(Character(UnicodeScalar(UInt8(v + 63))))
        }
        for p in pts {
            let lat = Int((p.lat * 1e6).rounded()), lon = Int((p.lon * 1e6).rounded())
            enc(lat - plat); enc(lon - plon); plat = lat; plon = lon
        }
        return out
    }

    static let milan = LatLon(lat: 45.4642, lon: 9.19)
    static let box = (45.0, 8.8, 46.0, 9.8)

    @Test func euroVeloFirstThenNearest() throws {
        let names = try Self.store().routes(in: Self.box, near: Self.milan).map(\.name)
        #expect(names == ["EuroVelo 5", "Naviglio Pavese", "Parco Nord MTB"])
    }

    @Test func filtersFollowP7() throws {
        let s = try Self.store()
        #expect(s.routes(in: Self.box, near: Self.milan, filter: .fits(.city)).map(\.name) == ["Naviglio Pavese"])
        #expect(s.routes(in: Self.box, near: Self.milan, filter: .fits(.gravel)).map(\.name) == ["EuroVelo 5", "Parco Nord MTB"])
        #expect(s.routes(in: Self.box, near: Self.milan, filter: .gravel).map(\.name) == ["EuroVelo 5", "Parco Nord MTB"])
        #expect(s.routes(in: Self.box, near: Self.milan, filter: .mtb).map(\.name) == ["Parco Nord MTB"])
        #expect(s.routes(in: Self.box, near: Self.milan, filter: .paved).map(\.name) == ["Naviglio Pavese"])
    }

    @Test func schema2Fields() throws {
        let r = try #require(try Self.store().routes(in: Self.box, near: Self.milan).first { $0.id == 1 })
        #expect(r.mix == .init(carFree: 0.6, quiet: 0.4, unpaved: 0))
        #expect(r.climb == 8 && r.descent == 47)
        #expect(r.note == "Milano → Pavia")
        #expect(r.networkName == "Regional")
        #expect(r.line.count == 2)
    }

    @Test func schema1HasNoMix() throws {
        let r = try #require(try Self.store(schema: 1).routes(in: Self.box, near: Self.milan).first { $0.id == 3 })
        #expect(r.mix == nil && r.climb == nil)
        #expect(abs(r.unpavedShare - 0.7) < 1e-9)
    }

    @Test func boxLeavesOutFarRoutes() throws {
        let names = try Self.store().routes(in: (45.25, 9.1, 45.5, 9.25), near: Self.milan).map(\.name)
        #expect(names == ["Naviglio Pavese"])
    }

    @Test func piecesChainEndToEnd() {
        let a = [LatLon(lat: 45.0, lon: 9.0), LatLon(lat: 45.01, lon: 9.0)]
        let b = [LatLon(lat: 45.03, lon: 9.0), LatLon(lat: 45.011, lon: 9.0)]   // reversed, after a
        let c = [LatLon(lat: 44.98, lon: 9.0), LatLon(lat: 44.999, lon: 9.0)]   // before a
        let line = RouteStore.chain([a, b, c])
        #expect(Set([line.first!, line.last!]) == Set([c.first!, b.first!]))
        #expect(line.count == 6)
    }

    @Test func timeByType() {
        #expect(RideType.gravel.time(meters: 18000, climb: 0) == 3600)
        #expect(RideType.city.time(meters: 16000, climb: 100) == 3600 + 600)
    }
}

@MainActor
struct RoutesModelTests {
    nonisolated static func route(_ id: Int64, unpaved: Double, kind: CycleRoute.Kind = .bicycle, line: [LatLon]? = nil) -> CycleRoute {
        let l = line ?? [LatLon(lat: 45.4 + Double(id) * 0.01, lon: 9.1), LatLon(lat: 45.5 + Double(id) * 0.01, lon: 9.1)]
        return CycleRoute(id: id, kind: kind, network: "rcn", name: "R\(id)", ref: "", eurovelo: nil, meters: 10000, pavedShare: 1 - unpaved,
                          mix: .init(carFree: 0.5, quiet: 0.5 - unpaved, unpaved: unpaved), climb: 10, descent: 10, description: "",
                          from: "A", to: "B", line: l, pieces: [l])
    }

    static func model() -> RoutesModel {
        let m = RoutesModel(rideType: .gravel, home: .init(center: RouteStoreTests.milan, name: "Milan"))
        m.show([route(1, unpaved: 0.3), route(2, unpaved: 0.0), route(3, unpaved: 0.7, kind: .mtb)], area: m.home)
        return m
    }

    @Test func filterKeysAndFocus() {
        let m = Self.model()
        #expect(m.results.map(\.id) == [1, 3])
        #expect(m.count == "2 fit Gravel")
        #expect(m.focus == 1)
        m.filterIndex = 1
        #expect(m.results.count == 3 && m.count == "3 routes")
    }

    @Test func aTappedLineComesToTheTopAndKeepsItsKey() {
        let m = Self.model()
        m.filterIndex = 1
        m.tapped(3)
        #expect(m.cards.map(\.key) == [3, 1, 2])
        #expect(m.focus == 3)
        #expect(m.mapRoute.listed.first { $0.id == 3 }?.state == .focus)
    }

    @Test func selectedGreysTheOthers() {
        let m = Self.model()
        m.select(3)
        #expect(m.selectedRoute?.id == 3)
        #expect(m.mapRoute.listed.filter { $0.state == .grey }.map(\.id) == [1])
        m.deselect()
        #expect(m.selectedRoute == nil)
    }

    @Test func theListWaitsForSearchHere() {
        let m = Self.model()
        m.mapMoved(to: LatLon(lat: 45.4650, lon: 9.19))   // 100 m: not a move
        #expect(m.moved == nil)
        m.mapMoved(to: LatLon(lat: 45.98, lon: 9.26), name: "Lake Como")
        #expect(m.moved?.name == "Lake Como")
        #expect(m.results.count == 2)   // unchanged until Search routes in this area
    }

    @Test func emptyFilterSaysWhatIsMissing() {
        let m = Self.model()
        m.show([Self.route(2, unpaved: 0)], area: .init(center: RouteStoreTests.milan, name: "Lake Como"))
        m.filterIndex = 4
        #expect(m.emptyText?.title == "No MTB routes in this area")
        #expect(m.emptyText?.message == "There is 1 other route here.")
    }

    @Test func outsideTheRegion() {
        let m = Self.model()
        m.load(store: nil, inside: { _ in false })
        m.search(.init(center: LatLon(lat: 46.0, lon: 8.95), name: "Lugano"))
        #expect(m.outside)
    }
}

struct RouteRideTests {
    static let line = [LatLon(lat: 45.40, lon: 9.0), LatLon(lat: 45.45, lon: 9.0), LatLon(lat: 45.50, lon: 9.0)]

    @Test func joinsAtTheNearerEnd() throws {
        let r = RoutesModelTests.route(1, unpaved: 0, line: Self.line)
        let near = try #require(RouteRide.leg(r, from: LatLon(lat: 45.39, lon: 9.0)))
        #expect(!near.reversed && near.from == "A" && near.to == "B")
        let far = try #require(RouteRide.leg(r, from: LatLon(lat: 45.52, lon: 9.0)))
        #expect(far.reversed && far.line.first == Self.line.last && far.from == "B" && far.to == "A")
    }

    @Test func viasStartAtTheJoinAndStopBeforeTheEnd() {
        let vias = RouteRide.vias(Self.line)   // ≈ 11 km
        #expect(vias.first == Self.line.first)
        #expect(vias.count == 7)
        #expect(Geo.distance(vias.last!, Self.line.last!) > 750)
    }

    @Test func longRoutesGetAtMostFortyVias() {
        let long = [LatLon(lat: 44.0, lon: 9.0), LatLon(lat: 45.5, lon: 9.0)]   // ≈ 167 km
        #expect(RouteRide.vias(long).count <= RouteRide.maxVias)
    }

    @Test func copy() {
        let leg = RouteRide.Leg(line: Self.line, from: "the Darsena", to: "Pavia", reversed: false)
        #expect(RouteRide.line(approachSeconds: 960, leg: leg) == "**16 min** to the start at the Darsena, then the full route to Pavia")
        #expect(RouteRide.duration(140 * 60) == "2 h 20")
        #expect(RouteRide.duration(45 * 60) == "45 min")
    }

    @Test func reroutesGoBackThroughTheViasAhead() {
        let vias = RouteRide.vias(Self.line)
        let ahead = PlannedRouteProvider.viasAhead(vias, from: vias[2])
        #expect(ahead == Array(vias[3...]))
    }
}
