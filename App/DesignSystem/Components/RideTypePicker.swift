import SwiftUI

/// RideTypePicker (P2 §08): S1 sheet with 6 tiles, and the S0b onboarding list.
struct RideTypePicker: View {
    enum Variant { case sheet, onboarding }
    var variant: Variant = .sheet
    @Binding var selected: RideType
    var onContinue: () -> Void = {}

    var body: some View {
        VelixSheet {
            switch variant {
            case .sheet:
                Text("Ride type").velixType(.title2).foregroundStyle(Color.velix.ink).accessibilityAddTraits(.isHeader)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(RideType.allCases, id: \.self) { tile($0) }
                }
            case .onboarding:
                Text("How do you usually ride?").velixType(.title1).foregroundStyle(Color.velix.ink).accessibilityAddTraits(.isHeader)
                Text("You can switch on the map before any trip.").velixType(.callout).foregroundStyle(Color.velix.ink2)
                VStack(spacing: 0) {
                    ForEach(Array(RideType.allCases.enumerated()), id: \.element) { i, type in row(type, first: i == 0) }
                }
                PrimaryButton(title: "Continue", action: onContinue)
            }
        }
    }

    private func tile(_ type: RideType) -> some View {
        let isSelected = type == selected
        return Button { selected = type } label: {
            VStack(alignment: .leading, spacing: 6) {
                VelixIconView(type.glyph, size: 28)
                Text(type.name).velixType(.cardTitle)
                Text(type.bestName).velixType(.footnote).foregroundStyle(Color.velix.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(CGFloat.velix.s)
            .foregroundStyle(Color.velix.ink)
            .background(isSelected ? Color.velix.surface : .clear, in: RoundedRectangle(cornerRadius: CGFloat.velix.radius.card))
            .overlay(RoundedRectangle(cornerRadius: CGFloat.velix.radius.card)
                .strokeBorder(isSelected ? Color.velix.ink : Color.velix.line, lineWidth: isSelected ? 2 : 1))
            .overlay(alignment: .topTrailing) {
                if isSelected { VelixIconView(.circleCheck, size: 22).foregroundStyle(Color.velix.ink).padding(10) }
            }
        }
        .buttonStyle(VelixPressStyle())
        .accessibilityLabel("\(type.name), \(type.bestName)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private func row(_ type: RideType, first: Bool) -> some View {
        let isSelected = type == selected
        return Button { selected = type } label: {
            HStack(spacing: CGFloat.velix.s) {
                VelixIconView(type.glyph, size: 24)
                    .frame(width: 40, height: 40)
                    .background(Color.velix.surface2, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 0) {
                    Text(type.name).velixType(.rowTitle)
                    Text(type.bestName).velixType(.rowSubtitle).foregroundStyle(Color.velix.ink2)
                }
                Spacer(minLength: 0)
                if isSelected { VelixIconView(.circleCheck, size: 22) }
            }
            .foregroundStyle(Color.velix.ink)
            .padding(.vertical, CGFloat.velix.s)
            .frame(minHeight: 72)
            .overlay(alignment: .top) { if !first { Rectangle().fill(Color.velix.line).frame(height: 1) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(type.name), \(type.bestName)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 24) {
            RideTypePicker(selected: .constant(.city))
            RideTypePicker(variant: .onboarding, selected: .constant(.ebike))
        }
        .padding()
    }
    .background(Color.velix.canvas)
}
