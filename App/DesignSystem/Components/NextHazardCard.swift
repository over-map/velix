import SwiftUI

/// NextHazardCard (P2 §08, S4): the next hazard ahead and what to do. Fills coral when approaching (< 50 m, with
/// haptic + voice in M7). `compact` is the small card of the all-types grid.
struct NextHazardCard: View {
    let type: HazardType
    /// "Cross straight, at a right angle"; defaults to the type's advice.
    var advice: String?
    var distance: String?
    var approaching = false
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 10 : 12) {
            VelixIconView(type.glyph, size: compact ? 24 : 34)
                .foregroundStyle(approaching ? Color.velix.hazard : Color.velix.hazardInk)
                .frame(width: compact ? 40 : 56, height: compact ? 40 : 56)
                .background(approaching ? Color.velix.hazardInk : Color.velix.hazard,
                            in: RoundedRectangle(cornerRadius: compact ? 10 : 14))
            VStack(alignment: .leading, spacing: 0) {
                Text(compact ? type.title : type.shortTitle)
                    .velixType(compact ? VelixType.headline.sized(15, lineHeight: 18) : VelixType.ridingStreet.sized(20, lineHeight: 23))
                    .foregroundStyle(approaching ? Color.velix.hazardInk : Color.velix.ink)
                Text(advice ?? type.advice)
                    .velixType(compact ? VelixType.body.sized(13, lineHeight: 17) : VelixType.ridingLabel.sized(15, lineHeight: 19))
                    .foregroundStyle(approaching ? Color.velix.hazardInk : Color.velix.ink2)
            }
            Spacer(minLength: 0)
            if let distance {
                Text(distance).velixType(.ridingNumber).foregroundStyle(approaching ? Color.velix.hazardInk : Color.velix.ink)
            }
        }
        .padding(compact ? EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8) : EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 16))
        .background(approaching ? Color.velix.hazard : Color.velix.surface, in: RoundedRectangle(cornerRadius: compact ? 14 : 20))
        .velixElevation(approaching ? VelixElevations.e0 : VelixElevations.e1, in: RoundedRectangle(cornerRadius: compact ? 14 : 20))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(type.title)\(distance.map { " in \($0)" } ?? ""). \(advice ?? type.advice)")
    }
}

extension HazardType {
    /// Riding card title (P2 NextHazardCard).
    var shortTitle: String { self == .tram ? "Tram rails" : title }

    /// Default advice (P2 copy; the app fills real lengths, grades and step counts).
    var advice: String {
        switch self {
        case .tram: "Cross straight, at a right angle"
        case .along: "Keep clear of the groove"
        case .cobbles: "Rough surface ahead"
        case .lane: "Mixed traffic, take the lane"
        case .dismount: "Walk your bike"
        case .steps: "Carry your bike"
        case .gap: "Barrier ahead, slow down"
        case .descent: "Steep downhill, brake early"
        case .climb: "Steep uphill, shift down early"
        case .door: "Parked cars, ride a door’s width out"
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        NextHazardCard(type: .tram, distance: "120 m")
        NextHazardCard(type: .tram, distance: "40 m", approaching: true)
        NextHazardCard(type: .cobbles, advice: "Rough surface for 300 m", compact: true)
    }
    .padding().background(Color.velix.canvas)
}
