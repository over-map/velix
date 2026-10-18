import SwiftUI

@main
struct VelixApp: App {
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
                RootView()
            }
            #else
            RootView()
            #endif
        }
    }
}
