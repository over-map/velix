import SwiftUI

/// StreetTag: the street of the next turn, on the route just past it, while riding (Filippo, 7 Nov, after Apple Maps:
/// which street to turn into). Drawn into the map by ``MapImages`` (`street-<id>`); the tail points at the street.
struct StreetTag: View {
    let name: String
    var body: some View {
        VStack(spacing: 0) {
            Text(name)
                .velixType(VelixType.label.sized(15, lineHeight: 19))
                .lineLimit(1)
                .foregroundStyle(Color.velix.accentInk)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.velix.accent, in: RoundedRectangle(cornerRadius: CGFloat.velix.radius.chip))
                .overlay { RoundedRectangle(cornerRadius: CGFloat.velix.radius.chip).strokeBorder(Color.velix.casing, lineWidth: 1.5) }
            Triangle().fill(Color.velix.casing).frame(width: 12, height: 6)
        }
        .accessibilityHidden(true)   // the maneuver banner says the street
    }
}

#Preview {
    VStack(spacing: 16) {
        StreetTag(name: "Via Giovanni Bellezza")
        StreetTag(name: "Via Altaguardia")
    }
    .padding().background(Color.velix.canvas)
}
