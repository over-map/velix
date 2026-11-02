import Foundation

/// The regions Velix offers (Filippo, 2 Nov: Lombardy and its neighbours), from `packs.json` on the fixed Release
/// `pack-index` (pipeline/stages/index.py): where each region is and its newest pack. Until that index exists, the
/// newest `pack-lombardy-*` among the repo's latest Releases (public API, no token).
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

        /// Inside the region's border (its bbox when the index has no polygon).
        func contains(_ p: LatLon) -> Bool {
            if let polygon { return polygon.contains(p) }
            return bbox.count == 4 && p.lon >= bbox[0] && p.lat >= bbox[1] && p.lon <= bbox[2] && p.lat <= bbox[3]
        }
    }

    let schema: Int
    let regions: [Region]

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
        return try decoder.decode(RegionCatalog.self, from: data)
    }
}

enum RegionPackCatalog {
    static let indexURL = URL(string: "https://github.com/over-map/velix/releases/download/pack-index/packs.json")!
    static let releasesURL = URL(string: "https://api.github.com/repos/over-map/velix/releases?per_page=30")!

    struct Release: Decodable {
        let tagName: String
        let draft: Bool
        let prerelease: Bool
    }

    /// The catalog: the index, else Lombardy alone from the latest Releases.
    static func fetch() async throws -> RegionCatalog {
        if let (data, response) = try? await URLSession.shared.data(from: indexURL),
           (response as? HTTPURLResponse)?.statusCode == 200, let index = try? RegionCatalog.decode(data) {
            return index
        }
        guard let url = try await latestManifestURL(region: "lombardy"),
              let m = try? RegionPackManifest.decode(await URLSession.shared.data(from: url).0) else {
            return RegionCatalog(schema: 1, regions: [])
        }
        return RegionCatalog(schema: 1, regions: [.init(id: m.pack, name: m.name, tag: url.deletingLastPathComponent().lastPathComponent,
                                                         version: m.version, bbox: m.bbox, polygon: m.polygon,
                                                         downloadBytes: m.downloadBytes, manifest: url)])
    }

    static func latestTag(region: String, in releasesJSON: Data) throws -> String? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let prefix = "pack-\(region)-"
        // GitHub lists releases newest first; the first published match wins.
        return try decoder.decode([Release].self, from: releasesJSON)
            .first { !$0.draft && !$0.prerelease && $0.tagName.hasPrefix(prefix) }?.tagName
    }

    static func latestManifestURL(region: String = "lombardy") async throws -> URL? {
        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try latestTag(region: region, in: data).map(RegionPack.releaseManifestURL(tag:))
    }
}
