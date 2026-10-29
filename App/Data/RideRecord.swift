import CoreLocation
import Foundation
import Observation
import SwiftData

/// One finished ride in the history (M9, SwiftData). The store lives in Application Support, so it is in the
/// phone's iCloud backup; no CloudKit, no account (BRIEF). The full log and the GPX stay files in `Documents/rides`.
@Model
final class RideRecord {
    @Attribute(.unique) var id: UUID
    var started: Date
    var ended: Date
    var destination: String
    var placeKind: String
    var rideType: String
    /// The S6 option line: "Calmest for city", "Fastest", "Bike + train".
    var option: String
    var meters: Double
    var movingSeconds: Double
    var climb: Double
    var arrived: Bool
    /// "Trenord RE80 25510", "M1" for bike + transit; nil for a ride.
    var transit: String?
    /// The ride as ridden, [[lat, lon]] JSON (the S6 map).
    var trackData: Data
    /// File names in `Documents/rides`.
    var logFile: String
    var gpxFile: String?
    var healthSaved: Bool

    init(id: UUID = UUID(), started: Date, ended: Date, destination: String, placeKind: Place.Kind = .poi,
         rideType: RideType, option: String? = nil, meters: Double, movingSeconds: Double, climb: Double, arrived: Bool, transit: String? = nil,
         track: [LatLon], logFile: String, gpxFile: String?, healthSaved: Bool = false) {
        self.id = id
        self.started = started
        self.ended = ended
        self.destination = destination
        self.placeKind = placeKind.rawValue
        self.rideType = rideType.rawValue
        self.option = option ?? (transit == nil ? rideType.bestName : "Bike + train")
        self.meters = meters
        self.movingSeconds = movingSeconds
        self.climb = climb
        self.arrived = arrived
        self.transit = transit
        self.trackData = (try? JSONEncoder().encode(track.map { [$0.lat, $0.lon] })) ?? Data()
        self.logFile = logFile
        self.gpxFile = gpxFile
        self.healthSaved = healthSaved
    }

    var type: RideType { RideType(rawValue: rideType) ?? .city }

    var track: [LatLon] {
        ((try? JSONDecoder().decode([[Double]].self, from: trackData)) ?? []).compactMap { $0.count == 2 ? LatLon(lat: $0[0], lon: $0[1]) : nil }
    }

    var gpxURL: URL? { gpxFile.map { RideHistory.directory.appending(path: $0) } }
}

extension RideRecord {
    /// P7 S8 RideRow subtitle: "Today 08:24 · City", "Yesterday · bike + train", "Tue 7 Oct · City".
    func detail(now: Date = AppClock.now, calendar: Calendar = .current) -> String {
        let day: String
        if calendar.isDate(started, inSameDayAs: now) {
            day = "Today " + started.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        } else if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(started, inSameDayAs: y) {
            day = "Yesterday"
        } else {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_GB")
            f.timeZone = calendar.timeZone
            f.dateFormat = "EEE d MMM"
            day = f.string(from: started)
        }
        return "\(day) · \(transit == nil ? type.name : "bike + train")"
    }
}

/// The ride history: saves a ride when it ends, lists them newest first, deletes one with its files, and imports
/// the logs written before M9 once.
@MainActor
@Observable
final class RideHistory {
    nonisolated static let directory = URL.documentsDirectory.appending(path: "rides")
    /// Rides shorter than this (a start and an End at the door) aren't kept.
    nonisolated static let minimumMeters = 200.0

    private(set) var rides: [RideRecord] = []
    private let context: ModelContext?

    init(inMemory: Bool = false) {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        context = (try? ModelContainer(for: RideRecord.self, configurations: config)).map { ModelContext($0) }
        refresh()
    }

    func add(_ record: RideRecord) {
        guard record.meters >= Self.minimumMeters, let context else { return }
        context.insert(record)
        try? context.save()
        refresh()
    }

