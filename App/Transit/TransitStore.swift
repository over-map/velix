import Foundation
import SQLite3

/// A station or metro stop in the pack's timetable (one row per station: Trenord and ATM both publish one stop each).
struct TransitStop: Hashable, Sendable {
    let id: String
    let feed: String
    /// Display name: Trenord's as published ("Milano Centrale"), ATM's from upper case ("Centrale FS").
    let name: String
    let location: LatLon
}

struct TransitRoute: Hashable, Sendable {
    enum Mode: String, Sendable { case rail, metro }
    let id: String
    let feed: String
    /// "RE8", "M1"
    let shortName: String
    let longName: String
    let mode: Mode
    /// Line colour, hex without "#" (metro lines).
    let color: String?
}

/// One train or metro run from a boarding stop to an alighting stop, on a given day.
struct TransitDeparture: Hashable, Sendable {
    let trip: String
    let route: TransitRoute
    /// The train number ("2816"); metro runs have none.
    let tripName: String?
    let headsign: String?
    let board: TransitStop
    let alight: TransitStop
    let departs: Date
    let arrives: Date
    let boardSeq: Int
    let alightSeq: Int

    /// "Trenord RE8 2816", "M1"
    var name: String {
        switch route.mode {
        case .rail: ["Trenord", route.shortName, tripName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        case .metro: route.shortName
        }
    }
}

/// A stop of a run, with its times (the S5d timeline).
struct TransitStopTime: Hashable, Sendable {
    let stop: TransitStop
    let arrives: Date
    let departs: Date
}

/// Whether a bike may travel (pipeline/config/bikes_allowed_rules.yml, table `bike_rules`).
struct BikeRule: Hashable, Sendable {
    enum Status: String, Sendable { case allowed, check, notAllowed = "not_allowed" }
    let status: Status
    /// "2nd or 5th carriage (doors with the bike sign), max 4 bikes per door"
    let carriage: String?
    let note: String?

    /// Trenord publishes no per-train bike flag (every train is `check`); Velix offers those trains as allowed
    /// (Filippo, 23 Oct 2026). `not_allowed` is never offered.
    var offered: Bool { status != .notAllowed }
}

/// Read-only access to the pack's `transit.sqlite` (pipeline/stages/transit.py, schema 1): Trenord rail and ATM metro
/// from GTFS, times in seconds after local midnight of the service day, days in the meta timezone.
final class TransitStore: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSLock()
    private(set) var timeZone = TimeZone(identifier: "Europe/Rome")!
    private var routes: [String: TransitRoute] = [:]
    private var stops: [String: TransitStop] = [:]
    private var rules: [(operator: String, routes: [String], weekdays: [Bool], start: Int, end: Int, rule: BikeRule)] = []

    enum Failure: Error { case cannotOpen(String) }

    init(path: URL) throws {
        guard sqlite3_open_v2(path.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            throw Failure.cannotOpen(path.path)
        }
        rows("SELECT value FROM meta WHERE key = 'timezone'") { s in
            if let id = Self.text(s, 0), let z = TimeZone(identifier: id) { timeZone = z }
        }
        rows("SELECT id, feed, short_name, long_name, mode, color FROM routes") { s in
            let r = TransitRoute(id: Self.text(s, 0) ?? "", feed: Self.text(s, 1) ?? "", shortName: Self.text(s, 2) ?? "",
                                 longName: Self.text(s, 3) ?? "", mode: TransitRoute.Mode(rawValue: Self.text(s, 4) ?? "") ?? .rail,
                                 color: Self.text(s, 5))
            routes[r.id] = r
        }
        rows("SELECT id, feed, name, lat, lon FROM stops") { s in
            let feed = Self.text(s, 1) ?? ""
            let stop = TransitStop(id: Self.text(s, 0) ?? "", feed: feed, name: Self.displayName(Self.text(s, 2) ?? "", feed: feed),
                                   location: LatLon(lat: sqlite3_column_double(s, 3), lon: sqlite3_column_double(s, 4)))
            stops[stop.id] = stop
        }
        rows("SELECT operator, routes, weekdays, start, \"end\", status, carriage, note FROM bike_rules ORDER BY id") { s in
            let list = (try? JSONDecoder().decode([String].self, from: Data((Self.text(s, 1) ?? "[]").utf8))) ?? []
            let rule = BikeRule(status: BikeRule.Status(rawValue: Self.text(s, 5) ?? "") ?? .check,
                                carriage: Self.text(s, 6), note: Self.text(s, 7))
            rules.append((Self.text(s, 0) ?? "", list, (Self.text(s, 2) ?? "1111111").map { $0 == "1" },
                          Int(sqlite3_column_int(s, 3)), Int(sqlite3_column_int(s, 4)), rule))
        }
    }

    deinit { sqlite3_close(db) }

    // MARK: Stops

    /// Stops within `radius` metres, nearest first.
    func stops(near p: LatLon, within radius: Double, limit: Int) -> [(stop: TransitStop, meters: Double)] {
        // A degree box first (cheap), then the real distance.
        let dLat = radius / 111_320, dLon = radius / (111_320 * cos(p.lat * .pi / 180))
        return stops.values
            .filter { abs($0.location.lat - p.lat) <= dLat && abs($0.location.lon - p.lon) <= dLon }
            .map { ($0, Geo.distance(p, $0.location)) }
            .filter { $0.1 <= radius }
            .sorted { $0.1 < $1.1 }
            .prefix(limit).map { $0 }
    }

