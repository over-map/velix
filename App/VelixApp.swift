import SwiftUI

@main
struct VelixApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
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
