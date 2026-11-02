import Foundation
import MapLibre

/// Serves the map's vector tiles from every installed region pack as one source, so the map shows them side by side
/// with one set of layers (Filippo, 2 Nov: several regions on the phone). The styles ask for
/// `https://tiles.velix.invalid/{basemap|overlays}/{z}/{x}/{y}`; MapLibre's session (``install()``) routes those here.
/// A tile two packs share (at a border) is merged (``VectorTileMerge``). A basemap tile no pack has comes from
/// OpenFreeMap (the same OpenMapTiles schema) while online: browsing outside the packs still shows a map.
final class PackTileProtocol: URLProtocol, @unchecked Sendable {
    static let host = "tiles.velix.invalid"

    /// The archives per layer kind ("basemap", "overlays"), set when packs change.
    nonisolated(unsafe) private static var archives: [String: [PMTiles]] = [:]
    private static let lock = NSLock()
    nonisolated(unsafe) private static var onlineTemplate: String?

    /// Point MapLibre's network session at this protocol (once, before the first map).
    static func install() {
        let manager = MLNNetworkConfiguration.sharedManager
        let config = manager.sessionConfiguration ?? .default
        config.protocolClasses = [PackTileProtocol.self] + (config.protocolClasses ?? [])
        manager.sessionConfiguration = config
        // The tiles are on the phone already: MapLibre's HTTP tile cache would only copy them (and, between maps,
        // served bytes the parser rejected).
        MLNOfflineStorage.shared.setMaximumAmbientCacheSize(0) { _ in }
    }

    /// The installed packs' map files.
    static func use(basemaps: [URL], overlays: [URL]) {
        let open = { (urls: [URL]) in urls.compactMap { try? PMTiles(url: $0) } }
        let b = open(basemaps), o = open(overlays)
        lock.lock(); defer { lock.unlock() }
        archives = ["basemap": b, "overlays": o]
    }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == host }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return fail() }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count == 4, let z = Int(parts[1]), let x = Int(parts[2]), let y = Int(parts[3].split(separator: ".")[0]) else {
            return fail()
        }
        let kind = parts[0]
        Self.lock.lock()
        let packs = Self.archives[kind] ?? []
        Self.lock.unlock()
        let found = packs.filter { Self.covers($0.header.bounds, z: z, x: x, y: y) }
        // Decompressed: MapLibre reads a tile body as plain MVT (tippecanoe's overlays are gzip inside the archive).
        let raw = found.compactMap { try? $0.vectorTile(z: z, x: x, y: y) }
        if !raw.isEmpty { return respond(raw.count == 1 ? raw[0] : VectorTileMerge.merge(raw)) }
        if kind == "basemap" { return online(z: z, x: x, y: y) }
        respond(Data())
    }

    override func stopLoading() {}

    // MARK: Responses

    private func respond(_ data: Data, status: Int = 200) {
        guard let url = request.url, let r = HTTPURLResponse(url: url, statusCode: data.isEmpty ? 204 : status, httpVersion: "HTTP/1.1",
                                                             headerFields: ["Content-Type": "application/x-protobuf", "Cache-Control": "no-store"]) else { return fail() }
        client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
        if !data.isEmpty { client?.urlProtocol(self, didLoad: data) }
        client?.urlProtocolDidFinishLoading(self)
    }

    private func fail() {
        client?.urlProtocol(self, didFailWithError: URLError(.badURL))
    }

    /// Outside the packs: OpenFreeMap's tile (its TileJSON names the current tile URL), or an empty tile offline.
    private func online(z: Int, x: Int, y: Int) {
        Self.template { [self] template in
            guard let template, let url = URL(string: template.replacingOccurrences(of: "{z}", with: "\(z)")
                .replacingOccurrences(of: "{x}", with: "\(x)").replacingOccurrences(of: "{y}", with: "\(y)")) else {
                return respond(Data())
            }
            URLSession.shared.dataTask(with: url) { [self] data, response, _ in
                respond((response as? HTTPURLResponse)?.statusCode == 200 ? data ?? Data() : Data())
            }.resume()
        }
    }

    private static func template(_ done: @escaping @Sendable (String?) -> Void) {
        if let cached = lock.withLock({ onlineTemplate }) { return done(cached) }
        struct TileJSON: Decodable { let tiles: [String] }
        guard let url = URL(string: VelixMapStyle.onlineBasemap) else { return done(nil) }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let t = data.flatMap { try? JSONDecoder().decode(TileJSON.self, from: $0) }?.tiles.first
            if let t { lock.withLock { onlineTemplate = t } }
            done(t)
        }.resume()
    }

    /// The tile touches the archive's bounds ([west, south, east, north]).
    static func covers(_ b: [Double], z: Int, x: Int, y: Int) -> Bool {
        guard b.count == 4 else { return true }
        let n = Double(1 << z)
        let west = Double(x) / n * 360 - 180, east = Double(x + 1) / n * 360 - 180
        func lat(_ t: Double) -> Double { atan(sinh(.pi * (1 - 2 * t / n))) * 180 / .pi }
        let north = lat(Double(y)), south = lat(Double(y + 1))
        return east >= b[0] && west <= b[2] && north >= b[1] && south <= b[3]
    }
}
