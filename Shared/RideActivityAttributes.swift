import ActivityKit
import SwiftUI

/// Live Activity payload for a ride. The app formats every string; the extension only lays them out (P2 LiveActivity).
struct RideActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var maneuver: Maneuver
        /// Distance to the maneuver, "200 m".
        var distance: String
        var street: String
        /// Arrival clock time, "08:42".
        var arrival: String
        /// "11 min"
        var minutesLeft: String
        /// "2.6 km"
        var distanceLeft: String
        /// The next hazard while it is close (hazard emphasis, P5 L2 / D2 / D5).
        var hazard: Hazard?
        /// The next hazard at any distance, for the footer line (P5 L1 / D4 "Tram rails in 160 m").
        var nextHazard: NextHazard?
        /// Bike + transit (P6): on the train, the countdown to the stop (L3, D6).
        var train: Train?
        /// Late or missed (P6 D7), with the spare time at the station ("2 min to spare").
        var notice: Notice?
        var spare: String?
    }

    struct Train: Codable, Hashable {
        /// "Monza"
        var station: String
        /// "Next: Sesto San Giovanni"
        var next: String
        /// "6"
        var minutes: String
        /// "Bike carriage at the front"
        var carriage: String
        /// Final arrival, "08:36"
        var arrival: String
        var metro: Bool = false
    }

    struct Notice: Codable, Hashable {
        /// "Running late"
        var title: String
        /// "Fastest route to catch the 08:16. +120 m cobbles."
        var message: String
    }

    struct NextHazard: Codable, Hashable {
        var glyph: VelixGlyph
        /// "Tram rails in 160 m"
        var text: String
    }

    struct Hazard: Codable, Hashable {
        var glyph: VelixGlyph
        /// "Tram rails"
        var title: String
        /// Short advice for the lock screen, "Cross straight".
        var advice: String
        /// The riding card's advice for the expanded island (P5 D5), "Cross straight, at a right angle".
        var longAdvice: String?
        /// "40 m"
        var distance: String
    }
}

extension VelixGlyph: Codable {}

extension RideActivityAttributes.ContentState {
    /// P5 L1 / D4 sample (the Politecnico trip).
    static let sample = Self(maneuver: .left, distance: "160 m", street: "Via Nino Bixio", arrival: "08:42",
                             minutesLeft: "18 min", distanceLeft: "4.4 km",
                             nextHazard: .init(glyph: .hazardTram, text: "Tram rails in 160 m"))
    /// P5 L2 / D5: the rails 35 m ahead, the turn 40 m.
    static let sampleHazard = Self(maneuver: .left, distance: "40 m", street: "Via Nino Bixio", arrival: "08:42",
                                   minutesLeft: "18 min", distanceLeft: "4.4 km",
                                   hazard: .init(glyph: .hazardTram, title: "Tram rails", advice: "Cross straight",
                                                 longAdvice: "Cross straight, at a right angle", distance: "35 m"))
    /// P6 L3 / D6: on the train.
    static let sampleTrain = Self(maneuver: .straight, distance: "", street: "", arrival: "08:36", minutesLeft: "15 min", distanceLeft: "2.0 km",
                                  train: .init(station: "Monza", next: "Next: Sesto San Giovanni", minutes: "6",
                                               carriage: "Bike carriage at the front", arrival: "08:36"))
    /// P6 D7: running late, switched to Fastest.
    static let sampleLate = Self(maneuver: .left, distance: "370 m", street: "Via Boscovich", arrival: "08:14", minutesLeft: "4 min",
                                 distanceLeft: "1.2 km",
                                 notice: .init(title: "Running late", message: "Fastest route to catch the 08:16. +120 m cobbles."),
                                 spare: "2 min to spare")
    /// No hazard left on the route: the footer carries the trip.
    static let sampleClear = Self(maneuver: .right, distance: "200 m", street: "Via Ampère", arrival: "08:42",
                                  minutesLeft: "11 min", distanceLeft: "2.6 km")
}
