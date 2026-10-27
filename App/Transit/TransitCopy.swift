import Foundation

/// The words for bike + transit (P4 S3d row, S3e card), from a plan and the bike-only options.
enum TransitCopy {
    /// "Long ride? Hop on the train with your bike" (BRIEF §8 copy).
    static func rowTitle(_ p: TransitPlan) -> String {
        "Long ride? Hop on the \(p.departure.route.mode == .metro ? "metro" : "train") with your bike"
    }

    /// "**21 min faster** · ride to Centrale, train to Monza, ride into the park".
    static func rowSubtitle(_ p: TransitPlan, bikeSeconds: TimeInterval, destination: Place) -> String {
        let saved = max(1, Int(((bikeSeconds - p.seconds) / 60).rounded()))
        let vehicle = p.departure.route.mode == .metro ? p.departure.route.shortName : "train"
        return "**\(saved) min faster** · ride to \(short(p.departure.board)), \(vehicle) to \(short(p.departure.alight)), "
            + lastRide(destination)
    }

    /// "ride into the park" (P4) for a park, else "ride to Villa Reale".
    static func lastRide(_ destination: Place) -> String {
        destination.kind == .park ? "ride into the park" : "ride to \(destination.name)"
    }

    /// Card title: "Bike + train", "Bike + M1".
    static func cardTitle(_ p: TransitPlan) -> String {
        p.departure.route.mode == .metro ? "Bike + \(p.departure.route.shortName)" : "Bike + train"
    }

    /// "13 min by bike · arrive 08:36"
    static func cardSubtitle(_ p: TransitPlan) -> String {
        "\(minutes(p.bikeSeconds)) min by bike · arrive \(clock(p.arrival))"
    }

    /// "Trenord RE80 25510 · 08:43 → Monza 08:52"
    static func trainLine(_ p: TransitPlan) -> String {
        "\(p.departure.name) · \(clock(p.departure.departs)) → \(short(p.departure.alight)) \(clock(p.departure.arrives))"
    }

    /// "Ride 7 min to Centrale · platform planned: check the board · bikes allowed · ride 6 min into the park"
    static func detail(_ p: TransitPlan, destination: Place) -> String {
        var parts = ["Ride \(minutes(p.rideIn.seconds)) min to \(short(p.departure.board))"]
        // GTFS has no platforms: say where to look instead of a number (BRIEF: platforms are "planned").
        if p.departure.route.mode == .rail { parts.append("platform planned: check the board") }
        parts.append("bikes allowed")
        let last = destination.kind == .park ? "into the park" : "to \(destination.name)"
        parts.append("ride \(minutes(p.rideOut.seconds)) min \(last)")
        return parts.joined(separator: " · ")
    }

    /// The operator's ticket page (one link, BRIEF §8).
    static func ticket(_ p: TransitPlan) -> (label: String, url: URL) {
        p.departure.route.feed == "atm"
            ? ("Ticket · ATM", URL(string: "https://www.atm.it/it/ViaggiaConNoi/Biglietti/Pagine/default.aspx")!)
            : ("Ticket · Trenord", URL(string: "https://www.trenord.it/biglietti/")!)
    }

    /// Replaces P4's "Illustrative timetable": the times are the static GTFS, no live delays.
    static let footnote = "Timetable as planned, no live delays"

    /// "Bike only · **52 min** Best · 45 min Fastest"
    static func bikeOnly(best: TimeInterval, fastest: TimeInterval?) -> String {
        "Bike only · **\(minutes(best)) min** Best" + (fastest.map { " · \(minutes($0)) min Fastest" } ?? "")
    }

    /// TripBar: Ride · Wait · Train · Out · Ride (P4: a wait under 4 min carries no label).
    @MainActor static func segments(_ p: TransitPlan) -> [TripBar.Segment] {
        let kind: TripBar.Kind = p.departure.route.mode == .metro
            ? .metro(MetroBadge.family(metroFamily(p.departure.route), name: p.departure.route.shortName).color) : .train
        let wait = minutes(p.wait), out = minutes(DirectPlanner.outOfStation)
        return [.init(kind: .ride, minutes: minutes(p.rideIn.seconds), label: "Ride \(minutes(p.rideIn.seconds))"),
                .init(kind: .wait, minutes: wait, label: wait < 4 ? "" : "Wait \(wait)"),
                .init(kind: kind, minutes: minutes(p.onBoard), label: "\(p.departure.route.mode == .metro ? p.departure.route.shortName : "Train") \(minutes(p.onBoard))"),
                .init(kind: .wait, minutes: out, label: out < 4 ? "" : "Out \(out)"),
                .init(kind: .ride, minutes: minutes(p.rideOut.seconds), label: "Ride \(minutes(p.rideOut.seconds))")]
    }

    /// Milan metro lines by number (the P3 families; ATM's GTFS colours are the same lines).
    static func metroFamily(_ r: TransitRoute) -> String {
        ["M1": "red", "M2": "green", "M3": "yellow", "M4": "blue", "M5": "purple"][r.shortName] ?? "grey"
    }

    /// "Milano Centrale" → "Centrale" (the city is implied); other names as they are.
    static func short(_ s: TransitStop) -> String {
        s.name.hasPrefix("Milano ") ? String(s.name.dropFirst(7)) : s.name
    }

    static func minutes(_ s: TimeInterval) -> Int { max(1, Int((s / 60).rounded())) }

    static func clock(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(timeZone: TimeZone(identifier: "Europe/Rome")!).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}
