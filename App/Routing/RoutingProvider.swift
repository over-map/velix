import CoreLocation
@preconcurrency import FerrostarCore
@preconcurrency import FerrostarCoreFFI

/// Where routes come from. Iteration 1 has one implementation, ``ValhallaOnDeviceProvider``;
/// an online provider can be added later behind the same protocol (BRIEF §5).
protocol RoutingProvider: CustomRouteProvider, Sendable {
    /// Ride-type profile the provider routes with (costing JSON from `RoutingProfiles/`).
    var profile: RoutingProfile { get }
}

/// A ride-type profile: the Valhalla costing and its options.
/// M1 ships only `city` as a spike; M3 defines all six ride types with golden tests.
struct RoutingProfile: Sendable, Decodable, Equatable {
    let id: String
    let costing: String
    let costingOptions: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case id
        case costing
        case costingOptions = "costing_options"
    }

    static func load(_ id: String, bundle: Bundle = .main) throws -> RoutingProfile {
        guard let url = bundle.url(forResource: id, withExtension: "json", subdirectory: "RoutingProfiles")
            ?? bundle.url(forResource: id, withExtension: "json")
        else { throw RoutingError.profileMissing(id) }
        return try JSONDecoder().decode(RoutingProfile.self, from: Data(contentsOf: url))
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
