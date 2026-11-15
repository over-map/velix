import CryptoKit
import Foundation

/// The regions Velix offers: `packs.json` on the fixed Release `pack-index` (pipeline/stages/index.py), signed
/// (`packs.json.sig`, ``PackSignature``): where each region is and its newest pack. Schema 2 (M11 PR 3) adds the mirror
/// list and each region's country, and keeps only a small outline per region (the exact border is in its manifest).
struct RegionCatalog: Codable, Equatable, Sendable {
    struct Region: Codable, Equatable, Sendable, Identifiable {
        let id: String
        let name: String
        let tag: String
        let version: String
        let bbox: [Double]
        let polygon: RegionShape?
        let downloadBytes: Int64
        let manifest: URL
        /// ISO 3166-1 alpha-2 (schema 2).
        var country: String?

        /// Inside the region's outline (its bbox when the index has no polygon).
        func contains(_ p: LatLon) -> Bool {
            if let polygon { return polygon.contains(p) }
            return bbox.count == 4 && p.lon >= bbox[0] && p.lat >= bbox[1] && p.lon <= bbox[2] && p.lat <= bbox[3]
        }
    }

    let schema: Int
    let regions: [Region]
    /// Where release assets are, tried in order: `<mirror><tag>/<asset>` (schema 2; schema 1: GitHub only).
    var mirrors: [URL]?

    static let supportedSchemas = 1 ... 2
    static let github = URL(string: "https://github.com/over-map/velix/releases/download/")!

    /// The mirrors to try, GitHub when the index names none.
    var assetMirrors: [URL] { (mirrors?.isEmpty ?? true) ? [Self.github] : mirrors! }

    func region(_ id: String) -> Region? { regions.first { $0.id == id } }
    func region(containing p: LatLon) -> Region? { regions.first { $0.contains(p) } }

    /// The bbox around every region (Search keeps to it).
    var bbox: [Double]? {
        let boxes = regions.map(\.bbox).filter { $0.count == 4 }
        guard !boxes.isEmpty else { return nil }
        return [boxes.map { $0[0] }.min()!, boxes.map { $0[1] }.min()!, boxes.map { $0[2] }.max()!, boxes.map { $0[3] }.max()!]
    }

    static func decode(_ data: Data) throws -> RegionCatalog {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        struct Probe: Decodable { let schema: Int }
        let schema = try decoder.decode(Probe.self, from: data).schema
        guard supportedSchemas.contains(schema) else { throw RegionPackError.unsupportedSchema(schema) }
        return try decoder.decode(RegionCatalog.self, from: data)
    }
}

enum RegionPackCatalog {
    static let indexURL = RegionCatalog.github.appending(path: "pack-index/packs.json")

    /// Fetches a URL's bytes (tests serve fixtures).
    typealias Loader = @Sendable (URL) async throws -> Data

    static let liveLoader: Loader = { url in
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    /// The signed index. Throws ``RegionPackError/unsigned(_:)`` when `packs.json.sig` is missing or doesn't match:
    /// an index anyone could have written never reaches the download list.
    static func fetch(from url: URL = indexURL, key: Curve25519.Signing.PublicKey? = PackSignature.velix,
                      load: Loader = liveLoader) async throws -> RegionCatalog {
        let data = try await load(url)
        let signature = try? await load(url.appendingPathExtension("sig"))
        guard let signature, PackSignature.verify(data, signature: signature, key: key) else {
            throw RegionPackError.unsigned(url.lastPathComponent)
        }
        return try RegionCatalog.decode(data)
    }
}
