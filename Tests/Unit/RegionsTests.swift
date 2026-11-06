import Foundation
import Testing
@testable import Velix

/// Several regions on the phone (Filippo, 2 Nov): region geometry, choosing the pack for a trip, the folder move,
/// the catalog, and the map tiles served from every pack (PMTiles reading, vector tiles merged at a border).
struct RegionsTests {
    private static func box(_ w: Double, _ s: Double, _ e: Double, _ n: Double) -> RegionShape {
        RegionShape(polygons: [[[[w, s], [e, s], [e, n], [w, n], [w, s]]]])
    }

    private static func manifest(_ pack: String, border: RegionShape, coverage: RegionShape) -> RegionPackManifest {
        var m = RegionPackManifest(schema: 1, pack: pack, name: pack.capitalized, version: "2026.11", built: "2026-11-01",
                                   valhalla: "3.9.0", bbox: [0, 0, 0, 0], files: [], downloadBytes: 1, unpackedBytes: 1,
                                   budgetBytes: 1, sources: [])
        m.polygon = border
        m.coverage = .init(bufferKm: 10, bbox: [0, 0, 0, 0], polygon: coverage)
        return m
    }

    @Test func shapesHoldTheirInsideNotTheirHoles() {
        let ring = RegionShape(polygons: [[[[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]], [[4, 4], [6, 4], [6, 6], [4, 6], [4, 4]]]])
        #expect(ring.contains(LatLon(lat: 2, lon: 2)))
        #expect(!ring.contains(LatLon(lat: 5, lon: 5)))      // the hole
        #expect(!ring.contains(LatLon(lat: 11, lon: 2)))
    }

    @Test func aTripPlansInThePackCoveringBothEnds() {
        let dir = FileManager.default.temporaryDirectory.appending(path: "velix-regions-\(UUID().uuidString)")
        let west = InstalledRegionPack(directory: dir, manifest: Self.manifest("west", border: Self.box(0, 0, 5, 5), coverage: Self.box(0, 0, 5.5, 5)))
        let east = InstalledRegionPack(directory: dir, manifest: Self.manifest("east", border: Self.box(5, 0, 10, 5), coverage: Self.box(4.5, 0, 10, 5)))
        let a = LatLon(lat: 2, lon: 4.8), b = LatLon(lat: 2, lon: 5.2)      // either side of the border, inside both buffers
        #expect(RegionPack.region(covering: [a, b], among: [west, east]) == "west")   // the start's region
        #expect(RegionPack.region(covering: [b, a], among: [west, east]) == "east")
        #expect(RegionPack.region(covering: [LatLon(lat: 2, lon: 1), LatLon(lat: 2, lon: 9)], among: [west, east]) == nil)
    }

