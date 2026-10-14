import Foundation

/// Small geometry toolkit for route analysis (local equirectangular metres; fine for city-scale distances).
enum Geo {
    static let earthRadius = 6_371_000.0

    static func distance(_ a: LatLon, _ b: LatLon) -> Double {
        let x = (b.lon - a.lon) * .pi / 180 * cos((a.lat + b.lat) / 2 * .pi / 180)
        let y = (b.lat - a.lat) * .pi / 180
        return sqrt(x * x + y * y) * earthRadius
    }

    /// Compass bearing a → b (0 = north, clockwise).
    static func bearing(_ a: LatLon, _ b: LatLon) -> Double {
        let x = (b.lon - a.lon) * cos((a.lat + b.lat) / 2 * .pi / 180)
        let y = b.lat - a.lat
        let deg = atan2(x, y) * 180 / .pi
        return deg < 0 ? deg + 360 : deg
    }

    static func angleBetween(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }

    /// Distance from p to segment a–b, and the fraction t (0…1) of the closest point along it.
    static func distance(from p: LatLon, toSegment a: LatLon, _ b: LatLon) -> (meters: Double, t: Double) {
        let k = cos(p.lat * .pi / 180)
        let ax = a.lon * k, ay = a.lat, bx = b.lon * k, by = b.lat, px = p.lon * k, py = p.lat
        let dx = bx - ax, dy = by - ay
        let len2 = dx * dx + dy * dy
        let t = len2 > 0 ? max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / len2)) : 0
        let c = LatLon(lat: ay + t * dy, lon: (ax + t * dx) / k)
        return (distance(p, c), t)
    }

    static func length(_ line: [LatLon]) -> Double {
        zip(line, line.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    /// Bounding box grown by `meters`: (minLat, minLon, maxLat, maxLon).
    static func bbox(_ points: [LatLon], padding meters: Double) -> (Double, Double, Double, Double) {
        let lats = points.map(\.lat), lons = points.map(\.lon)
        let dLat = meters / 111_320
        let midLat = ((lats.min() ?? 0) + (lats.max() ?? 0)) / 2
        let dLon = meters / (111_320 * max(cos(midLat * .pi / 180), 0.01))
        return ((lats.min() ?? 0) - dLat, (lons.min() ?? 0) - dLon, (lats.max() ?? 0) + dLat, (lons.max() ?? 0) + dLon)
    }

    /// Closed ring [[lon, lat]] around the points, `meters` of padding, for Valhalla `exclude_polygons`.
    static func box(around points: [LatLon], padding meters: Double) -> [[Double]] {
        let (s, w, n, e) = bbox(points, padding: meters)
        return [[w, s], [e, s], [e, n], [w, n], [w, s]]
    }

    static func decodePolyline6(_ encoded: String) -> [LatLon] {
        var coords: [LatLon] = []
        var lat = 0, lon = 0
        var bytes = Array(encoded.utf8)[...]
        func next() -> Int? {
            var result = 0, shift = 0
            while let byte = bytes.popFirst() {
                let b = Int(byte) - 63
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20 { return (result & 1) != 0 ? ~(result >> 1) : result >> 1 }
            }
            return nil
        }
        while let dLat = next(), let dLon = next() {
            lat += dLat; lon += dLon
            coords.append(LatLon(lat: Double(lat) / 1e6, lon: Double(lon) / 1e6))
        }
        return coords
    }
}
