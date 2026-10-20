@preconcurrency import FerrostarCore
import FerrostarMapLibreUI
import FerrostarSwiftUI
import MapLibreSwiftUI
import SwiftUI

/// Riding until M7b builds the P5 screen: Ferrostar's navigation view on the Velix map style, with the app's voice
/// modes behind its mute button.
struct RidingView: View {
    @Bindable var session: RideSession
    let styleURL: URL
    @State private var camera: MapViewCamera = .automotiveNavigation(zoom: 17)

    var body: some View {
        DynamicallyOrientingNavigationView(
            styleURL: styleURL,
            camera: $camera,
            navigationState: session.navigationState,
            isMuted: session.voice.mode == .mute,
            onTapMute: { session.voice.cycle() },
            onTapExit: { session.end() }
        )
    }
}