    @Test func theOldSinglePackMovesIntoItsRegionFolder() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "velix-legacy-\(UUID().uuidString)")
        let version = base.appending(path: "versions/2026.10")
        try FileManager.default.createDirectory(at: version, withIntermediateDirectories: true)
        try JSONEncoder.snake.encode(RegionPackManifest.sideloaded).write(to: version.appending(path: "manifest.json"))
        try Data("2026.10".utf8).write(to: base.appending(path: "current"))
        RegionPack.migrateLegacyLayout(base: base)
        #expect(RegionPackInstaller.current(root: base) == nil)
        #expect(RegionPackInstaller.current(root: base.appending(path: "lombardy"))?.manifest.pack == "lombardy")
        #expect(RegionPack.installed(base: base).map(\.manifest.pack) == ["lombardy"])
    }

    @Test func theCatalogReadsThePipelineIndex() throws {
        let json = #"""
        {"schema":1,"regions":[{"id":"piemonte","name":"Piedmont","tag":"pack-piemonte-2026.11","version":"2026.11",
         "built":"2026-11-01","bbox":[6.6,44.0,8.5,46.5],"polygon":[[[[6.6,44.0],[8.5,44.0],[8.5,46.5],[6.6,46.5],[6.6,44.0]]]],
         "coverage":null,"download_bytes":221900000,"unpacked_bytes":1,
         "manifest":"https://github.com/over-map/velix/releases/download/pack-piemonte-2026.11/manifest.json"}]}
        """#
        let c = try RegionCatalog.decode(Data(json.utf8))
        #expect(c.region(containing: LatLon(lat: 45.07, lon: 7.68))?.name == "Piedmont")
        #expect(c.region(containing: LatLon(lat: 45.46, lon: 9.19)) == nil)
        #expect(c.regions[0].downloadBytes == 221_900_000)
    }

    /// Filippo, 5 Nov: Remove is a button, and the last region stays (routes need one). Cancel stops a download.
    @Test @MainActor func regionsCanBeRemovedWhileOneStays() {
        let dir = FileManager.default.temporaryDirectory.appending(path: "velix-regions-\(UUID().uuidString)")
        let pack = PackService(base: dir, catalog: { RegionCatalog(schema: 1, regions: []) })
        let border = Self.box(0, 0, 1, 1)
        let old = RegionPackManifest(schema: 1, pack: "lombardy", name: "Lombardy", version: "2026.10", built: "2026-10-01",
                                 valhalla: "3.9.0", bbox: [0, 0, 1, 1], files: [], downloadBytes: 1, unpackedBytes: 1,
                                 budgetBytes: 1, sources: [])
        pack.setForTesting(.ready(old), region: "lombardy")
        pack.setForTesting(.ready(Self.manifest("piemonte", border: border, coverage: border)), region: "piemonte")
        let saved = RegionPack.active
        defer { RegionPack.active = saved }
        RegionPack.active = "piemonte"

        #expect(pack.canRemove("lombardy") && pack.canRemove("piemonte"))
        pack.delete("piemonte")
        #expect(!pack.isInstalled("piemonte"))
        #expect(RegionPack.active == "lombardy")        // never an uninstalled region
        #expect(!pack.canRemove("lombardy"))
        pack.delete("lombardy")
        #expect(pack.isInstalled("lombardy"))

        // A newer pack on offer: the row offers its update.
        pack.setCatalogForTesting(RegionCatalog(schema: 1, regions: [
            .init(id: "lombardy", name: "Lombardy", tag: "pack-lombardy-2026.11", version: "2026.11", bbox: [0, 0, 1, 1],
                  polygon: border, downloadBytes: 299_000_000, manifest: URL(string: "https://example.invalid/m.json")!)]))
        #expect(pack.hasUpdate("lombardy"))
        #expect(!pack.hasUpdate("piemonte"))

        // Cancel only touches the running download.
        pack.setForTesting(.downloading(received: 1, total: 2), region: "veneto")
        #expect(!pack.canRemove("veneto"))
        pack.cancel("lombardy")
        #expect(pack.downloading == "veneto")
    }

    @Test @MainActor func updatesInstallInTheBackgroundAndGiveWayToDownloads() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "velix-updates-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let border = Self.box(0, 0, 1, 1)
        func region(_ id: String, _ version: String) -> RegionCatalog.Region {
            .init(id: id, name: id.capitalized, tag: "pack-\(id)-\(version)", version: version, bbox: [0, 0, 1, 1],
                  polygon: border, downloadBytes: 100, manifest: URL(string: "https://example.invalid/\(id)/manifest.json")!)
        }
        let pack = PackService(base: dir, downloader: StalledDownloader(),
                               catalog: { RegionCatalog(schema: 1, regions: []) })
        let old = RegionPackManifest(schema: 1, pack: "lombardy", name: "Lombardy", version: "2026.10", built: "2026-10-01",
                                     valhalla: "3.9.0", bbox: [0, 0, 1, 1], files: [], downloadBytes: 1, unpackedBytes: 1,
                                     budgetBytes: 1, sources: [])
        pack.setForTesting(.ready(old), region: "lombardy")
        pack.setCatalogForTesting(RegionCatalog(schema: 1, regions: [region("lombardy", "2026.11"), region("veneto", "2026.11")]))

        pack.installUpdates()
        #expect(pack.downloading == nil)                  // Update automatically is off
        pack.autoUpdate = true
        #expect(pack.downloading == "lombardy")
        #expect(pack.isInstalled("lombardy") && !pack.isDownloading)   // the old pack serves meanwhile, no banner

        // The rider's download goes first; the update comes back after it.
        pack.install("veneto")
        try await Self.until { pack.downloading == "veneto" }
        #expect(pack.isDownloading && pack.isInstalled("lombardy"))
        pack.cancel("veneto")
        try await Self.until { pack.downloading == "lombardy" }
        #expect(pack.isInstalled("lombardy"))
        pack.autoUpdate = false
        pack.cancel("lombardy")
    }

    @MainActor private static func until(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition())
    }

    // MARK: Map tiles

    @Test func pmtilesTileIDsFollowTheSpec() {
        #expect(PMTiles.tileID(z: 0, x: 0, y: 0) == 0)
        #expect(PMTiles.tileID(z: 1, x: 0, y: 0) == 1)
        #expect(PMTiles.tileID(z: 1, x: 0, y: 1) == 2)
        #expect(PMTiles.tileID(z: 1, x: 1, y: 1) == 3)
        #expect(PMTiles.tileID(z: 1, x: 1, y: 0) == 4)
        #expect(PMTiles.tileID(z: 2, x: 0, y: 0) == 5)
    }

    @Test func pmtilesDirectoriesDecodeRunsAndOffsets() throws {
        // 2 entries: ids 5 and 7 (deltas 5, 2), runs 1 and 2, lengths 10 and 20, offsets 0 (stored +1) then "follows".
        let d = Data([2, 5, 2, 1, 2, 10, 20, 1, 0])
        let entries = try PMTiles.directory(d)
        #expect(entries == [.init(tileID: 5, offset: 0, length: 10, runLength: 1), .init(tileID: 7, offset: 10, length: 20, runLength: 2)])
        #expect(PMTiles.find(8, in: entries)?.tileID == 7)        // inside the run
        #expect(PMTiles.find(9, in: entries) == nil)              // past it
        #expect(PMTiles.find(4, in: entries) == nil)
    }

    @Test func gzipRoundTrips() throws {
        // `printf 'velix' | gzip -n | xxd -i`
        let gz = Data([0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0x2b, 0x4b, 0xcd, 0xc9, 0xac, 0x00, 0x00,
                       0xe7, 0xfe, 0x64, 0x17, 0x05, 0x00, 0x00, 0x00])
        #expect(try String(decoding: PMTiles.gunzip(gz), as: UTF8.self) == "velix")
    }

    @Test func borderTilesMergeLayersAndMoveTags() {
        // Two tiles, each one layer "building" with one key "h", one value, one feature tagged (0, 0).
        func tile(value: UInt8) -> Data {
            let feature: [UInt8] = [0x12, 0x02, 0x00, 0x00, 0x18, 0x03, 0x22, 0x00]   // tags [0,0], type 3, no geometry
            let val: [UInt8] = [0x28, value]                                           // Value.int_value
            var layer: [UInt8] = [0x78, 0x02, 0x0a, 0x08] + Array("building".utf8)
            layer += [0x12, UInt8(feature.count)] + feature
            layer += [0x1a, 0x01, UInt8(ascii: "h")]
            layer += [0x22, UInt8(val.count)] + val
            layer += [0x28, 0x80, 0x20]
            return Data([0x1a, UInt8(layer.count)] + layer)
        }
        let merged = [UInt8](VectorTileMerge.merge([tile(value: 3), tile(value: 9)]))
        // One layer, two features: the second's tags moved to (1, 1).
        #expect(String(decoding: merged, as: UTF8.self).components(separatedBy: "building").count == 2)
        let secondTags: [UInt8] = [0x12, 0x02, 0x01, 0x01]
        #expect(merged.indices.contains { i in Array(merged[i ..< min(i + 4, merged.count)]) == secondTags })
    }

    @Test func tilesTouchingAPackAreServedFromIt() {
        let lombardy = [8.49785, 44.67991, 11.42765, 46.63535]
        #expect(PackTileProtocol.covers(lombardy, z: 14, x: 8610, y: 5864))     // Milan
        #expect(!PackTileProtocol.covers(lombardy, z: 14, x: 8760, y: 6088))    // Rome
    }

    /// Filippo, 5 Nov: a blank world outside the pack. Only a tile wholly inside a pack's border comes from the pack;
    /// low zooms, border tiles and the rest of the world come online.
    @Test func onlyTilesInsideTheBorderComeFromThePack() {
        // A diamond around Milan (9.19 E, 45.46 N), ±1°.
        let border = RegionShape(polygons: [[[[9.19, 44.46], [10.19, 45.46], [9.19, 46.46], [8.19, 45.46], [9.19, 44.46]]]])
        let bounds = [8.19, 44.46, 10.19, 46.46]
        let milan14 = (z: 14, x: 8610, y: 5864)
        #expect(PackTileProtocol.holds(border, bounds: bounds, z: milan14.z, x: milan14.x, y: milan14.y))
        // z8 around Milan pokes past the diamond's sides; z5 holds the whole region (vertices inside).
        #expect(!PackTileProtocol.holds(border, bounds: bounds, z: 8, x: 134, y: 91))
        #expect(!PackTileProtocol.holds(border, bounds: bounds, z: 5, x: 16, y: 11))
        // Inside the bbox but outside the diamond (its south-west corner): online.
        let corner = Self.tile(lat: 44.6, lon: 8.3, z: 12)
        #expect(!PackTileProtocol.holds(border, bounds: bounds, z: 12, x: corner.x, y: corner.y))
        // No border (side-loaded): the tiles' bounds decide.
        #expect(PackTileProtocol.holds(nil, bounds: bounds, z: 12, x: corner.x, y: corner.y))
        #expect(!PackTileProtocol.holds(nil, bounds: bounds, z: 5, x: 16, y: 11))
    }

    @Test func tileBoundsAndOnlineURL() {
        let b = PackTileProtocol.bounds(z: 1, x: 1, y: 0)
        #expect(b[0] == 0 && b[2] == 180 && abs(b[3] - 85.0511) < 0.001 && abs(b[1]) < 1e-9)
        let url = PackTileProtocol.url("https://tiles.openfreemap.org/planet/20261101_080013_pt/{z}/{x}/{y}.pbf", z: 5, x: 17, y: 11)
        #expect(url?.absoluteString == "https://tiles.openfreemap.org/planet/20261101_080013_pt/5/17/11.pbf")
    }

    private static func tile(lat: Double, lon: Double, z: Int) -> (x: Int, y: Int) {
        let n = Double(1 << z), r = lat * .pi / 180
        return (Int((lon + 180) / 360 * n), Int((1 - log(tan(r) + 1 / cos(r)) / .pi) / 2 * n))
    }
}

private extension JSONEncoder {
    static var snake: JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }
}

/// A download that never finishes (until cancelled).
private struct StalledDownloader: PackDownloading {
    func download(_ url: URL, to destination: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        try await Task.sleep(for: .seconds(60))
    }
}
