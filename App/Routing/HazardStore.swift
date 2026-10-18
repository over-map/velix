import Foundation
import SQLite3

/// Read-only access to the pack's `hazards.sqlite` (pipeline/stages/hazards.py, schema 2).
final class HazardStore: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSLock()

    init(path: URL) throws {
        guard sqlite3_open_v2(path.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            throw RoutingError.tilesMissing(path.path)
        }
    }

    deinit { sqlite3_close(db) }

    /// Line hazards recorded on these OSM ways (cobbles, rails along, steps, dismount, door, narrow way).
    func lineHazards(onWays ways: some Collection<Int64>) -> [HazardRecord] {
        let ids = Array(Set(ways))
        var out: [HazardRecord] = []
        for chunk in stride(from: 0, to: ids.count, by: 400).map({ Array(ids[$0 ..< min($0 + 400, ids.count)]) }) {
            let list = chunk.map { "'w\($0)'" }.joined(separator: ",")
            out += query("SELECT \(Self.columns) FROM hazards h WHERE h.geom = 'line' AND h.osm IN (\(list))")
        }
        return out
    }

    /// Point hazards whose box meets this bounding box (minLat, minLon, maxLat, maxLon).
    func pointHazards(in box: (Double, Double, Double, Double)) -> [HazardRecord] {
        query("""
            SELECT \(Self.columns) FROM hazards h JOIN hazards_rtree r ON r.id = h.id
            WHERE h.geom = 'point' AND r.min_lat <= \(box.2) AND r.max_lat >= \(box.0)
              AND r.min_lon <= \(box.3) AND r.max_lon >= \(box.1)
            """)
    }

    /// Lighting per way: true lit, false unlit, missing = not tagged. Also whether the way is a path.
    func lighting(ofWays ways: some Collection<Int64>) -> [Int64: (lit: Bool?, path: Bool)] {
        let ids = Array(Set(ways))
        var out: [Int64: (Bool?, Bool)] = [:]
        lock.lock(); defer { lock.unlock() }
        for chunk in stride(from: 0, to: ids.count, by: 400).map({ Array(ids[$0 ..< min($0 + 400, ids.count)]) }) {
            var stmt: OpaquePointer?
            let sql = "SELECT way_id, lit, path FROM ways WHERE way_id IN (\(chunk.map(String.init).joined(separator: ",")))"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { continue }
            while sqlite3_step(stmt) == SQLITE_ROW {
                let lit: Bool? = sqlite3_column_type(stmt, 1) == SQLITE_NULL ? nil : sqlite3_column_int(stmt, 1) == 1
                out[sqlite3_column_int64(stmt, 0)] = (lit, sqlite3_column_int(stmt, 2) == 1)
            }
            sqlite3_finalize(stmt)
        }
        return out
    }

    /// Walk stretches (table `walk_ways`, absent in older packs: then none).
    func walkWays(among ways: some Collection<Int64>) -> Set<Int64> {
        let ids = Array(Set(ways))
        var out = Set<Int64>()
        lock.lock(); defer { lock.unlock() }
        for chunk in stride(from: 0, to: ids.count, by: 400).map({ Array(ids[$0 ..< min($0 + 400, ids.count)]) }) {
            var stmt: OpaquePointer?
            let sql = "SELECT way_id FROM walk_ways WHERE way_id IN (\(chunk.map(String.init).joined(separator: ",")))"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            while sqlite3_step(stmt) == SQLITE_ROW { out.insert(sqlite3_column_int64(stmt, 0)) }
            sqlite3_finalize(stmt)
        }
        return out
    }

    private static let columns = "h.id, h.type, h.geom, h.lat, h.lon, h.length_m, h.polyline6, h.detail, h.osm, h.heading"

    private func query(_ sql: String) -> [HazardRecord] {
        lock.lock(); defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [HazardRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            func text(_ i: Int32) -> String { sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? "" }
            guard let type = HazardType(rawValue: text(1)) else { continue }
            out.append(HazardRecord(
                id: sqlite3_column_int64(stmt, 0), type: type, isLine: text(2) == "line",
                lat: sqlite3_column_double(stmt, 3), lon: sqlite3_column_double(stmt, 4),
                lengthM: sqlite3_column_double(stmt, 5), polyline6: text(6), detail: text(7), osm: text(8),
                heading: sqlite3_column_type(stmt, 9) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 9)))
        }
        return out
    }
}
