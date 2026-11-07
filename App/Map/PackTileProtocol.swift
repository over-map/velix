import Foundation
import MapLibre

/// Serves the map's vector tiles from every installed region pack as one source, so the map shows them side by side
/// with one set of layers (Filippo, 2 Nov: several regions on the phone). The styles ask for
/// `https://tiles.velix.invalid/{basemap|overlays|terrain}/{z}/{x}/{y}`; MapLibre's session (``install()``) routes those here.
///
/// A basemap tile wholly inside a pack's border comes from the pack (offline, as fast as ever while riding). Any other
/// tile, at low zoom, across a border or outside every pack, comes from OpenFreeMap (the same OpenMapTiles schema),
/// kept in a 100 MB disk cache: the map shows the whole world, and places seen before show offline (Filippo, 5 Nov).
/// Offline and not cached, a border tile falls back to the packs' part of it (merged, ``VectorTileMerge``).
final class PackTileProtocol: URLProtocol, @unchecked Sendable {
    static let host = "tiles.velix.invalid"

    /// One installed pack's map files and its border (`nil`: side-loaded or older packs, its tiles' bounds).
    struct Source: Sendable {
        var basemap: URL?
        var overlays: URL?
        var border: RegionShape?
    }

    private struct Archive { let tiles: PMTiles; let border: RegionShape? }

    nonisolated(unsafe) private static var basemaps: [Archive] = []
    nonisolated(unsafe) private static var overlays: [PMTiles] = []
    /// "z/x/y" → index of the pack holding the whole tile, or -1 (crossing a border, or outside).
    nonisolated(unsafe) private static var inside: [String: Int] = [:]
    private static let lock = NSLock()
    nonisolated(unsafe) private static var onlineTemplate: String? = UserDefaults.standard.string(forKey: templateKey)
    nonisolated(unsafe) private static var templateChecked = false
    private static let templateKey = "velix.onlineTileTemplate"

