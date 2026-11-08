import SwiftUI

@main
struct VelixApp: App {
    /// One model for the app's life. Built here, not as RootView's default argument: SwiftUI re-runs the body often,
    /// and each run would build (and throw away) a whole model, ride history store included (30 Oct: that starved the
    /// map down to 3–5 frames a second).
    /// Each step is timed for the launch log (PerfLog, M10).
    @MainActor private static let model = PerfLog.phase("model") {
        AppModel(location: PerfLog.phase("location") { LocationService() },
                 pack: PerfLog.phase("packService") { PackService() },
                 history: PerfLog.phase("history") { RideHistory() })
    }

    init() {
        PerfLog.phase("migrate") { RegionPack.migrateLegacyLayout() }
        // Every map reads its tiles through the packs (several regions as one source, PackTileProtocol).
        PerfLog.phase("tileProtocol") {
            PackTileProtocol.install()
            PackTileProtocol.use(RegionPack.mapSources)
        }
        PerfLog.phase("diagnostics") { CrashReports.shared.start() }   // crash and hang reports (Documents/diagnostics)
    }

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
