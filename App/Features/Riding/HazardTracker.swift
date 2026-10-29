import Foundation

/// The next hazard ahead and its alert (P5 S4a/S4e: one card at a time; under 50 m it turns coral, the phone taps
/// twice and the voice says it once). Pure: positions in, events out.
struct HazardTracker: Sendable {
    /// Hazards that alert while riding: the shown types, gaps only when narrow (a cycle barrier, not a garden gate).
    let hazards: [RouteHazard]
    /// Hazards already announced, by type and OSM element: kept across reroutes, so the rails just crossed don't
    /// alert again on the new route.
    private(set) var alerted: Set<String>

    /// Alert distance; earlier when GPS is weak (S4h "Hazard alerts still fire, a little earlier").
    static let alertDistance = 50.0
    static let weakAlertDistance = 70.0
    /// A hazard counts as passed this far beyond its start (P5 maps keep hazards with `h.d > d − 4`).
    static let passed = 4.0

    init(hazards: [RouteHazard], alerted: Set<String> = []) {
        self.alerted = alerted
        self.hazards = hazards
            .filter { $0.type.shown && ($0.type != .gap || RuleChecker.isNarrowGap($0.detail)) }
            .sorted { $0.distanceAlong < $1.distanceAlong }
    }

    struct Next: Equatable, Sendable {
        let index: Int
        let hazard: RouteHazard
        let distance: Double
        /// Under the alert distance: the card is coral.
        let approaching: Bool
    }

    /// The first hazard not yet passed.
    func next(at position: Double, gps: GPSQuality = .good) -> Next? {
        guard let i = hazards.firstIndex(where: { $0.distanceAlong > position - Self.passed }) else { return nil }
        let h = hazards[i]
        let d = max(0, h.distanceAlong - position)
        return Next(index: i, hazard: h, distance: d, approaching: d <= limit(gps))
    }

    /// The hazard to alert for now (once each), if any.
    mutating func alert(at position: Double, gps: GPSQuality = .good) -> RouteHazard? {
        guard let n = next(at: position, gps: gps), n.approaching, !alerted.contains(Self.key(n.hazard)) else { return nil }
        alerted.insert(Self.key(n.hazard))
        return n.hazard
    }

    static func key(_ h: RouteHazard) -> String { "\(h.type.rawValue)-\(h.osm)" }

    private func limit(_ gps: GPSQuality) -> Double { gps == .weak ? Self.weakAlertDistance : Self.alertDistance }
}

/// Card advice and voice prompt for a hazard (design/tools/p5gen.js `HZ`), with the route's real lengths, grades
/// and step counts. Voice prompts stay within six words.
enum HazardPrompt {
    static func advice(_ h: RouteHazard) -> String {
        switch h.type {
        case .tram: "Cross straight, at a right angle"
        case .along: "Keep clear of the groove"
        case .cobbles: "Rough surface for \(metres(h.lengthM))"
        case .lane: "Mixed traffic, take the lane"
        case .dismount: "Walk your bike for \(metres(h.lengthM))"
        case .steps: steps(h).map { "Carry your bike up \($0) steps" } ?? "Carry your bike"
        case .gap: "Barrier ahead, slow down"
        case .descent: "\(grade(h) ?? "Steep"), brake early"
        case .climb: "\(grade(h) ?? "Steep"), shift down early"
        case .door: "Parked cars, ride a door’s width out"
        }
    }

    /// Lock-screen advice, one short line next to a 40 pt distance (P5 L2 "Cross straight").
    static func short(_ h: RouteHazard) -> String {
        switch h.type {
        case .tram: "Cross straight"
        case .along: "Keep clear"
        case .cobbles: "Rough for \(metres(h.lengthM))"
        case .lane: "Take the lane"
        case .dismount: "Walk \(metres(h.lengthM))"
        case .steps: "Carry your bike"
        case .gap: "Slow down"
        case .descent: "Brake early"
        case .climb: "Shift down early"
        case .door: "Ride out wider"
        }
    }

    static func voice(_ h: RouteHazard) -> String {
        switch h.type {
        case .tram: "Tram rails ahead. Cross straight."
        case .along: "Rails along the lane. Keep clear."
        case .cobbles: "Cobbles for \(spoken(h.lengthM))."
        case .lane: "Lane ends. Take the lane."
        case .dismount: "Walk your bike, \(spoken(h.lengthM))."
        case .steps: "Steps ahead. Carry your bike."
        case .gap: "Narrow gap. Slow down."
        case .descent: "Steep descent. Brake early."
        case .climb: "Steep climb. Shift down now."
        case .door: "Parked cars. Ride out wider."
        }
    }

    /// The card title: "Tram rails" (the card drops " crossing", P5 `hz()`).
    static func title(_ h: RouteHazard) -> String { h.type == .tram ? "Tram rails" : h.type.title }

    /// "300 m": nearest 10 m under 100, nearest 50 above.
    static func metres(_ m: Double) -> String { "\(rounded(m)) m" }
    static func spoken(_ m: Double) -> String { "\(rounded(m)) metres" }

    private static func rounded(_ m: Double) -> Int {
        m < 100 ? max(10, Int((m / 10).rounded()) * 10) : Int((m / 50).rounded()) * 50
    }

    /// "−9% for 200 m" from the analyzer's steep-stretch detail ("+8% for 400 m" / "−9% for 200 m").
    private static func grade(_ h: RouteHazard) -> String? { h.detail.contains("%") ? h.detail : nil }

    /// Step count from the sidecar detail (OSM `step_count`), when known.
    private static func steps(_ h: RouteHazard) -> Int? { Int(h.detail) }
}
