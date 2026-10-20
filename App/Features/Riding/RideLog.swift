import CoreLocation
import Foundation

/// The ride's own record (M7): every fix and every event, one JSON object per line in `Documents/rides/`.
/// It feeds the S6 summary (distance, moving time, climb, GPX) and the M7 acceptance review (hazard timing,
/// reroutes, gaps), pulled from the phone like M1's `m1-metrics.jsonl`.
final class RideLog: @unchecked Sendable {
    enum Event: Equatable, Sendable {
        case start(destination: String, meters: Double)
        case hazard(type: String, distance: Double, at: LatLon)
        case reroute(String)          // "requested", "accepted", "failed"
        case gps(String)              // "weak", "good"
        case end(String)              // "arrived", "ended"
    }

    let url: URL
    private let lock = NSLock()
    private var handle: FileHandle?
    private(set) var stats = RideStats()

    init(directory: URL = URL.documentsDirectory.appending(path: "rides"), started: Date = Date()) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = started.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "")
        url = directory.appending(path: "\(name).jsonl")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
    }

    func fix(_ l: CLLocation) {
        lock.lock(); defer { lock.unlock() }
        stats.add(l)
        write(["t": l.timestamp.timeIntervalSince1970, "lat": l.coordinate.latitude, "lon": l.coordinate.longitude,
               "acc": l.horizontalAccuracy, "alt": l.altitude, "v": l.speed, "c": l.course])
    }

    func event(_ e: Event) {
        lock.lock(); defer { lock.unlock() }
        let t = Date().timeIntervalSince1970
        switch e {
        case let .start(d, m): write(["t": t, "e": "start", "to": d, "m": m])
        case let .hazard(type, d, at): write(["t": t, "e": "hazard", "type": type, "d": d, "lat": at.lat, "lon": at.lon])
        case let .reroute(s): write(["t": t, "e": "reroute", "s": s])
        case let .gps(s): write(["t": t, "e": "gps", "s": s])
        case let .end(s): write(["t": t, "e": "end", "s": s])
        }
    }

    func close() {
        lock.lock(); defer { lock.unlock() }
        try? handle?.close()
        handle = nil
    }

    private func write(_ object: [String: Any]) {
        guard let handle, let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        handle.write(data + Data("\n".utf8))
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
