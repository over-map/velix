import Foundation

/// The time the app plans with (timetables, late / missed). Debug builds take `-fake-time 08:05` (today, Rome time)
/// or `-fake-time 2026-11-05T08:05`, and run on from there, so the Monza scenario can be tried at any hour.
enum AppClock {
    static var now: Date { Date().addingTimeInterval(offset) }

    private static let offset: TimeInterval = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-fake-time"), i + 1 < args.count, let fake = parse(args[i + 1], today: Date()) {
            return fake.timeIntervalSince(Date())
        }
        #endif
        return 0
    }()

    static let rome = TimeZone(identifier: "Europe/Rome")!

    /// "08:05" (today) or "2026-11-05T08:05", Rome time.
    static func parse(_ s: String, today: Date) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = rome
        let parts = s.split(separator: "T")
        let hm = (parts.last ?? "").split(separator: ":").compactMap { Int($0) }
        guard hm.count == 2 else { return nil }
        var day = cal.dateComponents([.year, .month, .day], from: today)
        if parts.count == 2 {
            let ymd = parts[0].split(separator: "-").compactMap { Int($0) }
            guard ymd.count == 3 else { return nil }
            day = DateComponents(year: ymd[0], month: ymd[1], day: ymd[2])
        }
        day.hour = hm[0]
        day.minute = hm[1]
        return cal.date(from: day)
    }
}
