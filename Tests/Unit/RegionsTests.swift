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
}

private extension JSONEncoder {
    static var snake: JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }
}
