@preconcurrency import FerrostarCore
import FerrostarMapLibreUI
import FerrostarSwiftUI
import MapLibreSwiftUI
import SwiftUI

/// Riding until M7 builds the P5 screen: Ferrostar's navigation view on the Velix map style.
struct RidingView: View {
    @Bindable var session: RideSession
    let styleURL: URL

    var body: some View {
        DynamicallyOrientingNavigationView(
            styleURL: styleURL,
            camera: $session.camera,
            navigationState: session.navigationState,
            isMuted: session.core?.spokenInstructionObserver.isMuted ?? false,
            onTapMute: { session.core?.spokenInstructionObserver.toggleMute() },
            onTapExit: { session.end() }
        )
    }
}
