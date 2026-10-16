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
