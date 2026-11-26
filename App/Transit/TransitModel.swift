import Foundation

/// A station or metro stop (from Transitous, M11 PR 4).
struct TransitStop: Hashable, Sendable {
    let id: String
    let feed: String
    /// Display name: as published ("Milano Centrale"), title-cased when published in capitals ("Centrale FS").
    let name: String
    let location: LatLon
}

struct TransitRoute: Hashable, Sendable {
    enum Mode: String, Sendable { case rail, metro }
    let id: String
    /// The operator as a key: its name in lower case ("trenord", "atm", "ns").
    let feed: String
    /// "RE8", "M1", "S1", "Sprinter"
    let shortName: String
    let longName: String
    let mode: Mode
    /// Line colour, hex without "#".
    let color: String?
    /// The rider-facing operator ("Trenord", "ATM", "NS").
    var operatorName = ""
    /// The operator's site (Transitous `agencyUrl`): where to buy a ticket outside Italy.
    var ticket: URL?

    /// The operator, shortened where a feed names a company ("DB Regio AG S-Bahn München" → "DB Regio").
    var operatorLabel: String {
        let name = operatorName.isEmpty ? (feed == "atm" ? "ATM" : "Trenord") : operatorName
        return name.components(separatedBy: " AG").first ?? name
    }
}

/// One train or metro run from a boarding stop to an alighting stop.
struct TransitDeparture: Hashable, Sendable {
    let trip: String
    let route: TransitRoute
    /// The train number ("2816"); metro runs have none.
    let tripName: String?
    let headsign: String?
    let board: TransitStop
    let alight: TransitStop
    /// Live times where the operator publishes them, else the timetable's.
    let departs: Date
    let arrives: Date
    let boardSeq: Int
    let alightSeq: Int
    /// The timetable's departure (`departs` minus the delay).
    var scheduledDeparts: Date?
    /// The times come from live data (Transitous `realTime`).
    var realTime = false
    /// The stops' time zone: times are shown in it.
    var timeZone = AppClock.rome

    /// "Trenord RE8 2816", "M1"
    var name: String {
        switch route.mode {
        case .rail: [route.operatorLabel, route.shortName, tripName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        case .metro: route.shortName
        }
    }

    /// In Italy (the Trenitalia ticket app, Italian names).
    var inItaly: Bool { timeZone.identifier == "Europe/Rome" }

    /// The same run at other times (a live update: a delay moves both ends).
    func moved(departs: Date, arrives: Date, realTime: Bool) -> TransitDeparture {
        var d = TransitDeparture(trip: trip, route: route, tripName: tripName, headsign: headsign, board: board, alight: alight,
                                 departs: departs, arrives: arrives, boardSeq: boardSeq, alightSeq: alightSeq)
        d.scheduledDeparts = scheduledDeparts
        d.realTime = realTime
        d.timeZone = timeZone
        return d
    }
}

/// A stop of a run, with its times (the S5d timeline).
struct TransitStopTime: Hashable, Sendable {
    let stop: TransitStop
    let arrives: Date
    let departs: Date
}

/// Whether a bike may travel (``BikeRules``, `App/Resources/Transit/bike-rules.json`).
struct BikeRule: Hashable, Sendable {
    enum Status: String, Sendable, Codable { case allowed, check, notAllowed = "not_allowed" }
    let status: Status
    /// "2nd or 5th carriage (doors with the bike sign), max 4 bikes per door"
    let carriage: String?
    let note: String?

    /// Trenord publishes no per-train bike flag (every train is `check`); Velix offers those trains as allowed
    /// (Filippo, 23 Oct 2026). `not_allowed` is never offered.
    var offered: Bool { status != .notAllowed }
}

/// One direct run as Transitous returns it: the run, its calls from boarding to alighting, the line it runs on.
struct TransitConnection: Hashable, Sendable {
    let departure: TransitDeparture
    let stops: [TransitStopTime]
    /// The leg's geometry (Transitous `legGeometry`), empty when none.
    let line: [LatLon]
    /// The feed's own bikes flag (Transitous `bikesAllowed`): true only where operators publish it (the Netherlands).
    let feedAllowsBikes: Bool
}

enum TransitNames {
    /// Trenord's trip short name is "RE_80 - 25510": the train number is the last part.
    static func trainNumber(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s.components(separatedBy: " - ").last?.trimmingCharacters(in: .whitespaces)
    }

    /// Names published in capitals ("CENTRALE FS", "P.TA VENEZIA", ATM's): title case, keeping short all-caps
    /// abbreviations ("FS").
    static func displayName(_ name: String) -> String {
        guard name == name.uppercased(), name.contains(where: \.isLetter) else { return name }
        return name.split(separator: " ").map { w in
            let word = String(w)
            if ["DI", "DA", "DE", "DEL", "DELLA", "LA", "IL", "LE"].contains(word) { return word.lowercased() }
            return word.count <= 2 && word.allSatisfy(\.isLetter) ? word : word.prefix(1) + word.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    /// Metro lines published as a number (ATM "1"): "M1".
    static func metroLine(_ shortName: String) -> String {
        !shortName.isEmpty && shortName.allSatisfy(\.isNumber) ? "M" + shortName : shortName
    }
}
