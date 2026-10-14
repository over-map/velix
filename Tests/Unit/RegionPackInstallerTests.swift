import Compression
import CryptoKit
import Foundation
import Testing
@testable import Velix

/// Serves files from a local folder in place of GitHub release assets.
private struct FolderDownloader: PackDownloading {
    let folder: URL
    var failing: Set<String> = []

    func download(_ url: URL, to destination: URL, progress: @Sendable (Int64) -> Void) async throws {
        if failing.contains(url.lastPathComponent) { throw URLError(.networkConnectionLost) }
        let source = folder.appending(path: url.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: destination)
        progress(Int64((try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
    }
}

/// Builds a release folder: manifest.json + one .xz per file, like pipeline/stages/package.py.
private func makeRelease(version: String, files: [String: Data], in folder: URL, corrupt: String? = nil) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let roles = ["valhalla_tiles.tar": "routing_tiles", "hazards.sqlite": "hazards", "routes.sqlite": "routes",
                 "transit.sqlite": "transit"]
    var entries: [[String: Any]] = []
    for (name, data) in files.sorted(by: { $0.key < $1.key }) {
        var xz = try RegionPackInstaller.compressXZ(data)
        let sha = SHA256.hash(data: xz).hexString
        if name == corrupt { xz.append(0) }
        try xz.write(to: folder.appending(path: "\(name).xz"))
        entries.append(["name": name, "asset": "\(name).xz", "role": roles[name]!, "bytes": xz.count, "sha256": sha,
                        "unpacked_bytes": data.count, "unpacked_sha256": SHA256.hash(data: data).hexString])
    }
    let manifest: [String: Any] = [
        "schema": 1, "pack": "lombardy", "name": "Lombardy", "version": version, "built": "2026-10-13",
        "valhalla": "3.9.0", "bbox": [8.49, 44.67, 11.43, 46.64], "polygon_sha256": String(repeating: "a", count: 64),
        "files": entries, "download_bytes": entries.reduce(0) { $0 + ($1["bytes"] as! Int) },
        "unpacked_bytes": files.values.reduce(0) { $0 + $1.count }, "budget_bytes": 220_000_000,
        "sources": [["id": "osm", "name": "OpenStreetMap", "url": "https://openstreetmap.org", "date": "2026-10-13",
                     "licence": "ODbL-1.0", "attribution": "© OpenStreetMap contributors"]],
        "counts": [:] as [String: Any],
    ]
    try JSONSerialization.data(withJSONObject: manifest, options: .sortedKeys)
        .write(to: folder.appending(path: "manifest.json"))
}

private func samplePack(_ tag: String) -> [String: Data] {
    [
        "valhalla_tiles.tar": Data(String(repeating: "tiles-\(tag) ", count: 5000).utf8),
        "hazards.sqlite": Data("hazards-\(tag)".utf8),
        "routes.sqlite": Data("routes-\(tag)".utf8),
        "transit.sqlite": Data("transit-\(tag)".utf8),
    ]
}

struct RegionPackInstallerTests {
    let tmp = FileManager.default.temporaryDirectory.appending(path: "velix-pack-tests-\(UUID().uuidString)")

    private func installer(release: URL, failing: Set<String> = []) -> RegionPackInstaller {
        RegionPackInstaller(root: tmp.appending(path: "RegionPack"),
                            downloader: FolderDownloader(folder: release, failing: failing))
    }

    @Test func xzRoundTripsThroughCompressionFramework() throws {
        let data = Data((0 ..< 200_000).map { UInt8($0 % 251) })
        let xz = try RegionPackInstaller.compressXZ(data)
        #expect(xz.prefix(6) == Data([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]))  // xz magic
        let out = tmp.appending(path: "out.bin")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let input = tmp.appending(path: "in.xz")
        try xz.write(to: input)
        try RegionPackInstaller.decompressXZ(input, to: out)
        #expect(try Data(contentsOf: out) == data)
    }

    @Test func decodesPipelineXZ() throws {
        // Written by `xz -9 -T1` (CRC64 check), the exact settings of pipeline/stages/package.py.
        let fixture = try #require(Bundle(for: BundleToken.self).url(forResource: "pipeline-sample", withExtension: "xz"))
        let out = tmp.appending(path: "sample.txt")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try RegionPackInstaller.decompressXZ(fixture, to: out)
        #expect(try String(contentsOf: out, encoding: .utf8).hasPrefix("Velix region pack xz fixture"))
    }

    @Test func installsAndPointsCurrentAtTheNewVersion() async throws {
        let release = tmp.appending(path: "release-1")
        try makeRelease(version: "2026.10", files: samplePack("a"), in: release)
        let installed = try await installer(release: release).install(manifest: release.appending(path: "manifest.json"))
        #expect(installed.manifest.version == "2026.10")
        let current = try #require(RegionPackInstaller.current(root: tmp.appending(path: "RegionPack")))
        #expect(current.directory == installed.directory)
        #expect(try Data(contentsOf: current.file(.routingTiles)) == samplePack("a")["valhalla_tiles.tar"])
        #expect(!FileManager.default.fileExists(atPath: installed.directory.appending(path: "hazards.sqlite.xz").path))
    }

    @Test func checksumMismatchFailsAndKeepsThePreviousPack() async throws {
        let good = tmp.appending(path: "release-good")
        try makeRelease(version: "2026.10", files: samplePack("a"), in: good)
        _ = try await installer(release: good).install(manifest: good.appending(path: "manifest.json"))

        let bad = tmp.appending(path: "release-bad")
        try makeRelease(version: "2026.11", files: samplePack("b"), in: bad, corrupt: "hazards.sqlite")
        await #expect(throws: RegionPackError.checksumMismatch("hazards.sqlite.xz")) {
            try await installer(release: bad).install(manifest: bad.appending(path: "manifest.json"))
        }
        let current = try #require(RegionPackInstaller.current(root: tmp.appending(path: "RegionPack")))
        #expect(current.manifest.version == "2026.10")
        #expect(try Data(contentsOf: current.file(.hazards)) == samplePack("a")["hazards.sqlite"])
    }

    @Test func failedDownloadLeavesNoStagingBehind() async throws {
        let release = tmp.appending(path: "release-net")
        try makeRelease(version: "2026.10", files: samplePack("a"), in: release)
        await #expect(throws: URLError.self) {
            try await installer(release: release, failing: ["transit.sqlite.xz"])
                .install(manifest: release.appending(path: "manifest.json"))
        }
        let root = tmp.appending(path: "RegionPack")
        #expect(RegionPackInstaller.current(root: root) == nil)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: root.appending(path: "staging").path)) ?? []
        #expect(leftovers.isEmpty)
    }

