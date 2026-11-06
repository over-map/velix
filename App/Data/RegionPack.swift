import Foundation

/// Where the offline region packs live on the phone: `Application Support/RegionPack/<region>/`, one per downloaded
/// region (`current` names the installed version under `versions/`, see ``RegionPackInstaller``). Every downloaded
/// region stays; the routing engine, hazards, timetable and cycle routes read the *active* one (``active``), the one
/// covering the trip (``region(covering:among:)``); the map shows them all (``PackTileProtocol``).
enum RegionPack {
    static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "RegionPack", directoryHint: .isDirectory)
    }

    /// One region's installer root.
    static func root(_ region: String, base: URL = directory) -> URL {
        base.appending(path: region, directoryHint: .isDirectory)
    }

    /// The region the pack files below come from (set by ``EngineHost`` for a trip; the first installed one otherwise).
    nonisolated(unsafe) static var active: String = installed().first?.manifest.pack ?? "lombardy"

    /// Every installed region, by name.
    static func installed(base: URL = directory) -> [InstalledRegionPack] {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return dirs.compactMap { RegionPackInstaller.current(root: $0) }.sorted { $0.manifest.name < $1.manifest.name }
    }

    /// The installed region whose routing data covers every point (both ends of a trip), preferring the one whose
    /// border holds the first point.
    static func region(covering points: [LatLon], among packs: [InstalledRegionPack] = installed()) -> String? {
        let fits = packs.filter { p in points.allSatisfy { p.manifest.covers($0) } }
        return (fits.first { p in points.first.map { p.manifest.contains($0) } ?? false } ?? fits.first)?.manifest.pack
    }

    /// Before Nov 2026 the one pack lived straight in `RegionPack/`: move it into its region's folder, once.
    static func migrateLegacyLayout(base: URL = directory) {
        let fm = FileManager.default
        guard let legacy = RegionPackInstaller.current(root: base) else { return }
        let target = root(legacy.manifest.pack, base: base)
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        for name in ["versions", "staging", "current"] {
            let from = base.appending(path: name)
            guard fm.fileExists(atPath: from.path) else { continue }
            try? fm.removeItem(at: target.appending(path: name))
            try? fm.moveItem(at: from, to: target.appending(path: name))
        }
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

    /// The active region's installed pack.
    static var current: InstalledRegionPack? { RegionPackInstaller.current(root: root(active)) }

    static var hazardStore: URL? { packFile(.hazards, sideloaded: "hazards.sqlite") }

    /// Map tiles (M5): `basemap.pmtiles` and `overlays.pmtiles` of every installed region with its border, for
    /// ``PackTileProtocol``, or side-loaded into Documents (no border).
    static var mapSources: [PackTileProtocol.Source] {
        let fm = FileManager.default
        func existing(_ url: URL?) -> URL? { url.flatMap { fm.fileExists(atPath: $0.path) ? $0 : nil } }
        let side = URL.documentsDirectory
        let sideloaded = PackTileProtocol.Source(basemap: existing(side.appending(path: "basemap.pmtiles")),
                                                 overlays: existing(side.appending(path: "overlays.pmtiles")))
        if preferSideloaded, sideloaded.basemap != nil { return [sideloaded] }
        let packs = installed().map { p in
            PackTileProtocol.Source(basemap: existing(try? p.file(.basemap)), overlays: existing(try? p.file(.overlays)),
                                    border: p.manifest.polygon)
        }.filter { $0.basemap != nil || $0.overlays != nil }
        if !packs.isEmpty { return packs }
        return sideloaded.basemap != nil || sideloaded.overlays != nil ? [sideloaded] : []
    }
    /// Bike + transit (M8): the active region's timetable, and the city area.
    static var transit: URL? { packFile(.transit, sideloaded: "transit.sqlite") }
    static var city: URL? { packFile(.city, sideloaded: "city.geojson") }
    /// Routes tab (M9): OSM cycle-route relations.
    static var routes: URL? { packFile(.routes, sideloaded: "routes.sqlite") }

    private static func packFile(_ role: RegionPackManifest.File.Role, sideloaded name: String) -> URL? {
        let side = URL.documentsDirectory.appending(path: name)
        if preferSideloaded, FileManager.default.fileExists(atPath: side.path) { return side }
        if let installed = try? current?.file(role), FileManager.default.fileExists(atPath: installed.path) {
            return installed
        }
        return FileManager.default.fileExists(atPath: side.path) ? side : nil
    }

    static var tileExtract: URL? {
        if preferSideloaded, FileManager.default.fileExists(atPath: sideloadedTileExtract.path) { return sideloadedTileExtract }
        if let installed = try? current?.file(.routingTiles), FileManager.default.fileExists(atPath: installed.path) {
            return installed
        }
        return FileManager.default.fileExists(atPath: sideloadedTileExtract.path) ? sideloadedTileExtract : nil
    }
}

extension RegionPackManifest {
    /// Inside the region's border (older packs: its bbox).
    func contains(_ p: LatLon) -> Bool {
        if let polygon { return polygon.contains(p) }
        return bbox.count == 4 && p.lon >= bbox[0] && p.lat >= bbox[1] && p.lon <= bbox[2] && p.lat <= bbox[3]
    }

    /// Where its routing data reaches: the border plus the buffer (older packs: the border).
    func covers(_ p: LatLon) -> Bool {
        coverage.map { $0.polygon.contains(p) } ?? contains(p)
    }
}
