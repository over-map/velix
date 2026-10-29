import Foundation

/// A coordinate (degrees). Kept independent of Ferrostar so the analysis is pure and testable.
struct LatLon: Hashable, Sendable, Codable {
    let lat: Double
    let lon: Double
}

/// One Valhalla edge from `trace_attributes` (edge_walk over a route shape).
struct RouteEdge: Decodable, Sendable, Equatable {
    let wayId: Int64
    let lengthKm: Double
    let use: String
    let cycleLane: String
    let roadClass: String
    let surface: String
    let unpaved: Bool
    let maxUpwardGrade: Int
    let maxDownwardGrade: Int
    /// Average grade over the edge (%, signed). Steadier than max_*_grade, which picks up spikes from the
    /// surface model (Copernicus GLO-30 includes buildings and trees).
    let weightedGrade: Double
    let meanElevation: Double?
    let names: [String]
    /// Valhalla's speed for the edge (km/h): maxspeed if tagged, else a default for the road class.
    let speed: Int
    let beginShapeIndex: Int
    let endShapeIndex: Int

    var meters: Double { lengthKm * 1000 }
    var grade: Double { abs(weightedGrade) }
    var name: String? { names.first }

    enum CodingKeys: String, CodingKey {
        case wayId = "way_id", lengthKm = "length", use, cycleLane = "cycle_lane", roadClass = "road_class", surface,
             unpaved, maxUpwardGrade = "max_upward_grade", maxDownwardGrade = "max_downward_grade",
             weightedGrade = "weighted_grade", meanElevation = "mean_elevation", names, speed, beginShapeIndex = "begin_shape_index",
             endShapeIndex = "end_shape_index"
    }

    init(wayId: Int64, lengthKm: Double, use: String = "road", cycleLane: String = "none",
         roadClass: String = "residential", surface: String = "paved_smooth", unpaved: Bool = false,
         maxUpwardGrade: Int = 0, maxDownwardGrade: Int = 0, weightedGrade: Double = 0, meanElevation: Double? = nil,
         names: [String] = [], speed: Int = 50, beginShapeIndex: Int = 0, endShapeIndex: Int = 0) {
        self.wayId = wayId; self.lengthKm = lengthKm; self.use = use; self.cycleLane = cycleLane
        self.roadClass = roadClass; self.surface = surface; self.unpaved = unpaved
        self.maxUpwardGrade = maxUpwardGrade; self.maxDownwardGrade = maxDownwardGrade; self.weightedGrade = weightedGrade
        self.meanElevation = meanElevation; self.names = names; self.speed = speed
        self.beginShapeIndex = beginShapeIndex; self.endShapeIndex = endShapeIndex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        wayId = try c.decodeIfPresent(Int64.self, forKey: .wayId) ?? 0
        lengthKm = try c.decode(Double.self, forKey: .lengthKm)
        use = try c.decodeIfPresent(String.self, forKey: .use) ?? "road"
        cycleLane = try c.decodeIfPresent(String.self, forKey: .cycleLane) ?? "none"
        roadClass = try c.decodeIfPresent(String.self, forKey: .roadClass) ?? "residential"
        surface = try c.decodeIfPresent(String.self, forKey: .surface) ?? "paved"
        unpaved = try c.decodeIfPresent(Bool.self, forKey: .unpaved) ?? false
        maxUpwardGrade = try c.decodeIfPresent(Int.self, forKey: .maxUpwardGrade) ?? 0
        maxDownwardGrade = try c.decodeIfPresent(Int.self, forKey: .maxDownwardGrade) ?? 0
        weightedGrade = try c.decodeIfPresent(Double.self, forKey: .weightedGrade) ?? 0
        meanElevation = try c.decodeIfPresent(Double.self, forKey: .meanElevation)
        names = try c.decodeIfPresent([String].self, forKey: .names) ?? []
        speed = try c.decodeIfPresent(Int.self, forKey: .speed) ?? 50
        beginShapeIndex = try c.decodeIfPresent(Int.self, forKey: .beginShapeIndex) ?? 0
        endShapeIndex = try c.decodeIfPresent(Int.self, forKey: .endShapeIndex) ?? 0
    }
}

