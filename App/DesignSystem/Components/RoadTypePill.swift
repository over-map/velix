import SwiftUI

/// RoadTypePill (P2 §08, S4): what you are riding on now. Swatch + label, never colour alone.
struct RoadTypePill: View {
    enum Kind: Hashable { case mix(MixCategory), walk }
    let kind: Kind
    var distance: String?

    var body: some View {
        HStack(spacing: 7) {
            switch kind {
            case let .mix(c): MixSwatch(category: c).frame(width: 14, height: 14).clipShape(RoundedRectangle(cornerRadius: 3))
            case .walk: VelixIconView(.hazardDismount, size: 16)
            }
            Text(text).lineLimit(1)
        }
        .velixType(VelixType.ridingLabel.sized(14, lineHeight: 18))
        .foregroundStyle(Color.velix.ink)
        .padding(.leading, kind == .walk ? 10 : 8).padding(.trailing, 10)
        .frame(height: 30)
        .background(Color.velix.surface2, in: RoundedRectangle(cornerRadius: 8))
        .overlay { if kind == .walk { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.velix.ink, lineWidth: 1.5) } }
    }

    private var text: String {
        let name = switch kind { case let .mix(c): c.label; case .walk: "Walk" }
        return distance.map { "\(name) · \($0)" } ?? name
    }
}

#Preview {
    VStack(alignment: .leading) {
        ForEach(MixCategory.allCases, id: \.self) { RoadTypePill(kind: .mix($0)) }
        RoadTypePill(kind: .walk, distance: "40 m")
    }
    .padding().background(Color.velix.canvas)
}
