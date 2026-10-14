import Foundation

/// `manifest.json` of a region pack (pipeline/schema/manifest.schema.json, schema 1).
struct RegionPackManifest: Codable, Equatable, Sendable {
    struct File: Codable, Equatable, Sendable {
        enum Role: String, Codable, Sendable {
            case routingTiles = "routing_tiles", hazards, routes, transit
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
