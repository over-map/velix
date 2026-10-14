import Foundation

/// Where the offline region pack lives on the phone.
/// M1: the tile extract is side-loaded into the app container (see pipeline/spike/README.md).
/// M2 replaces this with the downloaded, checksum-verified pack.
enum RegionPack {
    static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "RegionPack", directoryHint: .isDirectory)
    }

    /// Side-loading lands files in Documents (devicectl / simctl can write there).
    static var sideloadedTileExtract: URL {
        URL.documentsDirectory.appending(path: "valhalla_tiles.tar")
    }

    static var tileExtract: URL? {
        let candidates = [directory.appending(path: "valhalla_tiles.tar"), sideloadedTileExtract]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
