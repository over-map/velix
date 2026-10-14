import Foundation

/// Where the offline region pack lives on the phone: `Application Support/RegionPack/`
/// (`current` names the installed version under `versions/`, see ``RegionPackInstaller``).
enum RegionPack {
    static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "RegionPack", directoryHint: .isDirectory)
    }

    /// M1 side-loading lands files in Documents (devicectl / simctl can write there). Debug fallback only.
    static var sideloadedTileExtract: URL {
        URL.documentsDirectory.appending(path: "valhalla_tiles.tar")
    }

    /// Release download folder of a published pack (GitHub Release assets).
    static func releaseManifestURL(tag: String) -> URL {
        URL(string: "https://github.com/over-map/velix/releases/download/\(tag)/manifest.json")!
    }

    static var tileExtract: URL? {
        if let installed = try? RegionPackInstaller.current()?.file(.routingTiles),
           FileManager.default.fileExists(atPath: installed.path) {
            return installed
        }
        return FileManager.default.fileExists(atPath: sideloadedTileExtract.path) ? sideloadedTileExtract : nil
    }
}
