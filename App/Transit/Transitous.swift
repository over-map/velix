import Foundation

/// Where direct runs come from (M11 PR 4: Transitous; tests: recorded answers).
protocol TransitSource: Sendable {
    /// Direct rail and metro runs from near `origin` to near `destination`, leaving from `now` on.
    func connections(from origin: LatLon, to destination: LatLon, at now: Date) async throws -> [TransitConnection]
    /// The same run with its live times (nil when the run isn't found, e.g. the operator dropped it).
    func refresh(_ d: TransitDeparture) async throws -> TransitDeparture?
}

enum TransitSourceError: Error, Equatable { case offline, badResponse }

/// Transitous (https://transitous.org, MOTIS 2): free, keyless, open data, for open-source non-commercial apps.
/// Policy: a User-Agent with a contact, a visible link to its sources page (You → About), coordinate with them above
/// 720 plans a day. Velix asks once per trip plan (only online, only for rides of 5 km or more) and, riding to the
/// station, refreshes the run at most every 2 minutes in its last 30 (DECISIONS 26 Nov).
struct TransitousSource: TransitSource {
    var endpoint = URL(string: "https://api.transitous.org/api/v6")!
    var session: URLSession = .shared
    static let sources = URL(string: "https://transitous.org/sources/")!

    static let userAgent: String = {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
        return "Velix/\(v) (https://github.com/over-map/velix)"
    }()

    /// The plan query: direct runs only (one ride, one run, one ride), rail and metro, a bike at each end within
    /// 20 min (about the old 5 km station radius), runs within 90 min.
    static func planQuery(from o: LatLon, to d: LatLon, at now: Date) -> [URLQueryItem] {
        let time = ISO8601DateFormatter().string(from: now)
        return [
            .init(name: "fromPlace", value: "\(o.lat),\(o.lon)"), .init(name: "toPlace", value: "\(d.lat),\(d.lon)"),
            .init(name: "time", value: time), .init(name: "transitModes", value: "RAIL,SUBURBAN,SUBWAY"),
            .init(name: "maxTransfers", value: "0"),
            .init(name: "preTransitModes", value: "BIKE"), .init(name: "postTransitModes", value: "BIKE"),
            .init(name: "maxPreTransitTime", value: "1200"), .init(name: "maxPostTransitTime", value: "1200"),
            .init(name: "cyclingSpeed", value: "\(DirectPlanner.estimateSpeed)"),
            .init(name: "searchWindow", value: "\(Int(DirectPlanner.window))"), .init(name: "numItineraries", value: "6"),
            .init(name: "detailedLegs", value: "true"),
        ]
    }

    func connections(from origin: LatLon, to destination: LatLon, at now: Date) async throws -> [TransitConnection] {
        let data = try await get("plan", Self.planQuery(from: origin, to: destination, at: now))
        return try Self.connections(plan: data)
    }

    func refresh(_ d: TransitDeparture) async throws -> TransitDeparture? {
        let data = try await get("trip", [.init(name: "tripId", value: d.trip)])
        return try Self.refreshed(d, trip: data)
    }

