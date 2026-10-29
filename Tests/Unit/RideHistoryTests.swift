import Foundation
import Testing
@testable import Velix

@MainActor
struct RideHistoryTests {
    /// A log line per fix going north 20 m every 4 s, then the end.
    private func log(fixes: Int, train: ClosedRange<Int>? = nil, arrived: Bool = true, type: String? = "gravel") -> [String] {
        var lines: [String] = []
        var start: [String: Any] = ["t": 1000.0, "e": "start", "to": "Politecnico", "m": 5000.0]
        if let type { start["type"] = type }
        lines.append(String(data: try! JSONSerialization.data(withJSONObject: start), encoding: .utf8)!)
        for i in 0 ..< fixes {
            var o: [String: Any] = ["t": 1000.0 + Double(i) * 4, "lat": 45.4 + Double(i) * 0.00018, "lon": 9.2, "acc": 5.0,
                                    "alt": 120.0 + Double(i), "v": 5.0, "c": 0.0]
            if train?.contains(i) == true { o["train"] = true }
            lines.append(String(data: try! JSONSerialization.data(withJSONObject: o), encoding: .utf8)!)
        }
        lines.append(#"{"t":\#(1000 + fixes * 4),"e":"end","s":"\#(arrived ? "arrived" : "ended")"}"#)
        return lines
    }

    @Test func aLogBecomesARecord() throws {
        let r = try #require(RideHistory.record(lines: log(fixes: 51), logFile: "x.jsonl"))
        #expect(r.destination == "Politecnico")
        #expect(r.type == .gravel)
        #expect(r.arrived)
        #expect(r.transit == nil)
        #expect(abs(r.meters - 1000) < 20)
        #expect(r.movingSeconds == 200)
        #expect(r.climb >= 48)
        #expect(r.track.count > 40)
        #expect(r.option == RideType.gravel.bestName)
    }

    @Test func trainFixesAreNotRidden() throws {
        let r = try #require(RideHistory.record(lines: log(fixes: 51, train: 10 ... 40), logFile: "x.jsonl"))
        #expect(r.transit != nil)
        #expect(r.meters < 400)
        #expect(r.option == "Bike + train")
    }

    @Test func olderLogsWithoutATypeAreCity() throws {
        let r = try #require(RideHistory.record(lines: log(fixes: 20, arrived: false, type: nil), logFile: "x.jsonl"))
        #expect(r.type == .city)
        #expect(!r.arrived)
    }

    @Test func shortRidesAreNotKept() {
        let h = RideHistory(inMemory: true)
        h.add(RideRecord(started: .now, ended: .now, destination: "Door", rideType: .city, meters: 150, movingSeconds: 30,
                         climb: 0, arrived: false, track: [], logFile: "a.jsonl", gpxFile: nil))
        #expect(h.rides.isEmpty)
        h.add(RideRecord(started: .now, ended: .now, destination: "Park", rideType: .city, meters: 900, movingSeconds: 300,
                         climb: 0, arrived: true, track: [], logFile: "b.jsonl", gpxFile: nil))
        #expect(h.rides.map(\.destination) == ["Park"])
    }

    @Test func importRunsOnceAndNewestFirst() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "velix-hist-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try log(fixes: 51).joined(separator: "\n").write(to: dir.appending(path: "2026-10-20T080000Z.jsonl"), atomically: true, encoding: .utf8)
        var later = log(fixes: 51)
        later = later.map { $0.replacingOccurrences(of: "\"t\":1", with: "\"t\":9") }
        try later.joined(separator: "\n").write(to: dir.appending(path: "2026-10-21T080000Z.jsonl"), atomically: true, encoding: .utf8)
        try "".write(to: dir.appending(path: "empty.jsonl"), atomically: true, encoding: .utf8)
        let defaults = UserDefaults(suiteName: "velix-hist-\(UUID().uuidString)")!
        let h = RideHistory(inMemory: true)
        h.importLogs(from: dir, defaults: defaults)
        #expect(h.rides.count == 2)
        #expect(h.rides[0].started > h.rides[1].started)
        h.delete(h.rides[0])
        h.importLogs(from: dir, defaults: defaults)
        #expect(h.rides.count == 1)
    }

    @Test func rowDetailFollowsP7() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome")!
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 18))!
        func ride(_ d: DateComponents, transit: String? = nil) -> RideRecord {
            RideRecord(started: cal.date(from: d)!, ended: now, destination: "X", rideType: .city, meters: 5400, movingSeconds: 0,
                       climb: 0, arrived: true, transit: transit, track: [], logFile: "", gpxFile: nil)
        }
        #expect(ride(DateComponents(year: 2026, month: 10, day: 28, hour: 9), transit: "RE80").detail(now: now, calendar: cal)
            == "Yesterday · bike + train")
        #expect(ride(DateComponents(year: 2026, month: 10, day: 6, hour: 9)).detail(now: now, calendar: cal) == "Tue 6 Oct · City")
    }
}