    /// OpenFreeMap tiles, cached on disk (their responses allow ten years; the URL names the planet build).
    static let onlineSession: URLSession = {
        let config = URLSessionConfiguration.default
        let dir = URL.cachesDirectory.appending(path: "velix-online-tiles", directoryHint: .isDirectory)
        config.urlCache = URLCache(memoryCapacity: 8_000_000, diskCapacity: 100_000_000, directory: dir)
        config.requestCachePolicy = .useProtocolCachePolicy
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    /// Point MapLibre's network session at this protocol (once, before the first map).
    static func install() {
        let manager = MLNNetworkConfiguration.sharedManager
        let config = manager.sessionConfiguration ?? .default
        config.protocolClasses = [PackTileProtocol.self] + (config.protocolClasses ?? [])
        manager.sessionConfiguration = config
        // Pack tiles are on the phone already and online ones have their own cache (``onlineSession``): MapLibre's
        // HTTP tile cache would only copy them (and, between maps, served bytes the parser rejected).
        MLNOfflineStorage.shared.setMaximumAmbientCacheSize(0) { _ in }
    }

    /// The installed packs' map files.
    static func use(_ sources: [Source]) {
        let b = sources.compactMap { s in s.basemap.flatMap { try? PMTiles(url: $0) }.map { Archive(tiles: $0, border: s.border) } }
        let o = sources.compactMap { s in s.overlays.flatMap { try? PMTiles(url: $0) } }
        lock.lock(); defer { lock.unlock() }
        basemaps = b
        overlays = o
        inside = [:]
    }

    /// Files without borders (side-loaded packs, tests).
    static func use(basemaps: [URL], overlays: [URL]) {
        use(basemaps.map { Source(basemap: $0) } + overlays.map { Source(overlays: $0) })
    }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == host }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return fail() }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count == 4, let z = Int(parts[1]), let x = Int(parts[2]), let y = Int(parts[3].split(separator: ".")[0]) else {
            return fail()
        }
        if parts[0] == "terrain" {
            // Hillshade (6 Nov): Mapterhorn's Terrarium elevation, online only, through the same 100 MB cache.
            guard let url = Self.url(Self.terrainTemplate, z: z, x: x, y: y) else { return fail() }
            return Self.fetch(url) { [self] data in respond(data ?? Data(), contentType: "image/webp") }
        }
        if parts[0] == "imagery" {
            // Satellite (7 Nov): Esri World Imagery, keyless; EOX Sentinel-2 cloudless where Esri fails. Online, cached.
            return Self.imagery(z: z, x: x, y: y) { [self] data in respond(data ?? Data(), contentType: "image/jpeg") }
        }
        if parts[0] == "overlays" {
            let packs = Self.lock.withLock { Self.overlays }
            return respond(Self.tile(from: packs.filter { Self.covers($0.header.bounds, z: z, x: x, y: y) }, z: z, x: x, y: y))
        }
        let (packs, holder) = Self.basemapChoice(z: z, x: x, y: y)
        if let holder { return respond(Self.tile(from: [holder], z: z, x: x, y: y)) }
        // Decompressed lazily: only when the online tile can't be had.
        online(z: z, x: x, y: y) { Self.tile(from: packs, z: z, x: x, y: y) }
    }

    override func stopLoading() {}

    // MARK: Choosing

    /// The packs touching the tile, and the one holding all of it (serve it from the pack), if any.
    private static func basemapChoice(z: Int, x: Int, y: Int) -> ([PMTiles], PMTiles?) {
        let key = "\(z)/\(x)/\(y)"
        lock.lock()
        let all = basemaps
        let known = inside[key]
        lock.unlock()
        let touching = all.filter { covers($0.tiles.header.bounds, z: z, x: x, y: y) }
        let index = known ?? {
            let i = all.firstIndex { a in
                covers(a.tiles.header.bounds, z: z, x: x, y: y) && holds(a.border, bounds: a.tiles.header.bounds, z: z, x: x, y: y)
            } ?? -1
            lock.withLock { inside[key] = i }
            return i
        }()
        return (touching.map(\.tiles), index >= 0 && index < all.count ? all[index].tiles : nil)
    }

    /// Decompressed (MapLibre reads a tile body as plain MVT; tippecanoe's overlays are gzip inside the archive), and
    /// merged where two packs share the tile.
    private static func tile(from packs: [PMTiles], z: Int, x: Int, y: Int) -> Data {
        let raw = packs.compactMap { try? $0.vectorTile(z: z, x: x, y: y) }
        return raw.count <= 1 ? raw.first ?? Data() : VectorTileMerge.merge(raw)
    }

    /// The tile ([west, south, east, north]) for z/x/y.
    static func bounds(z: Int, x: Int, y: Int) -> [Double] {
        let n = Double(1 << z)
        func lat(_ t: Double) -> Double { atan(sinh(.pi * (1 - 2 * t / n))) * 180 / .pi }
        return [Double(x) / n * 360 - 180, lat(Double(y + 1)), Double(x + 1) / n * 360 - 180, lat(Double(y))]
    }

    /// The tile touches the archive's bounds ([west, south, east, north]).
    static func covers(_ b: [Double], z: Int, x: Int, y: Int) -> Bool {
        guard b.count == 4 else { return true }
        let t = bounds(z: z, x: x, y: y)
        return t[2] >= b[0] && t[0] <= b[2] && t[3] >= b[1] && t[1] <= b[3]
    }

    /// The whole tile lies inside the border: its four corners are inside and no border vertex lies within it (a
    /// straight border edge that cuts the tile leaves a corner outside). Without a border: inside the tiles' bounds.
    static func holds(_ border: RegionShape?, bounds b: [Double], z: Int, x: Int, y: Int) -> Bool {
        let t = bounds(z: z, x: x, y: y)
        guard let border else {
            return b.count == 4 && t[0] >= b[0] && t[1] >= b[1] && t[2] <= b[2] && t[3] <= b[3]
        }
        let corners = [LatLon(lat: t[1], lon: t[0]), LatLon(lat: t[1], lon: t[2]), LatLon(lat: t[3], lon: t[0]), LatLon(lat: t[3], lon: t[2])]
        guard corners.allSatisfy(border.contains) else { return false }
        for rings in border.polygons {
            for ring in rings {
                for v in ring where v.count >= 2 && v[0] > t[0] && v[0] < t[2] && v[1] > t[1] && v[1] < t[3] { return false }
            }
        }
        return true
    }

    // MARK: Responses

    private func respond(_ data: Data, status: Int = 200, contentType: String = "application/x-protobuf") {
        guard let url = request.url, let r = HTTPURLResponse(url: url, statusCode: data.isEmpty ? 204 : status, httpVersion: "HTTP/1.1",
                                                             headerFields: ["Content-Type": contentType, "Cache-Control": "no-store"]) else { return fail() }
        client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
        if !data.isEmpty { client?.urlProtocol(self, didLoad: data) }
        client?.urlProtocolDidFinishLoading(self)
    }

    private func fail() {
        client?.urlProtocol(self, didFailWithError: URLError(.badURL))
    }

    /// OpenFreeMap's tile (from the cache when offline), else `fallback`.
    private func online(z: Int, x: Int, y: Int, fallback: @escaping @Sendable () -> Data) {
        Self.template { [self] template in
            guard let template, let url = Self.url(template, z: z, x: x, y: y) else { return respond(fallback()) }
            Self.fetch(url) { [self] data in respond(data ?? fallback()) }
        }
    }

    /// Mapterhorn (mapterhorn.com): open elevation data worldwide, Copernicus GLO-30 at 30 m, finer where countries
    /// publish it (Lombardy 5 m, Switzerland 0.5–2 m); z0–12 everywhere.
    static let terrainTemplate = "https://tiles.mapterhorn.com/{z}/{x}/{y}.webp"

    /// Esri World Imagery (Filippo, 7 Nov: no API key): sub-metre in European cities. Its tile path is z/y/x.
    static let imageryTemplate = "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
    /// EOX Sentinel-2 cloudless 2024 (s2maps.eu, CC BY-NC-SA 4.0), 10 m: where Esri doesn't answer.
    static let imageryFallbackTemplate = "https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2024_3857/default/g/{z}/{y}/{x}.jpg"

    /// One satellite tile: Esri, else EOX, else the cache (the map's `imagery` source).
    static func imagery(z: Int, x: Int, y: Int, done: @escaping @Sendable (Data?) -> Void) {
        guard let esri = url(imageryTemplate, z: z, x: x, y: y), let eox = url(imageryFallbackTemplate, z: z, x: x, y: y) else {
            return done(nil)
        }
        fetch(esri) { data in
            if let data { return done(data) }
            fetch(eox, done: done)
        }
    }

    static func url(_ template: String, z: Int, x: Int, y: Int) -> URL? {
        URL(string: template.replacingOccurrences(of: "{z}", with: "\(z)").replacingOccurrences(of: "{x}", with: "\(x)")
            .replacingOccurrences(of: "{y}", with: "\(y)"))
    }

    /// The network, then (offline, or the server failing) whatever the cache holds.
    private static func fetch(_ url: URL, done: @escaping @Sendable (Data?) -> Void) {
        onlineSession.dataTask(with: url) { data, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200, let data { return done(data) }
            let cached = URLRequest(url: url, cachePolicy: .returnCacheDataDontLoad)
            onlineSession.dataTask(with: cached) { data, response, _ in
                done((response as? HTTPURLResponse)?.statusCode == 200 ? data : nil)
            }.resume()
        }.resume()
    }

    /// The current tile URL (OpenFreeMap's TileJSON names the planet build). The last one is kept, so cached tiles
    /// still resolve offline; it is checked once per launch.
    private static func template(_ done: @escaping @Sendable (String?) -> Void) {
        let (cached, checked) = lock.withLock { () -> (String?, Bool) in
            defer { templateChecked = true }
            return (onlineTemplate, templateChecked)
        }
        if let cached {
            if !checked { refreshTemplate { _ in } }
            return done(cached)
        }
        refreshTemplate(done)
    }

    private static func refreshTemplate(_ done: @escaping @Sendable (String?) -> Void) {
        struct TileJSON: Decodable { let tiles: [String] }
        guard let url = URL(string: VelixMapStyle.onlineBasemap) else { return done(nil) }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let t = data.flatMap { try? JSONDecoder().decode(TileJSON.self, from: $0) }?.tiles.first
            if let t {
                lock.withLock { onlineTemplate = t }
                UserDefaults.standard.set(t, forKey: templateKey)
            }
            done(t ?? lock.withLock { onlineTemplate })
        }.resume()
    }
}
