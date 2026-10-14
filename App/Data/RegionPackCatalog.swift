import Foundation

/// Finds the newest published pack for a region among the repo's GitHub Releases (tags `pack-<region>-YYYY.MM[.N]`).
/// Uses the public API without a token (60 requests/hour per IP: plenty for a check on launch).
enum RegionPackCatalog {
    static let releasesURL = URL(string: "https://api.github.com/repos/over-map/velix/releases?per_page=30")!

    struct Release: Decodable {
        let tagName: String
        let draft: Bool
        let prerelease: Bool
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
