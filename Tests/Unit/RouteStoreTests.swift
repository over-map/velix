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
