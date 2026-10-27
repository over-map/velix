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
    /// Bike + transit (P6): the stage strip on top of the banner.
    var stage: StageStrip?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let stage { stage }
            HStack(spacing: 14) {
                maneuver.icon(size: 48)
                    .foregroundStyle(Color.velix.accentInk)
                    .frame(width: 72, height: 72)
                    .background(Color.velix.accent, in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 4) {
                    Text(distance).velixType(.ridingBigNumber).lineLimit(1).minimumScaleFactor(0.7)
                    Text(street).velixType(VelixType.ridingStreet.sized(24, lineHeight: 28)).lineLimit(1).truncationMode(.tail)
                }
                .foregroundStyle(Color.velix.ink)
                Spacer(minLength: 0)
            }
            if then != nil || roadType != nil {
                // P5: the row wraps at large text (the pill drops under "Then"), P8.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { thenRow; Spacer(minLength: 0); pill }
                    VStack(alignment: .leading, spacing: 8) { thenRow; pill }
                }
                .padding(.top, 12)
                .overlay(alignment: .top) { Rectangle().fill(Color.velix.line).frame(height: 1) }
            }
        }
        .padding(.horizontal, CGFloat.velix.m).padding(.vertical, 14)
        .background(Color.velix.surface, in: RoundedRectangle(cornerRadius: 24))
        .velixElevation(VelixElevations.e1, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var thenRow: some View {
        if let then {
            HStack(spacing: 6) {
                Text("Then")
                then.maneuver.icon(size: 20)
                if !then.street.isEmpty { Text(then.street).lineLimit(1) }
            }
            .velixType(VelixType.ridingLabel.sized(17, lineHeight: 21))
            .foregroundStyle(Color.velix.ink2)
            .fixedSize()
        }
    }

    @ViewBuilder private var pill: some View {
        if let roadType { RoadTypePill(kind: roadType, distance: roadTypeDistance).fixedSize() }
    }

    /// P8: "Turn left in 160 metres onto Via Nino Bixio. Then turn right onto Piazza Adelaide. Quiet street."
    private var accessibilityText: String {
        let spokenDistance = distance.replacingOccurrences(of: " km", with: " kilometres").replacingOccurrences(of: " m", with: " metres")
        var t = maneuver == .arrive ? "Arrive in \(spokenDistance), \(street)." : "\(maneuver.spoken) in \(spokenDistance) onto \(street)."
        if let then { t += " Then \(then.maneuver.spoken.lowercased())\(then.street.isEmpty ? "" : " onto \(then.street)")." }
        if case let .mix(c)? = roadType { t += " \(c.label)." }
        return t
    }
}

/// The banner while rerouting (P5 S4g): no turn, no sound, no red.
struct RerouteBanner: View {
    var body: some View {
        HStack(spacing: 14) {
            VelixIconView(.loader, size: 40)
                .foregroundStyle(Color.velix.ink)
                .frame(width: 72, height: 72)
                .background(Color.velix.surface2, in: RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 4) {
                Text("Rerouting").velixType(VelixType.ridingStreet.sized(30, lineHeight: 32))
                Text("Keep riding. Back to the calm route in a moment.").velixType(VelixType.ridingLabel.sized(17, lineHeight: 22))
                    .foregroundStyle(Color.velix.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color.velix.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CGFloat.velix.m).padding(.vertical, 14)
        .background(Color.velix.surface, in: RoundedRectangle(cornerRadius: 24))
        .velixElevation(VelixElevations.e1, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
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

/// StageStrip (P6): the three stages of a bike + transit trip on top of the maneuver banner. Current in accent with
/// the ink casing, done ticked, next outlined. Not tappable: the trip moves on by itself.
struct StageStrip: View, Equatable {
    /// 1, 2 or 3: ride to the station, on the train (or metro), ride.
    let current: Int
    var metro = false

    private var labels: [String] { ["Ride to station", metro ? "On the metro" : "On the train", "Ride"] }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                let stage = i + 1
                HStack(spacing: 5) {
                    if stage < current { VelixIconView(.check, size: 14) }
                    Text(label).velixType(VelixType.ridingLabel.sized(13, lineHeight: 16)).lineLimit(1).minimumScaleFactor(0.8)
                }
                .foregroundStyle(stage == current ? Color.velix.accentInk : stage < current ? Color.velix.ink2 : Color.velix.ink3)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity).frame(height: 30)
                .background(stage == current ? Color.velix.accent : stage < current ? Color.velix.surface2 : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(stage == current ? Color.velix.casing : Color.velix.line,
                                                                   lineWidth: stage == current ? 1.5 : stage > current ? 1 : 0)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        // P8: "Stage 1 of 3, ride to station. Next: on the train." Not a button.
        .accessibilityLabel("Stage \(current) of 3, \(labels[max(0, min(2, current - 1))].lowercased())."
                            + (current < 3 ? " Next: \(labels[current].lowercased())." : ""))
    }
}

#Preview {
    VStack(spacing: 16) {
        ManeuverBanner(maneuver: .right, distance: "200 m", street: "Via Ampère", then: (.left, "Via Celoria"),
                       roadType: .mix(.protected), roadTypeDistance: "600 m")
        ManeuverBanner(maneuver: .arrive, distance: "80 m", street: "Politecnico, on the right")
        RerouteBanner()
        StageStrip(current: 1)
        StageStrip(current: 3)
    }
    .padding().background(Color.velix.canvas)
}
