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

    init(id: String, name: String, subtitle: String, kind: Kind, lat: Double, lon: Double, lines: [String] = [],
         lineFamilies: [String] = []) {
        self.id = id; self.name = name; self.subtitle = subtitle; self.kind = kind; self.lat = lat; self.lon = lon
        self.lines = lines; self.lineFamilies = lineFamilies
    }

    /// Fields added later are optional in stored state (an app update must not lose Home and Work).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .poi
        lat = try c.decode(Double.self, forKey: .lat)
        lon = try c.decode(Double.self, forKey: .lon)
        lines = try c.decodeIfPresent([String].self, forKey: .lines) ?? []
        lineFamilies = try c.decodeIfPresent([String].self, forKey: .lineFamilies) ?? []
    }

    var location: LatLon { LatLon(lat: lat, lon: lon) }

    /// Same place for recents dedupe: same id, or the same name within 50 m.
    func isSame(as other: Place) -> Bool {
        id == other.id || (name == other.name && Geo.distance(location, other.location) < 50)
    }
}