    @Test func newVersionReplacesTheOldOne() async throws {
        let r1 = tmp.appending(path: "r1"), r2 = tmp.appending(path: "r2")
        try makeRelease(version: "2026.10", files: samplePack("a"), in: r1)
        try makeRelease(version: "2026.11", files: samplePack("b"), in: r2)
        let first = try await installer(release: r1).install(manifest: r1.appending(path: "manifest.json"))
        _ = try await installer(release: r2).install(manifest: r2.appending(path: "manifest.json"))
        let current = try #require(RegionPackInstaller.current(root: tmp.appending(path: "RegionPack")))
        #expect(current.manifest.version == "2026.11")
        #expect(!FileManager.default.fileExists(atPath: first.directory.path))
    }

    @Test func rejectsUnknownSchema() throws {
        let json = #"{"schema": 2, "pack": "x", "name": "x", "version": "2026.10", "built": "2026-10-13", "valhalla": "3.9.0", "bbox": [0,0,1,1], "polygon_sha256": "", "files": [], "download_bytes": 1, "unpacked_bytes": 1, "budget_bytes": 1, "sources": []}"#
        #expect(throws: RegionPackError.unsupportedSchema(2)) {
            try RegionPackManifest.decode(Data(json.utf8))
        }
    }
}

private final class BundleToken {}

private extension SHA256.Digest {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

struct RegionPackCatalogTests {
    @Test func picksNewestPublishedPackForTheRegion() throws {
        let json = #"""
        [{"tag_name": "v0.2.0", "draft": false, "prerelease": false},
         {"tag_name": "pack-lombardy-2026.11", "draft": true, "prerelease": false},
         {"tag_name": "pack-lombardy-2026.10.2", "draft": false, "prerelease": false},
         {"tag_name": "pack-lombardy-2026.10", "draft": false, "prerelease": false}]
        """#
        #expect(try RegionPackCatalog.latestTag(region: "lombardy", in: Data(json.utf8)) == "pack-lombardy-2026.10.2")
        #expect(try RegionPackCatalog.latestTag(region: "piedmont", in: Data(json.utf8)) == nil)
    }
}
