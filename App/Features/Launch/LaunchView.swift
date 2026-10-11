import SwiftUI

/// M0 placeholder: proves the app builds and the bundled fonts load.
/// Replaced by S0 First launch / S1 Ride in M6.
struct LaunchView: View {
    var body: some View {
        VStack(spacing: Bootstrap.Spacing.xs) {
            Text("Velix")
                .font(Bootstrap.Font.display)
                .tracking(Bootstrap.Font.displayTracking)
            Text("ride smooth")
                .font(Bootstrap.Font.body)
        }
        .foregroundStyle(Bootstrap.Color.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Bootstrap.Color.canvas)
    }
}

#Preview("Light") { LaunchView() }
#Preview("Dark") { LaunchView().preferredColorScheme(.dark) }
