import Foundation

/// Velix's own bikes-on-board rules (BRIEF §8: "bikes-allowed connections only"), bundled in the app
/// (`App/Resources/Transit/bike-rules.json`, moved from the packs in M11 PR 4). Transitous marks Italian and German
/// trains "bikes: false" (DECISIONS 9 Nov), so a curated rule wins; with none, the feed's own "bikes allowed" (the
/// Netherlands) means allowed; anything else is "check", which is offered.
struct BikeRules: Sendable {
    struct Entry: Codable, Sendable {
        /// The operator's name as Transitous publishes it (`agencyName`), matched from its start, any case
        /// ("DB Regio AG S-Bahn München" for "DB Regio AG S-Bahn").
        let agency: String
        /// Lines (`routeShortName`, metro lines as "M1"), or "*".
        let routes: [String]
        /// Monday … Sunday as 7 characters of 0/1.
        let weekdays: String
        /// Local times, "HH:MM", end exclusive.
        let from: String
        let until: String
        let status: BikeRule.Status
        let carriage: String?
        let note: String?
        let source: String
        let checked: String
    }

    let entries: [Entry]

    static let bundled: BikeRules = {
        guard let url = Bundle.main.url(forResource: "bike-rules", withExtension: "json"),
              let data = try? Data(contentsOf: url), let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return BikeRules(entries: []) }
        return BikeRules(entries: entries)
    }()

    /// The first rule for the run's operator and line that covers the weekday and time; else allowed when the feed
    /// says so; else `check`.
    func rule(for d: TransitDeparture, feedAllowsBikes: Bool = false) -> BikeRule {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = d.timeZone
        let c = cal.dateComponents([.weekday, .hour, .minute], from: d.departs)
        let weekday = ((c.weekday ?? 2) + 5) % 7   // Monday = 0
        let minute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let agency = d.route.operatorName.lowercased()
        for e in entries where agency.hasPrefix(e.agency.lowercased())
            && (e.routes.contains("*") || e.routes.contains(d.route.shortName))
            && Self.day(e.weekdays, weekday) && minute >= Self.minutes(e.from) && minute < Self.minutes(e.until) {
            return BikeRule(status: e.status, carriage: e.carriage, note: e.note)
        }
        return BikeRule(status: feedAllowsBikes ? .allowed : .check, carriage: nil, note: nil)
    }

    private static func day(_ mask: String, _ weekday: Int) -> Bool {
        let a = Array(mask)
        return a.indices.contains(weekday) && a[weekday] == "1"
    }

    static func minutes(_ hhmm: String) -> Int {
        let p = hhmm.split(separator: ":").compactMap { Int($0) }
        return p.count == 2 ? p[0] * 60 + p[1] : 0
    }
}
