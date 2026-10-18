import Foundation

/// A place the rider can route to: a search result, Home, Work or a recent.
struct Place: Codable, Hashable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable { case address, street, station, metro, park, poi, city }

    var id: String
    var name: String
    var subtitle: String
    var kind: Kind
    var lat: Double
    var lon: Double
    /// Metro lines at a metro station ("M2", "M3"), shown as line tiles.
    var lines: [String] = []
    /// Their colour families, same order ("green", "yellow"; P3 mapRules).
    var lineFamilies: [String] = []

    var location: LatLon { LatLon(lat: lat, lon: lon) }

    /// Same place for recents dedupe: same id, or the same name within 50 m.
    func isSame(as other: Place) -> Bool {
        id == other.id || (name == other.name && Geo.distance(location, other.location) < 50)
    }
}
