import Foundation

/// A POI, park or station tapped on the Ride map as a place to route to (Filippo, 5 Nov). Reads the attributes the
/// map's layers draw: OpenMapTiles `poi` (name, class, subclass, osm id) and the pack's `velix_stations` (mode, name,
/// tiles "M1.red.0,M3.yellow.0").
enum MapFeaturePlace {
    /// The layers a tap picks from, nearest first: stations, then POIs and park names.
    static let layers: Set<String> = ["station-rail", "station-metro", "overlay-station-metro", "label-park",
                                      "poi-t1", "poi-t2", "poi-t3", "poi-t4", "poi-t5"]

    static func place(attributes a: [String: Any], at p: LatLon) -> Place? {
        guard let name = (a["name"] as? String) ?? (a["name_en"] as? String), !name.isEmpty else { return nil }
        let mode = a["mode"] as? String
        let cls = a["class"] as? String, sub = a["subclass"] as? String
        var kind = Place.Kind.poi
        var lines: [String] = [], families: [String] = []
        var category = PoiCategory.name(sub) ?? PoiCategory.name(cls)
        switch (mode, cls, sub) {
        case ("metro", _, _):
            kind = .metro
            category = "Metro station"
            // "M1.red.0,M3.yellow.0" → lines M1, M3 in red, yellow.
            for tile in ((a["tiles"] as? String) ?? "").split(separator: ",") {
                let parts = tile.split(separator: ".").map(String.init)
                guard parts.count >= 2 else { continue }
                lines.append(parts[0]); families.append(parts[1])
            }
        case ("train", _, _), (_, "railway", "station"), (_, "railway", "halt"):
            kind = .station
            category = "Railway station"
        case (_, "railway", "subway"):
            kind = .metro
            category = "Metro station"
        case (_, "park", _):
            kind = .park
            category = category ?? "Park"
        default: break
        }
        let osm = (a["id"] as? NSNumber)?.int64Value ?? (a["osm_id"] as? NSNumber)?.int64Value
        let id = osm.map { "tap-\($0)" } ?? String(format: "tap-%.5f,%.5f", p.lat, p.lon)
        return Place(id: id, name: name, subtitle: category ?? "", kind: kind, lat: p.lat, lon: p.lon,
                     lines: lines, lineFamilies: families)
    }
}
