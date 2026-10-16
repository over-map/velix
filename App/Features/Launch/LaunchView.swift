import SwiftUI

/// M0 placeholder: proves the app builds and the bundled fonts load.
/// Replaced by S0 First launch / S1 Ride in M6.
struct LaunchView: View {
    var body: some View {
        VStack(spacing: CGFloat.velix.xs) {
            Text("Velix").velixType(.display)
            Text("ride smooth").velixType(.body)
        }
        .foregroundStyle(Color.velix.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.velix.canvas)
    }
}

#Preview("Light") { LaunchView() }
#Preview("Dark") { LaunchView().preferredColorScheme(.dark) }
