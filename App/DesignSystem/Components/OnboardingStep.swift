import SwiftUI

/// OnboardingStep (P2 §08, S0): page dots, title, one line of why, the step's content and its button.
struct OnboardingStep<Content: View>: View {
    let step: Int
    var count = 3
    let title: String
    let message: String
    let button: PrimaryButton
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                ForEach(0 ..< count, id: \.self) { i in
                    Capsule().fill(i == step ? Color.velix.ink : Color.velix.line).frame(width: i == step ? 18 : 6, height: 6)
                }
            }
            .accessibilityElement().accessibilityLabel("Step \(step + 1) of \(count)")
            Text(title).velixType(VelixType.title2.sized(22, lineHeight: 25)).foregroundStyle(Color.velix.ink).padding(.top, 6)
            Text(message).velixType(VelixType.body.sized(14, lineHeight: 20)).foregroundStyle(Color.velix.ink2)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            button
        }
        .padding(18)
        .background(Color.velix.surface, in: RoundedRectangle(cornerRadius: 24))
        .velixElevation(VelixElevations.e1, in: RoundedRectangle(cornerRadius: 24))
    }
}

/// Compact ride-type choice of the onboarding card (three shown, "+3 more").
struct OnboardingRideTypeList: View {
    @Binding var selected: RideType
    var shown: [RideType] = [.city, .ebike, .road]
    var body: some View {
        VStack(spacing: 6) {
            ForEach(shown, id: \.self) { type in
                Button { selected = type } label: {
                    HStack(spacing: 10) {
                        VelixIconView(type.glyph, size: 22)
                        Text(type.name).velixType(.label)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Color.velix.ink)
                    .padding(.horizontal, 10).frame(height: 40)
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(type == selected ? Color.velix.ink : Color.velix.line, lineWidth: type == selected ? 2 : 1))
                    .frame(minHeight: CGFloat.velix.touch.min)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(type == selected ? .isSelected : [])
            }
            Text("+\(RideType.allCases.count - shown.count) more").velixType(VelixType.body.sized(12, lineHeight: 15))
                .foregroundStyle(Color.velix.ink3).frame(maxWidth: .infinity)
        }
    }
}