/// Comfort mix categories, in the design order (`velix-tokens.json` → `mixOrder`).
enum MixCategory: String, CaseIterable, Codable, Sendable {
    case protected, painted, quiet, mixed, cobbles, unpaved
}

/// Hazard types in the pack sidecar (pipeline/stages/hazards.py), named as the glyphs.
enum HazardType: String, CaseIterable, Codable, Sendable {
    case tram, along, cobbles, steps, gap, dismount, lane, door, descent, climb

    /// Shown to the rider (map tubes and markers, the riding card, voice, haptics, the lock screen, "On your route").
    /// Tram rails aren't (Filippo, 29 Oct 2026: riders see them, and they were too many and too loud); they still
    /// steer the route ("Never along tram rails") and explain it ("avoids rails along …", "Skipping …: rails").
    var shown: Bool { self != .tram && self != .along }

    /// HazardRow / hazard card title (design/tools/p5gen.js `HZ`).
    var title: String {
        switch self {
        case .tram: "Tram rails crossing"
        case .along: "Rails along lane"
        case .cobbles: "Cobbles"
        case .steps: "Steps"
        case .gap: "Narrow gap"
        case .dismount: "Dismount"
        case .lane: "Lane ends"
        case .door: "Door zone"
        case .descent: "Steep descent"
        case .climb: "Steep climb"
        }
    }
}

struct HazardRecord: Equatable, Sendable {
    let id: Int64
    let type: HazardType
    let isLine: Bool
    let lat: Double
    let lon: Double
    let lengthM: Double
    let polyline6: String
    let detail: String
    let osm: String
    let heading: Double?

    var wayId: Int64? { osm.hasPrefix("w") ? Int64(osm.dropFirst()) : nil }
}

/// A hazard found on a route, with where it starts along the route.
struct SignalStop: Equatable, Sendable {
    let distanceAlong: Double
    let location: LatLon
}

struct RouteHazard: Equatable, Sendable {
    let type: HazardType
    let distanceAlong: Double
    let lengthM: Double
    let street: String?
    let detail: String
    let osm: String
}

/// What a route is made of. Computed by ``RouteAnalyzer`` from Valhalla edges + the hazard sidecar.
struct RouteAnalysis: Equatable, Sendable {
    var shape: [LatLon] = []
    var edges: [RouteEdge] = []
    var lengthM: Double = 0
    var mix: [MixCategory: Double] = [:]
    var hazards: [RouteHazard] = []
    var climbM: Double = 0
    var maxGrade: Int = 0
    var profile = ElevationProfile(edges: [])
    /// Metres per way id, to find stretches one route uses and the other doesn't.
    var metersByWay: [Int64: Double] = [:]
    /// Metres on busy roads (mixed traffic, tertiary and up) by street name.
    var busyByName: [String: Double] = [:]
    /// Longest continuous stretch in mixed traffic.
    var longestMixedRun: Double = 0
    /// Path edges that are not lit (or not tagged lit), and roads tagged unlit.
    var unlitPaths: Int = 0
    var unlitMeters: Double = 0
    var unlitEdges: [RouteEdge] = []
    /// Edges on short pedestrian passages (walk stretches; ridden slowly).
    var walkEdges: [RouteEdge] = []
    /// Junctions with traffic lights, in order along the route (signal nodes within 40 m count once).
    var signalStops: [SignalStop] = []
    /// Metres on paths (cycleway, path, footway, track) — park paths for the scenic types.
    var pathMeters: Double = 0

    func meters(_ category: MixCategory) -> Double { mix[category] ?? 0 }
    func hazardMeters(_ type: HazardType) -> Double {
        hazards.filter { $0.type == type }.reduce(0) { $0 + max($1.lengthM, 1) }
    }
    func hazardCount(_ type: HazardType) -> Int { hazards.filter { $0.type == type }.count }
    var laneShare: Double {
        lengthM > 0 ? (meters(.protected) + meters(.painted)) / lengthM : 0
    }
}
