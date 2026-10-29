import Foundation
import SQLite3

/// An OSM cycle route from the pack (S7): a `route=bicycle|mtb` relation, its merged pieces and what it's made of.
struct CycleRoute: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case bicycle, mtb }

    let id: Int64
    let kind: Kind
    /// lcn | rcn | ncn | icn | "" (MTB routes may have none)
    let network: String
    let name: String
    let ref: String
    let eurovelo: Int?
    let meters: Double
    let pavedShare: Double
    /// S7 mix (schema 2; nil in older packs): car-free paved, quiet road, gravel. The rest is busier road.
    let mix: Mix?
    /// Metres up riding the pieces in stored order, and the other way (schema 2).
    let climb: Double?
    let descent: Double?
    let description: String
    let from: String
    let to: String
    /// The merged pieces, chained end to end (``RouteStore/chain(_:)``): what Ride this route follows.
    let line: [LatLon]
    /// The pieces as stored: what the map draws (chaining bridges gaps with straight lines).
    var pieces: [[LatLon]] = []

    struct Mix: Hashable, Sendable {
        var carFree: Double
        var quiet: Double
        var unpaved: Double
        var road: Double { max(0, 1 - carFree - quiet - unpaved) }
    }

    var unpavedShare: Double { mix?.unpaved ?? (1 - pavedShare) }

    /// P7 network chip: "Regional", "Local", "National", "MTB".
    var networkName: String {
        if kind == .mtb { return "MTB" }
        switch network {
        case "icn": return "International"
        case "ncn": return "National"
        case "rcn": return "Regional"
        default: return "Local"
        }
    }

    /// The card's one-line note: the description, else "From → To".
    var note: String {
        if !description.isEmpty { return description }
        if !from.isEmpty, !to.isEmpty { return "\(from) → \(to)" }
        return ""
    }
}

/// Which routes the S7 filter keeps (P7 chips: Fits {type} · All · Paved · Gravel · MTB).
enum RouteFilter: Hashable, Sendable {
    case fits(RideType), all, paved, gravel, mtb

    func keeps(_ r: CycleRoute) -> Bool {
        switch self {
        case .all: true
        case .paved: r.unpavedShare <= 0.1
        case .gravel: r.unpavedShare >= 0.2 && r.unpavedShare <= 0.8
        case .mtb: r.kind == .mtb
        case let .fits(type):
            switch type {
            case .city, .ebike, .cargo: r.kind == .bicycle && r.unpavedShare <= 0.1
            case .road: r.kind == .bicycle && r.unpavedShare <= 0.03
            case .gravel: r.unpavedShare >= 0.2
            case .mtb: r.kind == .mtb || r.unpavedShare >= 0.5
            }
        }
    }
}

