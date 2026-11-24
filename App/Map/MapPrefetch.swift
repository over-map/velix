import Foundation

/// The map along a ride's route, fetched at its start (Filippo, 24 Nov: the offline map is optional, so the map
/// mostly comes online): OpenFreeMap's tiles at z12–14 within 500 m of the route go into the online cache, so tunnels
/// and stretches without signal still show the map. OpenFreeMap stops at z14; the riding zooms enlarge those tiles.
/// Tiles a pack on the phone holds are skipped (``PackTileProtocol/warm(z:x:y:done:)``). About 60 tiles, a few MB, for
/// a 20 km ride; four at a time, in the background, stopped when the ride ends.
enum MapPrefetch {
    struct Tile: Hashable, Sendable { let z: Int; let x: Int; let y: Int }

    static let zooms = [14, 13, 12]
    static let bufferMeters = 500.0

    /// Riding zoom first, then the zooms out; each tile once, in route order.
    static func tiles(along route: [LatLon]) -> [Tile] {
        guard !route.isEmpty else { return [] }
        var seen = Set<Tile>(), out: [Tile] = []
        for z in zooms {
            for p in samples(route, every: 100) {
                let dLat = bufferMeters / 111_320, dLon = bufferMeters / (111_320 * max(cos(p.lat * .pi / 180), 0.01))
                let a = tile(LatLon(lat: p.lat + dLat, lon: p.lon - dLon), z), b = tile(LatLon(lat: p.lat - dLat, lon: p.lon + dLon), z)
                for x in a.x ... b.x {
                    for y in a.y ... b.y where seen.insert(Tile(z: z, x: x, y: y)).inserted { out.append(Tile(z: z, x: x, y: y)) }
                }
            }
        }
        return out
    }

    /// Fetches the tiles along the route, four at a time; cancelling the task stops it.
    static func warm(_ route: [LatLon]) -> Task<Void, Never> {
        let list = tiles(along: route)
        return Task.detached(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                var running = 0
                for t in list {
                    if Task.isCancelled { break }
                    if running == 4 { await group.next(); running -= 1 }
                    group.addTask {
                        await withCheckedContinuation { c in PackTileProtocol.warm(z: t.z, x: t.x, y: t.y) { c.resume() } }
                    }
                    running += 1
                }
            }
        }
    }

    private static func tile(_ p: LatLon, _ z: Int) -> Tile {
        let n = Double(1 << z), r = max(min(p.lat, 85.0511), -85.0511) * .pi / 180
        let x = Int((p.lon + 180) / 360 * n), y = Int((1 - log(tan(r) + 1 / cos(r)) / .pi) / 2 * n)
        return Tile(z: z, x: min(max(x, 0), Int(n) - 1), y: min(max(y, 0), Int(n) - 1))
    }

    /// The route's points, with extra ones so no gap is longer than `every` metres.
    private static func samples(_ route: [LatLon], every meters: Double) -> [LatLon] {
        var out = [route[0]]
        for (a, b) in zip(route, route.dropFirst()) {
            let d = Geo.distance(a, b), steps = max(1, Int((d / meters).rounded(.up)))
            for i in 1 ... steps {
                let f = Double(i) / Double(steps)
                out.append(LatLon(lat: a.lat + (b.lat - a.lat) * f, lon: a.lon + (b.lon - a.lon) * f))
            }
        }
        return out
    }
}
