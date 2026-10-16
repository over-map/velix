import SwiftUI

/// RideTypeChip (P2 §08, S1): the only place to pick the ride type; opens RideTypePicker.
struct RideTypeChip: View {
    let rideType: RideType
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: CGFloat.velix.xs) {
                VelixIconView(rideType.glyph, size: 24)
                Text(rideType.name).velixType(.label)
                VelixIconView(.chevronDown, size: 16)
            }
            .padding(.leading, 10).padding(.trailing, CGFloat.velix.s)
            .frame(height: CGFloat.velix.touch.min)
            .foregroundStyle(Color.velix.ink)
            .background(Color.velix.surface, in: Capsule())
            .velixElevation(VelixElevations.e1, in: Capsule())
        }
        .buttonStyle(VelixPressStyle())
        .accessibilityLabel("Ride type: \(rideType.name)")
        .accessibilityHint("Changes the ride type")
    }
}

#Preview {
    VStack(alignment: .leading) {
        ForEach(RideType.allCases, id: \.self) { RideTypeChip(rideType: $0) }
    }
    .padding().background(Color.velix.canvas)
}
