import CoreLocation
@preconcurrency import FerrostarCore
@preconcurrency import FerrostarCoreFFI
import Foundation
@preconcurrency import Valhalla
import ValhallaConfigModels

/// Routes on the phone with Valhalla (valhalla-mobile) against the region pack tiles,
/// and hands the result to Ferrostar as OSRM-format JSON.
final class ValhallaOnDeviceProvider: RoutingProvider, @unchecked Sendable {
    /// Costing used when Ferrostar asks for a route (start and reroute): the selected option's costing.
    var profile: RoutingProfile
    /// Called after every route computation with the engine time in milliseconds.
    var onRouteComputed: (@Sendable (_ milliseconds: Double, _ route: Route?) -> Void)?

    private let valhalla: Valhalla
    private let parser = createOsrmResponseParser(polylinePrecision: 6)
    /// Valhalla is thread-safe per call, but one request at a time keeps memory predictable on older phones.
    private let queue = DispatchQueue(label: "velix.routing.valhalla", qos: .userInitiated)

    /// Builds the engine. Expensive (mmaps the tile extract), so create one per app session.
    init(tileExtract: URL, profile: RoutingProfile) throws {
        guard FileManager.default.fileExists(atPath: tileExtract.path) else {
            throw RoutingError.tilesMissing(tileExtract.path)
        }
        self.profile = profile
        valhalla = try Valhalla(configPath: try Self.writeConfig(tileExtract: tileExtract).path)
    }

    /// The default valhalla-mobile config with the pack's tiles, and room for rule exclusions: RoutePlanner boxes out
    /// every cobbled / tram-rail / step way near a trip (hundreds of small polygons, so a long total perimeter).
    /// The Valhalla inside valhalla-mobile 0.6.3 has no vertex limit (and rejects the `max_exclude_polygons_vertices` key).
    static func writeConfig(tileExtract: URL) throws -> URL {
        let config = try ValhallaConfig(tileExtractTar: tileExtract)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any] ?? [:]
        var limits = json["service_limits"] as? [String: Any] ?? [:]
        limits["max_exclude_polygons_length"] = 5_000_000
        json["service_limits"] = limits
        let url = URL.applicationSupportDirectory.appending(path: "valhalla-velix.json")
        try FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: json).write(to: url, options: .atomic)
        return url
    }

    /// Valhalla `route` with a raw JSON request, off the main thread.
    func route(rawRequest json: String) async throws -> String {
        try await run { try $0.route(rawRequest: json) }
    }

    /// Valhalla `trace_attributes` with a raw JSON request, off the main thread.
    func traceAttributes(rawRequest json: String) async throws -> String {
        try await run { try $0.traceAttributes(rawRequest: json) }
    }

    private func run(_ body: @escaping @Sendable (Valhalla) throws -> String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                continuation.resume(with: Result { try body(self.valhalla) })
            }
        }
    }

    func getRoutes(userLocation: UserLocation, waypoints: [Waypoint]) async throws -> [Route] {
        let request = try Self.requestJSON(from: userLocation, waypoints: waypoints, profile: profile)
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                let start = DispatchTime.now()
                do {
                    let response = try valhalla.route(rawRequest: request)
                    let routes = try parser.parseResponse(response: Data(response.utf8))
                    onRouteComputed?(Self.milliseconds(since: start), routes.first)
                    continuation.resume(returning: routes)
                } catch {
                    onRouteComputed?(Self.milliseconds(since: start), nil)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Valhalla route request asking for OSRM output with banner and voice instructions,
    /// which is what Ferrostar's OSRM parser expects.
    static func requestJSON(from userLocation: UserLocation, waypoints: [Waypoint], profile: RoutingProfile,
                            excludePolygons: [[[Double]]] = []) throws -> String {
        var start: [String: JSONValue] = [
            "lat": .number(userLocation.coordinates.lat),
            "lon": .number(userLocation.coordinates.lng),
        ]
        if let course = userLocation.courseOverGround {
            start["heading"] = .number(Double(course.degrees))
            start["heading_tolerance"] = .number(45)
        }
        let locations: [JSONValue] = [.object(start)] + waypoints.map {
            .object([
                "lat": .number($0.coordinate.lat),
                "lon": .number($0.coordinate.lng),
                "type": .string($0.kind == .via ? "via" : "break"),
            ])
        }
        var fields: [String: JSONValue] = [
            "locations": .array(locations),
            "costing": .string(profile.costing),
            "costing_options": .object([profile.costing: .object(profile.costingOptions)]),
            "format": .string("osrm"),
            "banner_instructions": .bool(true),
            "voice_instructions": .bool(true),
            "units": .string("kilometers"),
            "language": .string("en-US"),
            "directions_type": .string("instructions"),
        ]
        // `ignore_oneways` only holds in the forward half of Valhalla's default bidirectional search: the reverse tree
        // from the destination still respects one-ways, so contraflow streets near the end were never used (Via Soave →
        // Piazza Santo Stefano skipped Sforza → Laghetto, 2.5 km instead of Google's 2.0 km). A departure time switches
        // Valhalla to its forward-only time-dependent A*, where the option applies everywhere.
        if profile.costingOptions["ignore_oneways"] == .bool(true) {
            fields["date_time"] = .object(["type": .number(0)])
        }
        if !excludePolygons.isEmpty {  // rings of [lon, lat]
            fields["exclude_polygons"] = .array(excludePolygons.map { .array($0.map { .array($0.map(JSONValue.number)) }) })
        }
        return String(decoding: try JSONEncoder().encode(JSONValue.object(fields)), as: UTF8.self)
    }

    private static func milliseconds(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }
}
