import SwiftUI

/// ManeuverBanner (P2 §08, S4/S5): the next turn in big type, the following turn and the road type underneath.
struct ManeuverBanner: View {
    let maneuver: Maneuver
    /// "200 m"
    let distance: String
    let street: String
    var then: (maneuver: Maneuver, street: String)?
    var roadType: RoadTypePill.Kind?
    var roadTypeDistance: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                maneuver.icon(size: 48)
                    .foregroundStyle(Color.velix.accentInk)
                    .frame(width: 72, height: 72)
                    .background(Color.velix.accent, in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 4) {
                    Text(distance).velixType(.ridingBigNumber).lineLimit(1).minimumScaleFactor(0.7)
                    Text(street).velixType(VelixType.ridingStreet.sized(24, lineHeight: 28)).lineLimit(2)
                }
                .foregroundStyle(Color.velix.ink)
                Spacer(minLength: 0)
            }
            if then != nil || roadType != nil {
                HStack(spacing: 8) {
                    if let then {
                        HStack(spacing: 6) {
                            Text("Then")
                            then.maneuver.icon(size: 20)
                            Text(then.street).lineLimit(1)
                        }
                        .velixType(.ridingLabel)
                        .foregroundStyle(Color.velix.ink2)
                    }
                    Spacer(minLength: 0)
                    if let roadType { RoadTypePill(kind: roadType, distance: roadTypeDistance).layoutPriority(1) }
                }
                .padding(.top, 12)
                .overlay(alignment: .top) { Rectangle().fill(Color.velix.line).frame(height: 1) }
            }
        }
        .padding(.horizontal, CGFloat.velix.m).padding(.vertical, 14)
        .background(Color.velix.surface, in: RoundedRectangle(cornerRadius: 24))
        .velixElevation(VelixElevations.e1, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(maneuver.label) in \(distance), \(street)")
    }
}

/// Turn-type tile (P2 turn types row): 48 pt accent tile with the arrow, label under it.
struct ManeuverTile: View {
    let maneuver: Maneuver
    var body: some View {
        VStack(spacing: 4) {
            maneuver.icon(size: 30)
                .foregroundStyle(Color.velix.accentInk)
                .frame(width: 48, height: 48)
                .background(Color.velix.accent, in: RoundedRectangle(cornerRadius: 12))
            Text(maneuver.label).velixType(VelixType.body.sized(11, lineHeight: 13)).foregroundStyle(Color.velix.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(width: 64)
    }
}

/// StageStrip (P2 §08 ManeuverBanner, S5): the stages of a bike + transit trip, the current one filled.
struct StageStrip: View {
    enum Stage: Hashable {
        case ride, train, metro
        var label: String { switch self { case .ride: "Ride"; case .train: "Train"; case .metro: "Metro" } }
        var glyph: VelixGlyph { switch self { case .ride: .rideTypeCity; case .train: .train; case .metro: .metro } }
    }
    let stages: [Stage]
    let current: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(stages.enumerated()), id: \.offset) { i, stage in
                let isCurrent = i == current
                HStack(spacing: 6) {
                    VelixIconView(stage.glyph, size: 18)
                    Text(stage.label).velixType(VelixType.ridingLabel.sized(14, lineHeight: 18))
                }
                .foregroundStyle(isCurrent ? Color.velix.surface : Color.velix.ink2)
                .frame(maxWidth: .infinity).frame(height: 36)
                .background(isCurrent ? Color.velix.ink : Color.velix.surface, in: RoundedRectangle(cornerRadius: 10))
                .velixElevation(isCurrent ? VelixElevations.e0 : VelixElevations.e1, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        ManeuverBanner(maneuver: .right, distance: "200 m", street: "Via Ampère", then: (.left, "Via Celoria"),
                       roadType: .mix(.protected), roadTypeDistance: "600 m")
        ManeuverBanner(maneuver: .arrive, distance: "80 m", street: "Politecnico, on the right")
        StageStrip(stages: [.ride, .train, .ride], current: 0)
    }
    .padding().background(Color.velix.canvas)
}
