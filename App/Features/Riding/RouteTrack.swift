import Foundation

/// Where the rider is along the route being ridden, and what is left of it (P5: "only the route ahead is drawn").
/// Ferrostar's remaining-polyline helper is unfinished in 0.57, so the app projects each fix on its own shape.
struct RouteTrack: Equatable, Sendable {
    let shape: [LatLon]
    let along: [Double]
    var length: Double { along.last ?? 0 }
    /// Metres from the start to the rider (never goes back by more than `backtrack`).
    private(set) var position: Double = 0
    /// How far the last fix was from the line.
    private(set) var offset: Double = .infinity

    /// How far behind the last position a fix may be placed (a U-turn on the route, a GPS wobble).
    static let backtrack = 40.0
    /// Fixes farther from the line than this don't move the position (off route).
    static let maxOffset = 60.0

    init(shape: [LatLon]) {
        self.shape = shape
        self.along = RouteAnalyzer.cumulative(shape)
    }

    /// Moves the position to the projection of `fix`, searching forward from the last position.
    mutating func update(_ fix: LatLon) {
        guard shape.count > 1 else { return }
        var best: (d: Double, along: Double)?
        for i in 0 ..< shape.count - 1 {
            guard along[i + 1] >= position - Self.backtrack else { continue }
            let r = Geo.distance(from: fix, toSegment: shape[i], shape[i + 1])
            let a = along[i] + r.t * (along[i + 1] - along[i])
            guard a >= position - Self.backtrack else { continue }
            // Prefer the nearest segment; on a tie (a loop), the one closer to the last position.
            if r.meters < (best?.d ?? .infinity) - 0.5 { best = (r.meters, a) }
        }
        offset = best?.d ?? .infinity
        if let best, best.d <= Self.maxOffset { position = best.along }
    }

    /// The point at a distance along the route.
    func point(at d: Double) -> LatLon { RuleChecker.point(at: max(0, min(d, length)), on: shape, along: along) }

    /// The route from the rider to the end (what the map draws while riding).
    var ahead: [LatLon] {
        guard shape.count > 1 else { return shape }
        let i = along.firstIndex { $0 > position } ?? shape.count - 1
        return [point(at: position)] + shape[i...]
    }

    var remaining: Double { max(0, length - position) }

    /// Where to draw the rider: on the line while near it (Ferrostar's snapping threshold), else the fix itself.
    func rider(_ fix: LatLon) -> LatLon { offset <= Self.snapWithin ? point(at: position) : fix }
    static let snapWithin = 30.0
}
