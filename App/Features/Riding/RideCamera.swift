import Foundation

/// The riding camera (P5 S4a–S4d, S4j): three follow views, the overview and the pause after a pan. Pure: taps,
/// pans and the clock in, the camera out (``tick(at:)`` brings follow back after 10 s).
struct RideCamera: Equatable, Sendable {
    typealias View = MapControlStack.View3D

    private(set) var view: View = .twoD
    /// Showing the rest of the trip (S4d) since this time.
    private(set) var overviewSince: Date?
    /// The rider moved the map (S4j) at this time.
    private(set) var pannedAt: Date?

    /// Overview and a pan both go back to follow after this long (P5 S4d, S4j).
    static let resumeAfter: TimeInterval = 10

    var isOverview: Bool { overviewSince != nil }
    var isPanned: Bool { pannedAt != nil }
    /// The camera tracks the rider (not overview, not panned).
    var isFollowing: Bool { !isOverview && !isPanned }
    /// Heading up with the P3 chevron at the anchor (2D and 3D follow); North up shows the dot and cone, rotating.
    var showsChevron: Bool { isFollowing && view != .north }
    /// While following, the screen draws the rider at the anchor (smooth: the camera glides, the marker stays put);
    /// panned or in the overview, the map puck does.
    var drawsRider: Bool { isFollowing }

    /// View control: 2D → 3D → North (P5 "Each control cycles on tap"); it also ends an overview or a pan.
    mutating func cycleView() {
        if isFollowing { view = Self.next(view) }
        overviewSince = nil
        pannedAt = nil
    }

    /// Overview control: on, or back to the last view on a second tap.
    mutating func toggleOverview(at now: Date) {
        overviewSince = isOverview ? nil : now
        pannedAt = nil
    }

    mutating func userPanned(at now: Date) {
        pannedAt = now
        overviewSince = nil
    }

    mutating func recenter() {
        pannedAt = nil
        overviewSince = nil
    }

    /// Back to follow once the overview or the pan is 10 s old. True when something changed.
    @discardableResult
    mutating func tick(at now: Date) -> Bool {
        var changed = false
        if let t = overviewSince, now.timeIntervalSince(t) >= Self.resumeAfter { overviewSince = nil; changed = true }
        if let t = pannedAt, now.timeIntervalSince(t) >= Self.resumeAfter { pannedAt = nil; changed = true }
        return changed
    }

    /// The follow camera at the rider (design/p4/maps.js r2d, r3d, rNorth; 3D from tokens `mapRules.follow3D`).
    func follow(at rider: LatLon, course: Double) -> MapCamera {
        switch view {
        case .twoD: MapCamera(center: rider, zoom: 16.6, bearing: course, anchor: 0.62)
        case .threeD: MapCamera(center: rider, zoom: 17, pitch: 50, bearing: course, anchor: 0.72)
        case .north: MapCamera(center: rider, zoom: 16.2, anchor: 0.55)
        }
    }

    private static func next(_ v: View) -> View {
        switch v { case .twoD: .threeD; case .threeD: .north; case .north: .twoD }
    }
}
