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
    /// No hazard left on the route: the footer carries the trip.
    static let sampleClear = Self(maneuver: .right, distance: "200 m", street: "Via Ampère", arrival: "08:42",
                                  minutesLeft: "11 min", distanceLeft: "2.6 km")
}
