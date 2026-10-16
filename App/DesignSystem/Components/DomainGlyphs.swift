import SwiftUI

/// Glyphs for routing types (app target only; the Live Activity extension compiles the design system without
/// Components/ and the routing model).
extension RideType {
    var glyph: VelixGlyph {
        switch self {
        case .city: .rideTypeCity
        case .ebike: .rideTypeEBike
        case .road: .rideTypeRoad
        case .gravel: .rideTypeGravel
        case .mtb: .rideTypeMtb
        case .cargo: .rideTypeCargoKids
        }
    }
}

extension HazardType {
    var glyph: VelixGlyph {
        switch self {
        case .tram: .hazardTram
        case .along: .hazardAlong
        case .cobbles: .hazardCobbles
        case .steps: .hazardSteps
        case .gap: .hazardGap
        case .dismount: .hazardDismount
        case .lane: .hazardLane
        case .door: .hazardDoor
        case .descent: .hazardDescent
        case .climb: .hazardClimb
        }
    }
}
