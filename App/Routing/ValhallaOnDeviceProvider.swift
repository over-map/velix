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
        var config = try ValhallaConfig(tileExtractTar: tileExtract)
        // Rule enforcement excludes small boxes around cobbles, rails, steps… (RoutePlanner); allow more of them.
        config.serviceLimits?.maxExcludePolygonsLength = 60_000
        valhalla = try Valhalla(config)
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
        if !excludePolygons.isEmpty {  // rings of [lon, lat]
            fields["exclude_polygons"] = .array(excludePolygons.map { .array($0.map { .array($0.map(JSONValue.number)) }) })
        }
        return String(decoding: try JSONEncoder().encode(JSONValue.object(fields)), as: UTF8.self)
    }

    private static func milliseconds(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }
}
