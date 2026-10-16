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
        /// The next hazard while it is close (hazard emphasis).
        var hazard: Hazard?
    }

    struct Hazard: Codable, Hashable {
        var glyph: VelixGlyph
        /// "Tram rails"
        var title: String
        /// Short advice, "Cross straight".
        var advice: String
        /// "40 m"
        var distance: String
    }
}

extension VelixGlyph: Codable {}

extension RideActivityAttributes.ContentState {
    /// P2 sample (Milan).
    static let sample = Self(maneuver: .right, distance: "200 m", street: "Via Ampère", arrival: "08:42",
                             minutesLeft: "11 min", distanceLeft: "2.6 km")
    static let sampleHazard = Self(maneuver: .right, distance: "200 m", street: "Via Ampère", arrival: "08:42",
                                   minutesLeft: "11 min", distanceLeft: "2.6 km",
                                   hazard: .init(glyph: .hazardTram, title: "Tram rails", advice: "Cross straight", distance: "40 m"))
}
