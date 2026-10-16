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

    /// Debug: `-use-sideloaded` prefers files side-loaded into Documents over the installed pack (testing a new build).
    static var preferSideloaded: Bool { ProcessInfo.processInfo.arguments.contains("-use-sideloaded") }

    static var hazardStore: URL? {
        let side = URL.documentsDirectory.appending(path: "hazards.sqlite")
        if preferSideloaded, FileManager.default.fileExists(atPath: side.path) { return side }
        if let installed = try? RegionPackInstaller.current()?.file(.hazards), FileManager.default.fileExists(atPath: installed.path) {
            return installed
        }
        return FileManager.default.fileExists(atPath: side.path) ? side : nil
    }

    /// Map tiles (M5): `basemap.pmtiles` and `overlays.pmtiles`, installed or side-loaded into Documents.
    static var basemap: URL? { mapFile(.basemap, sideloaded: "basemap.pmtiles") }
    static var overlays: URL? { mapFile(.overlays, sideloaded: "overlays.pmtiles") }

    private static func mapFile(_ role: RegionPackManifest.File.Role, sideloaded name: String) -> URL? {
        let side = URL.documentsDirectory.appending(path: name)
        if preferSideloaded, FileManager.default.fileExists(atPath: side.path) { return side }
        if let installed = try? RegionPackInstaller.current()?.file(role), FileManager.default.fileExists(atPath: installed.path) {
            return installed
        }
        return FileManager.default.fileExists(atPath: side.path) ? side : nil
    }

    static var tileExtract: URL? {
        if preferSideloaded, FileManager.default.fileExists(atPath: sideloadedTileExtract.path) { return sideloadedTileExtract }
        if let installed = try? RegionPackInstaller.current()?.file(.routingTiles),
           FileManager.default.fileExists(atPath: installed.path) {
            return installed
        }
        return FileManager.default.fileExists(atPath: sideloadedTileExtract.path) ? sideloadedTileExtract : nil
    }
}