    private func get(_ path: String, _ query: [URLQueryItem]) async throws -> Data {
        var c = URLComponents(url: endpoint.appending(path: path), resolvingAgainstBaseURL: false)!
        c.queryItems = query
        var req = URLRequest(url: c.url!, timeoutInterval: 10)
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw TransitSourceError.badResponse }
            return data
        } catch let e as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
                                         .cannotConnectToHost, .dataNotAllowed, .internationalRoamingOff].contains(e.code) {
            throw TransitSourceError.offline
        }
    }

    // MARK: Decoding (only the fields Velix uses)

    struct Place: Decodable {
        let name: String
        let stopId: String?
        let lat: Double
        let lon: Double
        let arrival: Date?
        let departure: Date?
        let scheduledArrival: Date?
        let scheduledDeparture: Date?
        let tz: String?
        let cancelled: Bool?
    }

    struct Geometry: Decodable {
        let points: String
        let precision: Int
    }

    struct Leg: Decodable {
        let mode: String
        let from: Place
        let to: Place
        let startTime: Date
        let endTime: Date
        let realTime: Bool?
        let cancelled: Bool?
        let tripId: String?
        let routeId: String?
        let routeShortName: String?
        let routeLongName: String?
        let routeColor: String?
        let agencyName: String?
        let agencyUrl: String?
        let headsign: String?
        let tripShortName: String?
        let bikesAllowed: Bool?
        let intermediateStops: [Place]?
        let legGeometry: Geometry?
    }

    struct Itinerary: Decodable { let legs: [Leg] }
    struct Plan: Decodable { let itineraries: [Itinerary] }

    static let transitModes: Set<String> = ["SUBWAY", "SUBURBAN", "RAIL", "REGIONAL_RAIL", "REGIONAL_FAST_RAIL", "LONG_DISTANCE",
                                            "HIGHSPEED_RAIL", "NIGHT_RAIL", "METRO"]

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            if let date = f.date(from: s) { return date }
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "date \(s)"))
        }
        return d
    }

    /// Each itinerary with exactly one rail or metro leg (not cancelled) becomes a connection.
    static func connections(plan data: Data) throws -> [TransitConnection] {
        let plan = try decoder.decode(Plan.self, from: data)
        return plan.itineraries.compactMap { it in
            let runs = it.legs.filter { transitModes.contains($0.mode) }
            guard runs.count == 1, let leg = runs.first, leg.cancelled != true, leg.from.cancelled != true else { return nil }
            return connection(leg)
        }
    }

    static func connection(_ leg: Leg) -> TransitConnection? {
        guard let trip = leg.tripId else { return nil }
        let zone = (leg.from.tz ?? leg.to.tz).flatMap(TimeZone.init(identifier:)) ?? AppClock.rome
        let agency = leg.agencyName ?? ""
        let metro = leg.mode == "SUBWAY" || leg.mode == "METRO"
        let short = metro ? TransitNames.metroLine(leg.routeShortName ?? "") : (leg.routeShortName ?? "")
        var route = TransitRoute(id: leg.routeId ?? trip, feed: agency.lowercased(), shortName: short,
                                 longName: leg.routeLongName ?? "", mode: metro ? .metro : .rail,
                                 color: leg.routeColor.flatMap { $0.isEmpty ? nil : $0 })
        route.operatorName = agency
        route.ticket = leg.agencyUrl.flatMap { $0.isEmpty ? nil : URL(string: $0) }
        func stop(_ p: Place) -> TransitStop {
            TransitStop(id: p.stopId ?? p.name, feed: route.feed, name: TransitNames.displayName(p.name),
                        location: LatLon(lat: p.lat, lon: p.lon))
        }
        let calls = [leg.from] + (leg.intermediateStops ?? []) + [leg.to]
        let stops = calls.enumerated().map { i, p in
            let arrives = i == 0 ? leg.startTime : (p.arrival ?? p.departure ?? leg.endTime)
            let departs = i == calls.count - 1 ? leg.endTime : (p.departure ?? p.arrival ?? leg.startTime)
            return TransitStopTime(stop: stop(p), arrives: arrives, departs: departs)
        }
        var d = TransitDeparture(trip: trip, route: route, tripName: metro ? nil : TransitNames.trainNumber(leg.tripShortName),
                                 headsign: leg.headsign, board: stop(leg.from), alight: stop(leg.to),
                                 departs: leg.startTime, arrives: leg.endTime, boardSeq: 0, alightSeq: calls.count - 1)
        d.scheduledDeparts = leg.from.scheduledDeparture
        d.realTime = leg.realTime ?? false
        d.timeZone = zone
        let line = leg.legGeometry.map { Polyline.decode($0.points, precision: $0.precision) } ?? []
        return TransitConnection(departure: d, stops: stops, line: line, feedAllowsBikes: leg.bikesAllowed ?? false)
    }

    /// A `trip` answer (the whole run) for a planned departure: its live times at the boarding and alighting stops,
    /// or a cancelled copy (nil times) → nil.
    static func refreshed(_ d: TransitDeparture, trip data: Data) throws -> TransitDeparture? {
        let it = try decoder.decode(Itinerary.self, from: data)
        guard let leg = it.legs.first(where: { $0.tripId == d.trip }) ?? it.legs.first else { return nil }
        if leg.cancelled == true { return nil }
        let calls = [leg.from] + (leg.intermediateStops ?? []) + [leg.to]
        guard let board = calls.first(where: { $0.stopId == d.board.id }),
              let alight = calls.last(where: { $0.stopId == d.alight.id }),
              board.cancelled != true, alight.cancelled != true else { return nil }
        let departs = board.departure ?? board.arrival ?? d.departs
        let arrives = alight.arrival ?? alight.departure ?? d.arrives
        return d.moved(departs: departs, arrives: arrives, realTime: leg.realTime ?? false)
    }
}

/// Google's encoded polyline at a given precision (Transitous: 6; Velix's own `Geo.decodePolyline6`).
enum Polyline {
    static func decode(_ s: String, precision: Int) -> [LatLon] {
        let factor = pow(10, Double(precision))
        var out: [LatLon] = []
        var lat = 0, lon = 0
        let bytes = Array(s.utf8)
        var i = 0
        func next() -> Int? {
            var result = 0, shift = 0
            while i < bytes.count {
                let b = Int(bytes[i]) - 63
                i += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20 { return (result & 1) != 0 ? ~(result >> 1) : result >> 1 }
            }
            return nil
        }
        while i < bytes.count {
            guard let dLat = next(), let dLon = next() else { break }
            lat += dLat
            lon += dLon
            out.append(LatLon(lat: Double(lat) / factor, lon: Double(lon) / factor))
        }
        return out
    }
}

/// Recorded answers (tests).
struct FixedTransitSource: TransitSource {
    var connections: [TransitConnection]
    var live: [String: TransitDeparture?] = [:]
    var offline = false

    func connections(from origin: LatLon, to destination: LatLon, at now: Date) async throws -> [TransitConnection] {
        if offline { throw TransitSourceError.offline }
        return connections.filter { $0.departure.departs >= now }
    }

    func refresh(_ d: TransitDeparture) async throws -> TransitDeparture? {
        if offline { throw TransitSourceError.offline }
        if let l = live[d.trip] { return l }
        return d
    }
}