/// Read-only access to the pack's `routes.sqlite` (pipeline/stages/routes.py; schema 2, schema 1 tolerated).
final class RouteStore: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSLock()
    private(set) var schema = 1

    /// At most this many routes in a search (P7 lists a handful), none shorter than `minimumMeters` (the pack clips
    /// routes at the region border and keeps stray pieces of others).
    static let limit = 10
    static let minimumMeters = 2000.0
    /// Pieces shorter than this are left out of the chained line (still drawn).
    static let minimumPiece = 200.0

    enum Failure: Error { case cannotOpen(String) }

    init(path: URL) throws {
        guard sqlite3_open_v2(path.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            throw Failure.cannotOpen(path.path)
        }
        rows("SELECT value FROM meta WHERE key = 'schema'") { s in schema = Int(Self.text(s, 0) ?? "1") ?? 1 }
    }

    deinit { sqlite3_close(db) }

    /// Routes meeting the box (minLat, minLon, maxLat, maxLon) and the filter: EuroVelo first, then the nearest to
    /// `center` (by the route's nearest point).
    func routes(in box: (Double, Double, Double, Double), near center: LatLon, filter: RouteFilter = .all,
                limit: Int = RouteStore.limit) -> [CycleRoute] {
        let extra = schema >= 2 ? ", car_free_share, quiet_share, unpaved_share, climb_m, descent_m, description, \"from\", \"to\"" : ""
        var out: [CycleRoute] = []
        rows("""
            SELECT r.id, kind, network, name, ref, eurovelo, length_m, paved_share, polylines\(extra)
            FROM routes r JOIN routes_rtree t ON t.id = r.id
            WHERE t.min_lat <= \(box.2) AND t.max_lat >= \(box.0) AND t.min_lon <= \(box.3) AND t.max_lon >= \(box.1)
            """) { s in
            let pieces = ((try? JSONDecoder().decode([String].self, from: Data((Self.text(s, 8) ?? "[]").utf8))) ?? [])
                .map(Geo.decodePolyline6)
            let v2 = schema >= 2
            let route = CycleRoute(
                id: sqlite3_column_int64(s, 0), kind: CycleRoute.Kind(rawValue: Self.text(s, 1) ?? "") ?? .bicycle,
                network: Self.text(s, 2) ?? "", name: Self.text(s, 3) ?? "", ref: Self.text(s, 4) ?? "",
                eurovelo: sqlite3_column_type(s, 5) == SQLITE_NULL ? nil : Int(sqlite3_column_int(s, 5)),
                meters: sqlite3_column_double(s, 6), pavedShare: sqlite3_column_double(s, 7),
                mix: v2 ? .init(carFree: sqlite3_column_double(s, 9), quiet: sqlite3_column_double(s, 10),
                                unpaved: sqlite3_column_double(s, 11)) : nil,
                climb: v2 && sqlite3_column_type(s, 12) != SQLITE_NULL ? sqlite3_column_double(s, 12) : nil,
                descent: v2 && sqlite3_column_type(s, 13) != SQLITE_NULL ? sqlite3_column_double(s, 13) : nil,
                description: v2 ? Self.text(s, 14) ?? "" : "", from: v2 ? Self.text(s, 15) ?? "" : "",
                to: v2 ? Self.text(s, 16) ?? "" : "", line: Self.chain(pieces), pieces: pieces)
            out.append(route)
        }
        return Self.ordered(out.filter { $0.meters >= Self.minimumMeters && filter.keeps($0) }, near: center).prefix(limit).map { $0 }
    }

    /// EuroVelo first, then by the distance from `center` to the route's nearest point.
    static func ordered(_ routes: [CycleRoute], near center: LatLon) -> [CycleRoute] {
        let near = Dictionary(uniqueKeysWithValues: routes.map { r in (r.id, r.line.map { Geo.distance($0, center) }.min() ?? .infinity) })
        return routes.sorted {
            if ($0.eurovelo != nil) != ($1.eurovelo != nil) { return $0.eurovelo != nil }
            return near[$0.id]! < near[$1.id]!
        }
    }

    /// The pieces as one line: from the longest, the nearest remaining piece is joined at whichever end is closer
    /// (reversed if needed), at the front or the back. OSM relations aren't always ordered or in one direction.
    static func chain(_ pieces: [[LatLon]]) -> [LatLon] {
        // Fragments at junctions (a few metres of a side way, both carriageways) would send the vias back and forth.
        var rest = pieces.filter { $0.count > 1 }
        if rest.count > 1 { rest = rest.filter { Geo.length($0) >= minimumPiece } }
        if rest.isEmpty { rest = pieces.filter { $0.count > 1 } }
        guard let longest = rest.indices.max(by: { Geo.length(rest[$0]) < Geo.length(rest[$1]) }) else { return pieces.first ?? [] }
        var line = rest.remove(at: longest)
        while !rest.isEmpty {
            var best = (index: 0, gap: Double.infinity, atEnd: true, reversed: false)
            for (i, p) in rest.enumerated() {
                for (atEnd, reversed, gap) in [(true, false, Geo.distance(line.last!, p.first!)), (true, true, Geo.distance(line.last!, p.last!)),
                                               (false, true, Geo.distance(line.first!, p.first!)), (false, false, Geo.distance(line.first!, p.last!))]
                where gap < best.gap {
                    best = (i, gap, atEnd, reversed)
                }
            }
            var piece = rest.remove(at: best.index)
            if best.reversed { piece.reverse() }
            line = best.atEnd ? line + piece : piece + line
        }
        return line
    }

    private func rows(_ sql: String, _ each: (OpaquePointer) -> Void) {
        lock.lock(); defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW { each(stmt) }
    }

    private static func text(_ s: OpaquePointer, _ i: Int32) -> String? {
        sqlite3_column_text(s, i).map { String(cString: $0) }
    }
}

extension RideType {
    /// Valhalla's cycling_speed in this type's profile (App/Resources/RoutingProfiles), km/h.
    var paceKmh: Double {
        switch self {
        case .city: 16
        case .ebike: 22
        case .road: 25
        case .gravel: 18
        case .mtb: 15
        case .cargo: 13
        }
    }

    /// Riding time for a distance and a climb: the profile's pace plus a minute per 10 m up (half on an e-bike).
    func time(meters: Double, climb: Double) -> TimeInterval {
        meters / (paceKmh / 3.6) + climb * (self == .ebike ? 3 : 6)
    }
}
