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
        // A label needs room: under 4 min (P4), or under a tenth of the trip, the wait goes unlabelled.
        let total = Double(minutes(p.seconds))
        func label(_ m: Int, _ text: String) -> String { m < 4 || Double(m) < 0.1 * total ? "" : text }
        return [.init(kind: .ride, minutes: minutes(p.rideIn.seconds), label: "Ride \(minutes(p.rideIn.seconds))"),
                .init(kind: .wait, minutes: wait, label: label(wait, "Wait \(wait)")),
                .init(kind: kind, minutes: minutes(p.onBoard), label: "\(p.departure.route.mode == .metro ? p.departure.route.shortName : "Train") \(minutes(p.onBoard))"),
                .init(kind: .wait, minutes: out, label: label(out, "Out \(out)")),
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

    // MARK: Riding with transit (P6 S5)

    /// What Fastest adds, from Best's and Fastest's analyses: "120 m of cobbles", "2 rail crossings"; nil when nothing.
    static func lateCost(best: RouteAnalysis, fastest: RouteAnalysis) -> String? {
        if let r = DifferenceCopy.avoidedReasons(best: best, fastest: fastest, rideType: .city).first {
            if case let .cobbles(m) = r { return "\(DifferenceCopy.distance(m)) of cobbles" }
            return r.text
        }
        let rails = fastest.hazardCount(.tram) - best.hazardCount(.tram)
        return rails > 0 ? (rails == 1 ? "1 rail crossing" : "\(rails) rail crossings") : nil
    }

    /// S5b: "Running late" / "Switched to the fastest route to catch the 08:16. It adds 120 m of cobbles."
    static func late(_ d: TransitDeparture, cost: String?) -> (title: String, message: String, short: String) {
        let catchIt = "catch the \(clock(d.departs))"
        return ("Running late", "Switched to the fastest route to \(catchIt)." + (cost.map { " It adds \($0)." } ?? ""),
                "Fastest route to \(catchIt)." + (cost.map { " +\($0.replacingOccurrences(of: " of ", with: " "))." } ?? ""))
    }

    /// S5c: "You’d miss the 08:16" / "Moved you to the 08:46. Arrival 09:05."
    static func missed(_ old: TransitDeparture, next: TransitPlan) -> (title: String, message: String) {
        ("You’d miss the \(clock(old.departs))", "Moved you to the \(clock(next.departure.departs)). Arrival \(clock(next.arrival)).")
    }

    static let lateVoice = "Running late. Taking the fastest route."
    static func missedVoice(_ next: TransitPlan) -> String { "New train: \(clock(next.departure.departs))." }

    /// The stage-1 ETA bar (P6 S5a): "08:12" "Centrale" "08:16 ·" "4 min to spare" (tight under 3 min).
    static func stationEta(_ p: TransitPlan, now: Date, eta: TimeInterval) -> EtaBar.State {
        let spare = TrainCatch.spare(departs: p.departure.departs, now: now, eta: eta, boarding: DirectPlanner.boarding(p.departure.route.mode))
        let mins = Int((spare / 60).rounded(.down))
        return .transit(arrival: clock(now.addingTimeInterval(eta)), at: short(p.departure.board),
                        train: "\(clock(p.departure.departs)) ·", spare: spare >= 0 ? "\(mins) min to spare" : "Late", tight: spare < 3 * 60)
    }

    /// S5d: the on-train sheet at `now`.
    static func onTrain(_ p: TransitPlan, now: Date, destination: Place) -> OnTrainCard {
        let d = p.departure
        let upcoming = p.stops.dropFirst().filter { $0.arrives > now }
        let left = max(0, upcoming.count - 1)
        let metro = d.route.mode == .metro
        let stops: [OnTrainCard.Stop] = p.stops.enumerated().map { i, st in
            let state: OnTrainCard.Stop.State = i == p.stops.count - 1 ? .end : st.departs <= now ? .departed : .next
            return .init(name: st.stop.name, time: clock(i == 0 ? st.departs : st.arrives), state: state)
        }
        let positions = BikeCarriages.positions(d.route)
        return OnTrainCard(train: "\(d.name) to \(short(d.alight))", getOff: "Get off at \(short(d.alight))",
                           stopsLeft: now < d.departs ? "Leaves at \(clock(d.departs))"
                               : left == 0 ? "Next stop" : left == 1 ? "1 stop before yours" : "\(left) stops before yours",
                           minutes: max(0, Int((d.arrives.timeIntervalSince(now) / 60).rounded(.up))),
                           stops: Array(stops.suffix(4)), carriages: positions,
                           carriageNote: positions == nil ? (p.rule.carriage ?? "Carriage with the bike area") : BikeCarriages.note(positions!),
                           arrival: "\(destination.name) \(clock(p.arrival))", metro: metro)
    }

    /// The lock screen on the train (P6 L3).
    static func trainActivity(_ p: TransitPlan, now: Date) -> RideActivityAttributes.Train {
        let next = p.stops.dropFirst().first { $0.arrives > now }
        let positions = BikeCarriages.positions(p.departure.route)
        return .init(station: short(p.departure.alight), next: next.map { "Next: \($0.stop.name)" } ?? "Next stop",
                     minutes: "\(max(0, Int((p.departure.arrives.timeIntervalSince(now) / 60).rounded(.up))))",
                     carriage: positions.map(BikeCarriages.note) ?? p.rule.carriage ?? "Carriage with the bike area",
                     arrival: clock(p.arrival), metro: p.departure.route.mode == .metro)
    }

    static func getOffVoice(_ p: TransitPlan) -> String { "Get ready. \(short(p.departure.alight)) in 2 minutes." }

    static func minutes(_ s: TimeInterval) -> Int { max(1, Int((s / 60).rounded())) }

    static func clock(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(timeZone: TimeZone(identifier: "Europe/Rome")!).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}

/// Where the bikes go on Milan's metro (ATM "Bici sui mezzi": M1–M3 the 2nd and 5th of 6 carriages, M4–M5 the first
/// or last of 4). Trenord doesn't say per train: nil, the rule's note instead.
enum BikeCarriages {
    static func positions(_ r: TransitRoute) -> [Bool]? {
        guard r.feed == "atm" else { return nil }
        switch r.shortName {
        case "M1", "M2", "M3": return [false, true, false, false, true, false]
        case "M4", "M5": return [true, false, false, true]
        default: return nil
        }
    }

    static func note(_ positions: [Bool]) -> String {
        positions == [false, true, false, false, true, false] ? "Bikes in the 2nd and 5th carriage"
            : positions.first == true && positions.last == true ? "Bikes in the first or last carriage"
            : positions.first == true ? "Bike carriage at the front" : "Carriage with the bike area"
    }
}
