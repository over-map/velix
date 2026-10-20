import Foundation

/// When to ask for a new route while riding (M7; M1 finding 1: 9–10 reroutes 7–10 s apart while Filippo rode his own
/// way on purpose; finding 3: one reroute failed silently). Pure and clock-driven, so it is tested without a ride.
///
/// - Off route means completely off it for `offRouteFixes` fixes in a row or for `offRouteSeconds`.
/// - Reroutes are at least `wait` apart: `baseWait` at first, doubled (up to `maxWait`) each time the rider leaves a
///   new route again within `leftAgainWithin`, back to `baseWait` after `calmAfter` on the route.
/// - A failed reroute keeps the current route and is retried after the wait, also standing still.
struct ReroutePolicy: Sendable {
    static let offRouteFixes = 3
    static let offRouteSeconds: TimeInterval = 8
    static let baseWait: TimeInterval = 15
    static let maxWait: TimeInterval = 120
    static let leftAgainWithin: TimeInterval = 30
    static let calmAfter: TimeInterval = 120
    /// Failures in a row before the screen says it can't find a route (it keeps trying).
    static let failuresShown = 3

    private(set) var offRouteSince: Date?
    private(set) var offRouteCount = 0
    private(set) var wait: TimeInterval = Self.baseWait
    private(set) var lastRequest: Date?
    private(set) var lastNewRoute: Date?
    private(set) var onRouteSince: Date?
    private(set) var failures = 0
    private(set) var inFlight = false
    /// The rider left the last new route within `leftAgainWithin`.
    private(set) var leftQuickly = false
    private var latest = Date.distantPast

    /// The rider is visibly off the route (the screen shows "Rerouting").
    var isOffRoute: Bool {
        offRouteCount >= Self.offRouteFixes || (offRouteSince.map { latest.timeIntervalSince($0) >= Self.offRouteSeconds } ?? false)
    }
    var cannotFindRoute: Bool { failures >= Self.failuresShown }

    /// Each fix: completely off the route, or not.
    mutating func fix(offRoute: Bool, at time: Date) {
        latest = time
        if offRoute {
            if offRouteSince == nil {
                offRouteSince = time
                leftQuickly = lastNewRoute.map { time.timeIntervalSince($0) <= Self.leftAgainWithin } ?? false
            }
            offRouteCount += 1
            onRouteSince = nil
        } else {
            offRouteSince = nil
            offRouteCount = 0
            if onRouteSince == nil { onRouteSince = time }
            if let since = onRouteSince, time.timeIntervalSince(since) >= Self.calmAfter { wait = Self.baseWait }
        }
    }

    /// Whether to ask for a new route now.
    func shouldReroute(at time: Date) -> Bool {
        guard !inFlight, isOffRoute else { return false }
        guard let lastRequest else { return true }
        return time.timeIntervalSince(lastRequest) >= wait
    }

    mutating func requested(at time: Date) {
        inFlight = true
        lastRequest = time
        if leftQuickly { wait = min(wait * 2, Self.maxWait) }
        leftQuickly = false
    }

    /// A new route was accepted.
    mutating func succeeded(at time: Date) {
        inFlight = false
        failures = 0
        lastNewRoute = time
        offRouteSince = nil
        offRouteCount = 0
    }

    /// No route came back: keep the current one.
    mutating func failed(at time: Date) {
        inFlight = false
        failures += 1
    }
}
