import Foundation
import UIKit
import Testing
@testable import Velix

/// National aerial photos on the Satellite map where they are free and keyless, EOX elsewhere (Filippo, 23 Nov).
struct AerialImageryTests {
    let catalog = AerialImagery.Catalog.bundled

    /// The z17 tile holding a point.
    func tile(_ lat: Double, _ lon: Double, z: Int = 17) -> (z: Int, x: Int, y: Int) {
        let n = Double(1 << z), r = lat * .pi / 180
        return (z, Int((lon + 180) / 360 * n), Int((1 - asinh(tan(r)) / .pi) / 2 * n))
    }

    func source(_ lat: Double, _ lon: Double, z: Int = 17) -> String? {
        let t = tile(lat, lon, z: z)
        return catalog.source(z: t.z, x: t.x, y: t.y)?.id
    }

    @Test func picksTheServiceOfTheAreaHoldingTheTile() {
        #expect(source(48.8566, 2.3522) == "fr")         // Paris
        #expect(source(48.1372, 11.5756) == "de-by")     // Munich
        #expect(source(46.0037, 8.9511) == "ch")         // Lugano
        #expect(source(48.2082, 16.3738) == "at")        // Vienna
        #expect(source(52.3676, 4.9041) == "nl")         // Amsterdam
        #expect(source(52.5200, 13.4050) == "de-be")     // Berlin, inside Brandenburg's outline: the city-state first
        #expect(source(53.5511, 9.9937) == "de-hh")      // Hamburg
        #expect(source(50.8467, 4.3525) == "be-bru")     // Brussels, inside Flanders' outline
        #expect(source(46.4983, 11.3548) == "it-bz")     // Bolzano
        #expect(source(46.2044, 6.1432) == "ch")         // Geneva
        #expect(source(46.1930, 6.2350) == "fr")         // Annemasse, across the border
    }

    @Test func eoxWhereThereIsNoOpenService() {
        #expect(source(45.4642, 9.1900) == nil)          // Milan
        #expect(source(51.5074, -0.1278) == nil)         // London
        #expect(source(55.6761, 12.5683) == nil)         // Copenhagen (key needed)
        #expect(source(47.0, -12.0) == nil)              // the Atlantic
    }

    @Test func onlyFromZoom13() {
        #expect(source(48.8566, 2.3522, z: 12) == nil)
        #expect(source(48.8566, 2.3522, z: 13) == "fr")
        #expect(source(48.8566, 2.3522, z: 18) == "fr")
        #expect(source(48.8566, 2.3522, z: 19) == nil)   // the style stops at 18; MapLibre enlarges z18
    }

    @Test func buildsEachKindOfAddress() throws {
        let xyz = try #require(AerialImagery.url("https://a.test/{z}/{y}/{x}.jpeg", z: 17, x: 68_000, y: 46_000))
        #expect(xyz.absoluteString == "https://a.test/17/46000/68000.jpeg")
        // TMS rows count from the south: 2^z − 1 − y.
        let tms = try #require(AerialImagery.url("https://a.test/{z}/{x}/{-y}.png", z: 3, x: 4, y: 1))
        #expect(tms.absoluteString == "https://a.test/3/4/6.png")
        // WMS: the tile's EPSG:3857 bounds in metres, west,south,east,north. z1 tile (1, 0) is the north-east quarter.
        let wms = try #require(AerialImagery.url("https://a.test/wms?BBOX={bbox}&LAYERS=a", z: 1, x: 1, y: 0))
        let half = 20_037_508.342789244
        #expect(wms.absoluteString == "https://a.test/wms?BBOX=0.00,0.00,\(String(format: "%.2f", half)),\(String(format: "%.2f", half))&LAYERS=a")
    }

    @Test func everySourceIsOpenAndCredited() throws {
        #expect(catalog.sources.count >= 30)
        let blocked = ["google", "bing", "virtualearth", "mapbox", "apple", "arcgisonline", "esri", "codefor.de", "level2.si"]
        for s in catalog.sources {
            #expect(s.url.hasPrefix("https://"), "\(s.id)")
            #expect(!s.attribution.isEmpty && !s.licence.isEmpty && s.licenceURL.hasPrefix("https://"), "\(s.id)")
            #expect(catalog.hasArea(s.area), "\(s.id): no outline for \(s.area)")
            let host = URL(string: s.url.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: ""))?.host ?? ""
            #expect(!blocked.contains(where: host.contains), "\(s.id): \(host)")
            #expect(s.url.contains("{bbox}") || (s.url.contains("{z}") && s.url.contains("{x}")), "\(s.id)")
        }
        #expect(Set(catalog.sources.map(\.id)).count == catalog.sources.count)
    }

    // MARK: No-data pixels

    func jpeg(_ draw: (CGContext) -> Void) -> Data {
        let r = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        return r.jpegData(withCompressionQuality: 0.9) { draw($0.cgContext) }
    }

    @Test func aWhiteTileIsNoDataAndShowsEOX() {
        let white = jpeg { $0.setFillColor(UIColor.white.cgColor); $0.fill(CGRect(x: 0, y: 0, width: 256, height: 256)) }
        #expect(AerialImagery.dropNoData(white) == .empty)
    }

    @Test func aPhotoIsServedAsItCame() {
        let photo = jpeg { c in
            c.setFillColor(UIColor(red: 0.3, green: 0.4, blue: 0.2, alpha: 1).cgColor); c.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            c.setFillColor(UIColor.white.cgColor); c.fill(CGRect(x: 100, y: 100, width: 4, height: 4))   // a white roof
        }
        #expect(AerialImagery.dropNoData(photo) == .asIs)
    }

    @Test func aTileAcrossTheEdgeOfTheServiceLosesItsWhitePart() throws {
        let edge = jpeg { c in
            c.setFillColor(UIColor(red: 0.3, green: 0.4, blue: 0.2, alpha: 1).cgColor); c.fill(CGRect(x: 0, y: 0, width: 128, height: 256))
            c.setFillColor(UIColor.white.cgColor); c.fill(CGRect(x: 128, y: 0, width: 128, height: 256))
        }
        guard case let .cleared(png) = AerialImagery.dropNoData(edge) else { Issue.record("not cleared"); return }
        let image = try #require(UIImage(data: png)?.cgImage)
        #expect(image.alphaInfo != .none && image.alphaInfo != .noneSkipLast && image.alphaInfo != .noneSkipFirst)
        let px = try #require(Self.rgba(image))
        #expect(px(64, 128).a == 255)
        #expect(px(200, 128).a == 0)
    }

    static func rgba(_ image: CGImage) -> ((Int, Int) -> (r: UInt8, a: UInt8))? {
        var buf = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let ctx = CGContext(data: &buf, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let w = image.width
        return { x, y in let i = (y * w + x) * 4; return (buf[i], buf[i + 3]) }
    }
}
