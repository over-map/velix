import SwiftUI

@main
struct VelixApp: App {
    /// One model for the app's life. Built here, not as RootView's default argument: SwiftUI re-runs the body often,
    /// and each run would build (and throw away) a whole model, ride history store included (30 Oct: that starved the
    /// map down to 3–5 frames a second).
    @MainActor private static let model = AppModel()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-design-gallery") {
                DesignGalleryView()
            } else if args.contains("-map-preview") {
                MapPreviewView()
            } else if args.contains("-spike") {
                SpikeView()
            } else if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                LaunchView()
            } else {
                RootView(app: Self.model)
            }
            #else
            RootView(app: Self.model)
            #endif
        }
    }
}
