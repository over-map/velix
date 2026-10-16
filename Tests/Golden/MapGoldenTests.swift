import MapLibre
import XCTest
@testable import Velix

/// Renders the P3 styles from the pack's basemap and overlays (VELIX_PACK_DIR with basemap.pmtiles + overlays.pmtiles;
/// skipped otherwise, like the golden routes). Checks the map draws its land, roads and buildings; PNGs go to
/// VELIX_GOLDEN_OUT/map for review (docs/reviews/m5 has the P3 side-by-sides).
@MainActor
final class MapGoldenTests: XCTestCase {
    private var pack: URL? { ProcessInfo.processInfo.environment["VELIX_PACK_DIR"].map { URL(filePath: $0) } }

    func testStylesRenderFromThePack() throws {
        guard let dir = pack, FileManager.default.fileExists(atPath: dir.appending(path: "basemap.pmtiles").path) else {
            throw XCTSkip("No basemap.pmtiles in VELIX_PACK_DIR")
        }
        let out = ProcessInfo.processInfo.environment["VELIX_GOLDEN_OUT"].map { URL(filePath: $0).appending(path: "map") }
        if let out { try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true) }
        let overlays = dir.appending(path: "overlays.pmtiles")
        for kind in MapStyleKind.allCases {
            for mode in MapMode.allCases {
                for zoom in [13.0, 15, 17] {
                    let style = try VelixMapStyle.url(kind, mode, basemap: dir.appending(path: "basemap.pmtiles"),
                                                      overlays: FileManager.default.fileExists(atPath: overlays.path) ? overlays : nil)
                    let image = try snapshot(style, center: LatLon(lat: 45.473220, lon: 9.216726), zoom: zoom)
                    let distinct = distinctColours(image)
                    XCTAssertGreaterThan(distinct, 6, "\(kind)-\(mode)-z\(Int(zoom)) looks blank (\(distinct) colours)")
                    if let out { try image.pngData()?.write(to: out.appending(path: "\(kind.rawValue)-\(mode.rawValue)-z\(Int(zoom)).png")) }
                }
            }
        }
    }

    private func snapshot(_ style: URL, center: LatLon, zoom: Double) throws -> UIImage {
        let cam = MLNMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: center.lat, longitude: center.lon),
                               altitude: 0, pitch: 0, heading: 0)
        let opts = MLNMapSnapshotOptions(styleURL: style, camera: cam, size: CGSize(width: 393, height: 600))
        opts.zoomLevel = zoom
        let done = expectation(description: "snapshot")
        final class Box: @unchecked Sendable { var result: Result<UIImage, Error> = .failure(CocoaError(.featureUnsupported)) }
        let box = Box()
        let snapper = MLNMapSnapshotter(options: opts)
        snapper.start { snap, error in   // completion on the main queue
            if let snap { box.result = .success(snap.image) } else if let error { box.result = .failure(error) }
            done.fulfill()
        }
        wait(for: [done], timeout: 60)
        return try box.result.get()
    }

    /// Distinct colours on a coarse grid: a blank or failed map has 1–2.
    private func distinctColours(_ image: UIImage) -> Int {
        guard let cg = image.cgImage, let data = cg.dataProvider?.data, let p = CFDataGetBytePtr(data) else { return 0 }
        var seen = Set<UInt32>()
        let bpr = cg.bytesPerRow, bpp = cg.bitsPerPixel / 8
        for y in stride(from: 0, to: cg.height, by: 17) {
            for x in stride(from: 0, to: cg.width, by: 17) {
                let i = y * bpr + x * bpp
                seen.insert(UInt32(p[i] >> 3) << 10 | UInt32(p[i + 1] >> 3) << 5 | UInt32(p[i + 2] >> 3))
            }
        }
        return seen.count
    }
}
