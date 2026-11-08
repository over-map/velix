import CoreLocation
import Foundation

/// The ride's own record (M7): every fix and every event, one JSON object per line in `Documents/rides/`.
/// It feeds the S6 summary (distance, moving time, climb, GPX) and the M7 acceptance review (hazard timing,
/// reroutes, gaps), pulled from the phone like M1's `m1-metrics.jsonl`.
final class RideLog: @unchecked Sendable {
    enum Event: Equatable, Sendable {
        case start(destination: String, meters: Double, type: RideType? = nil, context: Context? = nil)
        /// The route ridden from here (at start and after every reroute): what should alert on the way (M7 review).
        case route(meters: Double, maneuvers: Int, hazards: [Planned])
        /// `speed` and `gps` at the alert, `spoken`: the voice mode let it speak.
        case hazard(type: String, distance: Double, at: LatLon, speed: Double = -1, gps: String = "good", spoken: Bool = true)
        /// "requested" (position, ms since the last request), "accepted" (ms since the request, the new route's
        /// metres), "failed" (reason; the old route is kept), "held" (the back-off said no, once a minute at most),
        /// "fastest" / "best" (bike + transit swaps).
        case reroute(String, ms: Double? = nil, meters: Double? = nil, reason: String? = nil, at: LatLon? = nil)
        case gps(String)              // "weak", "good"
        case end(String)              // "arrived", "ended", "leg"
        case transit(String)          // bike + transit: "late: fastest to catch 08:43", "missed 08:43: next 09:20", …
        /// A spoken prompt: "started", "finished", "cancelled", "error" (with the text), and whether the phone was locked.
        case voice(String, text: String, locked: Bool, background: Bool)
        /// "active", "background", "locked", "unlocked", "terminate", "memoryWarning".
        case app(String)
        /// Once a minute: battery (0–1, -1 unknown), plugged in, thermal state, memory footprint, fixes that minute.
        /// `fps`: frames the map drew a second over the minute (MapLibre draws only when something changes); `slowFrames`: frames over 33 ms.
        /// `cpu`: the app's CPU time over the minute, in % of one core (iOS reports the battery only in 5 % steps, too coarse to compare builds).
        case health(battery: Double, charging: Bool, thermal: String, memoryMB: Double, fixes: Int, fps: Double = 0, slowFrames: Int = 0, cpu: Double = -1)
        /// The Live Activity: "started", "unavailable", "failed" (once), "updates" (count in the last minute).
        case activity(String, count: Int = 0)
    }

    /// The ride's setting, logged at start (M7 review).
    struct Context: Equatable, Sendable {
        var app: String
        var simulated: Bool
        var voice: String
        var view: String
        var battery: Double
        var charging: Bool
        var lowPower: Bool
    }

    /// A hazard on the route: its type, where along the route (m), and where.
    struct Planned: Equatable, Sendable {
        var type: String
        var along: Double
        var at: LatLon
    }

    let url: URL
    let started: Date
    private let lock = NSLock()
    /// The file is written here, in order, off the main thread (M10: a write a second on main while riding).
    private let queue = DispatchQueue(label: "app.velix.ridelog", qos: .utility)
    private var handle: FileHandle?   // used on `queue` only after init
    private(set) var stats = RideStats()
    /// The ride as ridden, a point every 10 m (the S6 map).
    private(set) var ridden: [LatLon] = []
    static let riddenStep = 10.0

