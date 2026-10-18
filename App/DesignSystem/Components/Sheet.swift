import SwiftUI

/// Bottom-sheet surface used by RideTypePicker and MapStyleSheet: radius 24, grabber, e3.
struct VelixSheet<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat.velix.s) {
            Capsule().fill(Color.velix.line).frame(width: 36, height: 5).frame(maxWidth: .infinity)
            content
        }
        .padding(EdgeInsets(top: CGFloat.velix.xs, leading: CGFloat.velix.m, bottom: CGFloat.velix.m, trailing: CGFloat.velix.m))
        .background(Color.velix.surface, in: RoundedRectangle(cornerRadius: CGFloat.velix.radius.sheet))
        .velixElevation(VelixElevations.e3, in: RoundedRectangle(cornerRadius: CGFloat.velix.radius.sheet))
    }
}

/// Sheet close button (P4 S1g–i, S3): 36 pt circle on surface-2, 44 pt hit area.
struct SheetCloseButton: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            VelixIconView(.x, size: 18).foregroundStyle(Color.velix.ink)
                .frame(width: 36, height: 36)
                .background(Color.velix.surface2, in: Circle())
                .frame(width: CGFloat.velix.touch.min, height: CGFloat.velix.touch.min)
        }
        .buttonStyle(VelixPressStyle())
        .accessibilityLabel("Close")
    }
}

/// A full-width row with a chevron ("Edit rules in You ›", "Why this route ›").
struct ChevronRow: View {
    let title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).velixType(.label)
                Spacer()
                VelixIconView(.chevronRight, size: 18)
            }
            .foregroundStyle(Color.velix.ink)
            .frame(minHeight: CGFloat.velix.touch.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