    func stop(_ id: String) -> TransitStop? { stops[id] }

    // MARK: Departures

    /// Direct runs from any of `boards` to any of `alights`, leaving between `after` and `before` (absolute times),
    /// in service that day. A run that calls at several of the stops comes back once per board/alight pair.
    func departures(from boards: [String], to alights: [String], after: Date, before: Date) -> [TransitDeparture] {
        guard !boards.isEmpty, !alights.isEmpty else { return [] }
        let day = serviceDay(of: after)
        let from = Int(after.timeIntervalSince(day.start).rounded(.down)), to = Int(before.timeIntervalSince(day.start).rounded(.up))
        let list = { (ids: [String]) in ids.map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }.joined(separator: ",") }
        let sql = """
            SELECT a.trip, a.stop, a.dep, a.seq, b.stop, b.arr, b.seq, t.route, t.short_name, t.headsign
            FROM stop_times a
            JOIN stop_times b ON b.trip = a.trip AND b.seq > a.seq
            JOIN trips t ON t.id = a.trip
            WHERE a.stop IN (\(list(boards))) AND b.stop IN (\(list(alights))) AND a.dep BETWEEN \(from) AND \(to)
              AND t.service IN (SELECT service FROM service_dates WHERE date = \(day.number))
            ORDER BY a.dep
            """
        var out: [TransitDeparture] = []
        rows(sql) { s in
            guard let route = routes[Self.text(s, 7) ?? ""], let board = stops[Self.text(s, 1) ?? ""],
                  let alight = stops[Self.text(s, 4) ?? ""] else { return }
            out.append(TransitDeparture(trip: Self.text(s, 0) ?? "", route: route, tripName: Self.trainNumber(Self.text(s, 8)),
                                        headsign: Self.text(s, 9),
                                        board: board, alight: alight,
                                        departs: day.start.addingTimeInterval(Double(sqlite3_column_int(s, 2))),
                                        arrives: day.start.addingTimeInterval(Double(sqlite3_column_int(s, 5))),
                                        boardSeq: Int(sqlite3_column_int(s, 3)), alightSeq: Int(sqlite3_column_int(s, 6))))
        }
        return out
    }

    /// The run's calls from boarding to alighting, both included (S5d).
    func stopTimes(of d: TransitDeparture) -> [TransitStopTime] {
        let day = serviceDay(of: d.departs)
        var out: [TransitStopTime] = []
        rows("""
            SELECT stop, arr, dep FROM stop_times WHERE trip = '\(d.trip.replacingOccurrences(of: "'", with: "''"))'
              AND seq BETWEEN \(d.boardSeq) AND \(d.alightSeq) ORDER BY seq
            """) { s in
            guard let stop = stops[Self.text(s, 0) ?? ""] else { return }
            out.append(TransitStopTime(stop: stop, arrives: day.start.addingTimeInterval(Double(sqlite3_column_int(s, 1))),
                                       departs: day.start.addingTimeInterval(Double(sqlite3_column_int(s, 2)))))
        }
        return out
    }

    // MARK: Bikes

    /// The first rule for the run's operator and line that covers the weekday and time; `check` when none does
    /// (the pipeline's precedence: the feed's per-trip flag, then the curated rules, then check).
    func bikeRule(for d: TransitDeparture) -> BikeRule {
        let day = serviceDay(of: d.departs)
        let seconds = Int(d.departs.timeIntervalSince(day.start))
        for r in rules where r.operator == d.route.feed
            && (r.routes.contains("*") || r.routes.contains(d.route.shortName))
            && r.weekdays[day.weekday] && seconds >= r.start && seconds < r.end {
            return r.rule
        }
        return BikeRule(status: .check, carriage: nil, note: nil)
    }

    // MARK: Days

    /// The service day an instant falls in: local midnight in the feed's timezone, YYYYMMDD and Monday = 0.
    func serviceDay(of t: Date) -> (start: Date, number: Int, weekday: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let start = cal.startOfDay(for: t)
        let c = cal.dateComponents([.year, .month, .day, .weekday], from: start)
        return (start, (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0), ((c.weekday ?? 2) + 5) % 7)
    }

    // MARK: SQLite

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

    /// Trenord's trip short name is "RE_80 - 25510": the train number is the last part.
    static func trainNumber(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s.components(separatedBy: " - ").last?.trimmingCharacters(in: .whitespaces)
    }

    /// ATM publishes stop names in capitals ("CENTRALE FS", "P.TA VENEZIA"): title case, keeping short all-caps
    /// abbreviations ("FS").
    static func displayName(_ name: String, feed: String) -> String {
        guard feed == "atm", name == name.uppercased() else { return name }
        return name.split(separator: " ").map { w in
            let word = String(w)
            if ["DI", "DA", "DE", "DEL", "DELLA", "LA", "IL", "LE"].contains(word) { return word.lowercased() }
            return word.count <= 2 && word.allSatisfy(\.isLetter) ? word : word.prefix(1) + word.dropFirst().lowercased()
        }.joined(separator: " ")
    }
}
