import CoreLocation
@preconcurrency import FerrostarCore
@preconcurrency import FerrostarCoreFFI
import Foundation
import Valhalla
import ValhallaConfigModels

/// Routes on the phone with Valhalla (valhalla-mobile) against the region pack tiles,
/// and hands the result to Ferrostar as OSRM-format JSON.
final class ValhallaOnDeviceProvider: RoutingProvider, @unchecked Sendable {
    let profile: RoutingProfile
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
        valhalla = try Valhalla(ValhallaConfig(tileExtractTar: tileExtract))
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
    static func requestJSON(from userLocation: UserLocation, waypoints: [Waypoint], profile: RoutingProfile) throws -> String {
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
        let body: JSONValue = .object([
            "locations": .array(locations),
            "costing": .string(profile.costing),
            "costing_options": .object([profile.costing: .object(profile.costingOptions)]),
            "format": .string("osrm"),
            "banner_instructions": .bool(true),
            "voice_instructions": .bool(true),
            "units": .string("kilometers"),
            "language": .string("en-US"),
            "directions_type": .string("instructions"),
        ])
        return String(decoding: try JSONEncoder().encode(body), as: UTF8.self)
    }

    private static func milliseconds(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }
}
