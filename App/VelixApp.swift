import SwiftUI

@main
struct VelixApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-design-gallery") {
                DesignGalleryView()
            } else if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
                SpikeView()
            } else {
                LaunchView()
            }
            #else
            LaunchView()
            #endif
        }
    }
}
