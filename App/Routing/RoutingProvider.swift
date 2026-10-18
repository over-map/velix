import CoreLocation
@preconcurrency import FerrostarCore
@preconcurrency import FerrostarCoreFFI

/// Where routes come from. Iteration 1 has one implementation, ``ValhallaOnDeviceProvider``;
/// an online provider can be added later behind the same protocol (BRIEF §5).
protocol RoutingProvider: CustomRouteProvider, Sendable {
    /// Ride-type profile the provider routes with (costing JSON from `RoutingProfiles/`).
    var profile: RoutingProfile { get }
}

/// One Valhalla costing: the model and its options.
struct RoutingProfile: Sendable, Decodable, Equatable {
    let costing: String
    let costingOptions: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case costing
        case costingOptions = "costing_options"
    }
}

/// A ride type's costings (`RoutingProfiles/<id>.json`): Best = the ride type's own costing, Fastest = permissive.
struct RideProfile: Sendable, Decodable, Equatable {
    let id: String
    let best: RoutingProfile
    let fastest: RoutingProfile

    /// Rules that Valhalla's costing can express directly. Cobbles reach Valhalla as a bad surface (the pack retags
    /// them), so "No cobbles" sets how hard bad surfaces are avoided; "Paved roads only" makes road bikes refuse them.
    func adjusted(for rules: RuleSet) -> RideProfile {
        var options = best.costingOptions
        let current: Double = if case let .number(v) = options["avoid_bad_surfaces"] { v } else { 0.25 }
        if rules.enabled.contains(.pavedOnly) {
            options["avoid_bad_surfaces"] = .number(1.0)
        } else if rules.enabled.contains(.noCobbles) {
            options["avoid_bad_surfaces"] = .number(max(current, 0.8))
        } else if rules.rideType != .road {
            options["avoid_bad_surfaces"] = .number(min(current, 0.3))
        } else {
            options["avoid_bad_surfaces"] = .number(0.5)
        }
        // One-way streets (Filippo, 18 Oct): ridden both ways by default; "Respect one-way streets" in You turns it off.
        var fastestOptions = fastest.costingOptions
        if !rules.respectOneways {
            options["ignore_oneways"] = .bool(true)
            fastestOptions["ignore_oneways"] = .bool(true)
        }
        return RideProfile(id: id, best: RoutingProfile(costing: best.costing, costingOptions: options),
                           fastest: RoutingProfile(costing: fastest.costing, costingOptions: fastestOptions))
    }

    static func load(_ type: RideType, bundle: Bundle = .main) throws -> RideProfile {
        guard let url = bundle.url(forResource: type.rawValue, withExtension: "json", subdirectory: "RoutingProfiles")
            ?? bundle.url(forResource: type.rawValue, withExtension: "json")
        else { throw RoutingError.profileMissing(type.rawValue) }
        return try JSONDecoder().decode(RideProfile.self, from: Data(contentsOf: url))
    }
}

enum RoutingError: Error, Equatable, CustomStringConvertible {
    case profileMissing(String)
    case tilesMissing(String)
    case noRoute(String)

    var description: String {
        switch self {
        case let .profileMissing(id): "Routing profile \(id).json is not in the app bundle"
        case let .tilesMissing(path): "No routing tiles at \(path)"
        case let .noRoute(message): "No route: \(message)"
        }
    }
}

/// Minimal JSON value so costing options pass through unchanged into the Valhalla request.
enum JSONValue: Sendable, Equatable, Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case let .string(s): try c.encode(s)
        case let .number(n): try c.encode(n)
        case let .bool(b): try c.encode(b)
        case let .object(o): try c.encode(o)
        case let .array(a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }
}
