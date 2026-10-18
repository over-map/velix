import Foundation

/// Finds places for S2 Search. The live one is Photon (komoot, OpenStreetMap data); tests use fixtures.
protocol PlaceSearch: Sendable {
    func search(_ query: String, near: LatLon?) async throws -> [Place]
}

enum PlaceSearchError: Error, Equatable { case offline, badResponse }

/// Photon geocoder (https://photon.komoot.io, fair use): biased to the rider, limited to the pack region.
struct PhotonSearch: PlaceSearch {
    var endpoint = URL(string: "https://photon.komoot.io/api/")!
    /// Lombardy (the pack bbox): routes only work inside it.
    var bbox: [Double] = [8.49785, 44.67991, 11.42765, 46.63535]
    var limit = 8
    var session: URLSession = .shared

    func search(_ query: String, near: LatLon?) async throws -> [Place] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return [] }
        var c = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "q", value: q), URLQueryItem(name: "limit", value: String(limit)),
                     URLQueryItem(name: "lang", value: "en"),
                     URLQueryItem(name: "bbox", value: bbox.map { String($0) }.joined(separator: ","))]
        if let near {
            items += [URLQueryItem(name: "lat", value: String(near.lat)), URLQueryItem(name: "lon", value: String(near.lon))]
        }
        c.queryItems = items
        var request = URLRequest(url: c.url!, timeoutInterval: 10)
        request.setValue("Velix/0.1 (https://github.com/over-map/velix)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PlaceSearchError.badResponse }
            return try Self.parse(data)
        } catch let e as URLError where [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
                                         .internationalRoamingOff, .timedOut, .cannotFindHost].contains(e.code) {
            throw PlaceSearchError.offline
        }
    }

    /// Photon GeoJSON → places, deduplicated by name + position.
    static func parse(_ data: Data) throws -> [Place] {
        struct FC: Decodable { let features: [F] }
        struct F: Decodable { let geometry: G; let properties: P }
        struct G: Decodable { let coordinates: [Double] }
        struct P: Decodable {
            let osm_id: Int64?; let osm_type: String?; let osm_key: String?; let osm_value: String?; let type: String?
            let name: String?; let street: String?; let housenumber: String?; let district: String?; let city: String?
            let county: String?; let locality: String?
        }
        let fc = try JSONDecoder().decode(FC.self, from: data)
        var out: [Place] = []
        for f in fc.features where f.geometry.coordinates.count == 2 {
            let p = f.properties
            let streetLine = [p.street, p.housenumber].compactMap { $0 }.joined(separator: " ")
            let name = p.name ?? (streetLine.isEmpty ? nil : streetLine)
            guard let name else { continue }
            let kind = Self.kind(key: p.osm_key, value: p.osm_value, type: p.type)
            let area = [p.district ?? p.locality, p.city ?? p.county].compactMap { $0 }.filter { $0 != name }
            var subtitle: [String] = []
            switch kind {
            case .station: subtitle.append("Railway station")
            case .metro: subtitle.append("Metro station")
            default: break
            }
            if p.name != nil, !streetLine.isEmpty, kind != .street { subtitle.append(streetLine) }
            subtitle += area.prefix(1)
            let place = Place(id: "\(p.osm_type ?? "x")\(p.osm_id ?? 0)", name: name, subtitle: subtitle.joined(separator: " · "),
                              kind: kind, lat: f.geometry.coordinates[1], lon: f.geometry.coordinates[0])
            if !out.contains(where: { $0.isSame(as: place) }) { out.append(place) }
        }
        return out
    }

    static func kind(key: String?, value: String?, type: String?) -> Place.Kind {
        switch (key, value) {
        case ("railway", "station"), ("railway", "halt"), ("public_transport", "station"): return .station
        case ("railway", "subway_entrance"), ("station", "subway"), ("railway", "subway"): return .metro
        case ("leisure", "park"), ("leisure", "garden"), ("boundary", "national_park"): return .park
        case ("highway", _): return .street
        case ("place", "city"), ("place", "town"), ("place", "village"): return .city
        default: return type == "house" ? .address : (type == "street" ? .street : .poi)
        }
    }
}