    init(directory: URL = URL.documentsDirectory.appending(path: "rides"), started: Date = Date()) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.started = started
        let name = started.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "")
        url = directory.appending(path: "\(name).jsonl")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
    }

    /// `ridden`: false on the train (bike + transit): the fix is logged, not counted as riding (S6 km, moving time).
    func fix(_ l: CLLocation, ridden counts: Bool = true) {
        lock.lock(); defer { lock.unlock() }
        guard counts else {
            stats.resume()
            write(["t": l.timestamp.timeIntervalSince1970, "lat": l.coordinate.latitude, "lon": l.coordinate.longitude,
                   "acc": l.horizontalAccuracy, "alt": l.altitude, "v": l.speed, "c": l.course, "train": true])
            return
        }
        stats.add(l)
        let p = LatLon(lat: l.coordinate.latitude, lon: l.coordinate.longitude)
        if l.horizontalAccuracy >= 0, l.horizontalAccuracy <= 30, ridden.last.map({ Geo.distance($0, p) >= Self.riddenStep }) ?? true {
            ridden.append(p)
        }
        write(["t": l.timestamp.timeIntervalSince1970, "lat": l.coordinate.latitude, "lon": l.coordinate.longitude,
               "acc": l.horizontalAccuracy, "alt": l.altitude, "v": l.speed, "c": l.course])
    }

    func event(_ e: Event) {
        lock.lock(); defer { lock.unlock() }
        let t = Date().timeIntervalSince1970
        switch e {
        case let .start(d, m, type, c):
            var o: [String: Any] = ["t": t, "e": "start", "to": d, "m": m]
            if let type { o["type"] = type.rawValue }
            if let c {
                o["app"] = c.app; o["sim"] = c.simulated; o["voice"] = c.voice; o["view"] = c.view
                o["battery"] = Self.r2(c.battery); o["charging"] = c.charging; o["lowPower"] = c.lowPower
            }
            write(o)
        case let .route(m, maneuvers, hazards):
            write(["t": t, "e": "route", "m": Self.r1(m), "steps": maneuvers,
                   "hazards": hazards.map { ["type": $0.type, "along": Self.r1($0.along), "lat": $0.at.lat, "lon": $0.at.lon] }])
        case let .hazard(type, d, at, v, gps, spoken):
            var o: [String: Any] = ["t": t, "e": "hazard", "type": type, "d": d, "lat": at.lat, "lon": at.lon, "gps": gps, "spoken": spoken]
            if v >= 0 { o["v"] = Self.r1(v); if v > 0.5 { o["secs"] = Self.r1(d / v) } }
            write(o)
        case let .reroute(s, ms, m, reason, at):
            var o: [String: Any] = ["t": t, "e": "reroute", "s": s]
            if let ms { o["ms"] = Int(ms.rounded()) }
            if let m { o["m"] = Self.r1(m) }
            if let reason { o["reason"] = reason }
            if let at { o["lat"] = at.lat; o["lon"] = at.lon }
            if s == "failed" { o["kept"] = true }
            write(o)
        case let .gps(s): write(["t": t, "e": "gps", "s": s])
        case let .end(s): write(["t": t, "e": "end", "s": s])
        case let .transit(s): write(["t": t, "e": "transit", "s": s])
        case let .voice(s, text, locked, background):
            write(["t": t, "e": "voice", "s": s, "text": text, "locked": locked, "background": background])
        case let .app(s): write(["t": t, "e": "app", "s": s])
        case let .health(b, charging, thermal, mb, fixes, fps, slow, cpu):
            write(["t": t, "e": "health", "battery": Self.r2(b), "charging": charging, "thermal": thermal, "mb": Self.r1(mb), "fixes": fixes,
                   "fps": Self.r1(fps), "slow": slow, "cpu": Self.r1(cpu)])
        case let .activity(s, count):
            var o: [String: Any] = ["t": t, "e": "activity", "s": s]
            if s == "updates" { o["n"] = count }
            write(o)
        }
    }

    private static func r1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
    private static func r2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    /// The log marks a simulated ride (`-simulate-ride`, `-fake-location`): kept out of the history and the M7 review.
    nonisolated static func isSimulated(lines: [String]) -> Bool {
        for line in lines.prefix(3) {
            if let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], o["e"] as? String == "start" {
                return o["sim"] as? Bool ?? false
            }
        }
        return false
    }

    /// Simulated by its flag, or (logs from before the flag, 6 Nov) by the simulator's constant 5.0 m accuracy.
    nonisolated static func looksSimulated(lines: [String]) -> Bool {
        if isSimulated(lines: lines) { return true }
        var accuracies = Set<Double>(), fixes = 0
        for line in lines {
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], o["e"] == nil,
                  let acc = o["acc"] as? Double else { continue }
            accuracies.insert(acc)
            fixes += 1
            if accuracies.count > 1 { return false }
        }
        return fixes >= 10 && accuracies == [5]
    }

    /// Writes what's queued and closes the file (before it's read: the history, the GPX, app termination).
    func close() {
        lock.lock(); defer { lock.unlock() }
        queue.sync {
            try? handle?.close()
            handle = nil
        }
    }

    /// Waits for the queued lines (tests, readers of a log still open).
    func flush() { queue.sync {} }

    /// The ride as GPX 1.1 (S6 Share GPX: the fixes only, no events), written next to the log.
    func gpx(name: String) throws -> URL {
        flush()
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
        let out = url.deletingPathExtension().appendingPathExtension("gpx")
        try Self.gpx(lines: lines, name: name).write(to: out, atomically: true, encoding: .utf8)
        return out
    }

    static func gpx(lines: [String], name: String) -> String {
        let time = Date.ISO8601FormatStyle()
        var pts = ""
        for line in lines {
            // Fixes only (no events), and not the train's (bike + transit): the GPX is the ride.
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], o["e"] == nil, o["train"] == nil,
                  let lat = o["lat"] as? Double, let lon = o["lon"] as? Double, let t = o["t"] as? Double else { continue }
            let ele = (o["alt"] as? Double).map { "<ele>\(String(format: "%.1f", $0))</ele>" } ?? ""
            pts += "<trkpt lat=\"\(lat)\" lon=\"\(lon)\">\(ele)<time>\(Date(timeIntervalSince1970: t).formatted(time))</time></trkpt>\n"
        }
        let safe = name.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Velix" xmlns="http://www.topografix.com/GPX/1/1">
        <trk><name>\(safe)</name><type>cycling</type><trkseg>
        \(pts)</trkseg></trk>
        </gpx>

        """
    }

    private func write(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        queue.async { [self] in handle?.write(data + Data("\n".utf8)) }
    }
}

/// Totals for S6 (P7: "5.4 km · 21 min moving · 8 m climb"), across reroutes (Ferrostar restarts its summary on each).
struct RideStats: Equatable, Sendable {
    private(set) var meters: Double = 0
    private(set) var movingSeconds: TimeInterval = 0
    private(set) var climb: Double = 0
    private var last: CLLocation?
    private var lastAltitude: Double?

    /// Below this speed the rider is stopped (a light, a junction): not moving time.
    static let movingSpeed: CLLocationSpeed = 1.0
    /// Altitude changes smaller than this are GPS noise.
    static let climbStep: Double = 2

    /// After a stretch not ridden (the train): the next fix starts fresh, not measured from the last one.
    mutating func resume() {
        last = nil
        lastAltitude = nil
    }

    mutating func add(_ l: CLLocation) {
        defer { last = l }
        if l.verticalAccuracy >= 0, l.verticalAccuracy <= 15 {
            if let a = lastAltitude {
                let rise = l.altitude - a
                if abs(rise) >= Self.climbStep {
                    if rise > 0 { climb += rise }
                    lastAltitude = l.altitude
                }
            } else {
                lastAltitude = l.altitude
            }
        }
        guard let last, l.horizontalAccuracy >= 0, l.horizontalAccuracy <= 30 else { return }
        let d = l.distance(from: last), dt = l.timestamp.timeIntervalSince(last.timestamp)
        guard dt > 0 else { return }
        meters += d
        if d / dt >= Self.movingSpeed { movingSeconds += dt }
    }
}
