import Foundation

/// `manifest.json` of a region pack (pipeline/schema/manifest.schema.json, schema 1).
struct RegionPackManifest: Codable, Equatable, Sendable {
    struct File: Codable, Equatable, Sendable {
        enum Role: String, Codable, Sendable {
            case routingTiles = "routing_tiles", hazards, routes, transit
            /// OpenMapTiles vector tiles (PMTiles, uncompressed tiles) and the Velix overlay tiles (M5).
            case basemap, overlays
            /// The city area polygon (GeoJSON, M8): "destination outside the city" suggests bike + transit.
            case city
        }

        let name: String
        let asset: String
        let role: Role
        let bytes: Int64
        let sha256: String
        let unpackedBytes: Int64
        let unpackedSha256: String
    }

    struct Source: Codable, Equatable, Sendable {
        let id: String
        let name: String
        let url: String
        let date: String
        let licence: String
        let attribution: String
    }

    let schema: Int
    let pack: String
    let name: String
    let version: String
    let built: String
    let valhalla: String
    let bbox: [Double]
    let files: [File]
    let downloadBytes: Int64
    let unpackedBytes: Int64
    let budgetBytes: Int64
    let sources: [Source]
    /// The region's border, simplified (packs from Nov 2026; older packs: the bbox).
    var polygon: RegionShape?
    /// Where the pack's routing data reaches: the border plus a buffer (packs from Nov 2026).
    var coverage: Coverage?

    struct Coverage: Codable, Equatable, Sendable {
        let bufferKm: Double
        let bbox: [Double]
        let polygon: RegionShape
    }

    static let supportedSchema = 1

    static func decode(_ data: Data) throws -> RegionPackManifest {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        struct Probe: Decodable { let schema: Int }
        let schema = try decoder.decode(Probe.self, from: data).schema
        guard schema == supportedSchema else { throw RegionPackError.unsupportedSchema(schema) }
        return try decoder.decode(RegionPackManifest.self, from: data)
    }

    func file(_ role: File.Role) -> File? { files.first { $0.role == role } }
}

enum RegionPackError: Error, Equatable, CustomStringConvertible {
    case unsupportedSchema(Int)
    case checksumMismatch(String)
    case sizeMismatch(String)
    case missingFile(String)
    case decompression(String)

    var description: String {
        switch self {
        case let .unsupportedSchema(v): "Region pack schema \(v) is newer than this app understands"
        case let .checksumMismatch(f): "Checksum mismatch for \(f)"
        case let .sizeMismatch(f): "Unexpected size for \(f)"
        case let .missingFile(f): "Region pack has no \(f)"
        case let .decompression(f): "Could not unpack \(f)"
        }
    }
}

/// A GeoJSON MultiPolygon's coordinates (polygons → rings → [lon, lat]): a region's border or its coverage.
struct RegionShape: Codable, Equatable, Sendable {
    let polygons: [[[[Double]]]]

    init(polygons: [[[[Double]]]]) { self.polygons = polygons }
    init(from decoder: Decoder) throws { polygons = try decoder.singleValueContainer().decode([[[[Double]]]].self) }
    func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(polygons) }

    /// Even-odd ray casting over every ring: inside an outer ring and not in one of its holes.
    func contains(_ p: LatLon) -> Bool {
        polygons.contains { rings in
            rings.reduce(false) { inside, ring in Self.inRing(p, ring) ? !inside : inside }
        }
    }

    private static func inRing(_ p: LatLon, _ ring: [[Double]]) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in 0 ..< ring.count {
            let (xi, yi, xj, yj) = (ring[i][0], ring[i][1], ring[j][0], ring[j][1])
            if (yi > p.lat) != (yj > p.lat), p.lon < (xj - xi) * (p.lat - yi) / (yj - yi) + xi { inside.toggle() }
            j = i
        }
        return inside
    }
}
