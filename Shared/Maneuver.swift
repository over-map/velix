import SwiftUI

/// Turn types drawn by ManeuverBanner and the Live Activity (P2 §08 ManeuverBanner: Ferrostar set, Lucide + custom
/// roundabout). Shared with the Live Activity extension.
enum Maneuver: String, Codable, Hashable, CaseIterable, Sendable {
    case straight, slightRight, right, sharpRight, slightLeft, left, sharpLeft, uTurn, roundabout, merge, arrive

    var label: String {
        switch self {
        case .straight: "Straight"
        case .slightRight: "Slight right"
        case .right: "Right"
        case .sharpRight: "Sharp right"
        case .slightLeft: "Slight left"
        case .left: "Left"
        case .sharpLeft: "Sharp left"
        case .uTurn: "U-turn"
        case .roundabout: "Roundabout"
        case .merge: "Merge"
        case .arrive: "Arrive"
        }
    }

    /// VoiceOver phrase (P8 S4: "Turn left in 160 metres onto Via Nino Bixio").
    var spoken: String {
        switch self {
        case .straight: "Go straight"
        case .slightRight: "Bear right"
        case .right: "Turn right"
        case .sharpRight: "Turn sharp right"
        case .slightLeft: "Bear left"
        case .left: "Turn left"
        case .sharpLeft: "Turn sharp left"
        case .uTurn: "Make a U-turn"
        case .roundabout: "Take the roundabout"
        case .merge: "Merge"
        case .arrive: "Arrive"
        }
    }

    /// Lucide has no slight / sharp left: the right-hand arrows mirrored.
    private var mirrored: Bool { self == .slightLeft || self == .sharpLeft }

    private var image: Image {
        switch self {
        case .straight: Image(velix: .arrowUp)
        case .slightRight, .slightLeft: Image(velix: .arrowUpRight)
        case .right: Image(velix: .cornerUpRight)
        case .sharpRight, .sharpLeft: Image(velix: .arrowDownRight)
        case .left: Image(velix: .cornerUpLeft)
        case .uTurn: Image(velix: .undo2)
        case .roundabout: Image(velix: .roundabout)
        case .merge: Image(velix: .merge)
        case .arrive: Image(velix: .flag)
        }
    }

    /// The turn arrow at `size` pt, template-rendered.
    func icon(size: CGFloat) -> some View {
        image.resizable().renderingMode(.template).scaledToFit()
            .frame(width: size, height: size)
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            .accessibilityHidden(true)
    }
}