    func delete(_ record: RideRecord) {
        for name in [record.logFile, record.gpxFile].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: Self.directory.appending(path: name))
        }
        context?.delete(record)
        try? context?.save()
        refresh()
    }

    func save() {
        try? context?.save()
        refresh()
    }

    private func refresh() {
        rides = (try? context?.fetch(FetchDescriptor<RideRecord>(sortBy: [SortDescriptor(\.started, order: .reverse)]))) ?? []
    }

    // MARK: From a ride

    /// The record of a ride that just ended (nil without a log).
    static func record(_ session: RideSession, transit: String?, at now: Date = AppClock.now) -> RideRecord? {
        guard let log = session.log else { return nil }
        let stats = session.stats
        let ridden = log.ridden
        return RideRecord(started: log.started, ended: now, destination: session.destination.name,
                          placeKind: session.destination.kind, rideType: session.rules.rideType,
                          option: transit != nil ? "Bike + train" : session.choice == .best ? nil : "Fastest", meters: stats.meters,
                          movingSeconds: stats.movingSeconds, climb: stats.climb, arrived: session.arrived, transit: transit,
                          track: ridden.count > 1 ? ridden : session.option.analysis.shape,
                          logFile: log.url.lastPathComponent, gpxFile: session.gpx?.lastPathComponent)
    }

    // MARK: Logs written before the history

    nonisolated static let importedKey = "velix.history.importedLogs"

    /// Once per install: every `*.jsonl` in `directory` not already in the history becomes a record.
    func importLogs(from directory: URL = RideHistory.directory, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: Self.importedKey) else { return }
        defer { defaults.set(true, forKey: Self.importedKey) }
        let known = Set(rides.map(\.logFile))
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in files where url.pathExtension == "jsonl" && !known.contains(url.lastPathComponent) {
            guard let lines = try? String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init),
                  let record = Self.record(lines: lines, logFile: url.lastPathComponent) else { continue }
            let gpx = url.deletingPathExtension().appendingPathExtension("gpx")
            if FileManager.default.fileExists(atPath: gpx.path) { record.gpxFile = gpx.lastPathComponent }
            context?.insert(record)
        }
        save()
    }

    /// A record from a ride log's lines (RideLog format); nil when it has no fixes.
    nonisolated static func record(lines: [String], logFile: String) -> RideRecord? {
        var stats = RideStats()
        var ridden: [LatLon] = []
        var first: Double?, last: Double?
        var destination = "Ride", type = RideType.city, arrived = false, train = false
        for line in lines {
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], let t = o["t"] as? Double else { continue }
            first = first ?? t
            last = t
            if let e = o["e"] as? String {
                if e == "start" {
                    destination = o["to"] as? String ?? destination
                    if let raw = o["type"] as? String, let rt = RideType(rawValue: raw) { type = rt }
                }
                if e == "end", o["s"] as? String == "arrived" { arrived = true }
                continue
            }
            guard let lat = o["lat"] as? Double, let lon = o["lon"] as? Double else { continue }
            if o["train"] != nil { train = true; stats.resume(); continue }
            let acc = o["acc"] as? Double ?? -1
            // The log has no vertical accuracy: altitude counts as fair (RideStats takes ≤ 15 m).
            let l = CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), altitude: o["alt"] as? Double ?? 0,
                               horizontalAccuracy: acc, verticalAccuracy: o["alt"] == nil ? -1 : 10,
                               course: o["c"] as? Double ?? -1, speed: o["v"] as? Double ?? -1,
                               timestamp: Date(timeIntervalSince1970: t))
            stats.add(l)
            let p = LatLon(lat: lat, lon: lon)
            if acc >= 0, acc <= 30, ridden.last.map({ Geo.distance($0, p) >= RideLog.riddenStep }) ?? true { ridden.append(p) }
        }
        guard let first, let last, !ridden.isEmpty else { return nil }
        return RideRecord(started: Date(timeIntervalSince1970: first), ended: Date(timeIntervalSince1970: last), destination: destination,
                          rideType: type, meters: stats.meters, movingSeconds: stats.movingSeconds, climb: stats.climb,
                          arrived: arrived, transit: train ? "Train" : nil, track: ridden, logFile: logFile, gpxFile: nil)
    }
}
