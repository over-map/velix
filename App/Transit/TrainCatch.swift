import Foundation

/// Stage 1 of a bike + transit ride: will the rider make the train (P6 S5a–S5c)? Pure and clock-driven.
///
/// "Late" is the rider's ETA against the scheduled departure (BUILD_PLAN: no live feed). The ETA is the route's
/// remaining time scaled by the rider's own pace, so a slow rider is late before the route says so.
/// - Late on Best: switch to the leg's Fastest, when that still makes it (S5b).
/// - Late on Fastest too (or no Fastest saves it): the next train of the same pair (S5c).
/// - On Fastest with time to spare again: back to Best (HANDOFF: "back to Best when time allows").
/// Each decision waits for 2 fixes in a row and comes at most every 30 s, so one bad fix or a long light doesn't flip it.
struct TrainCatch: Sendable {
    enum Action: Equatable, Sendable { case none, switchToFastest, nextTrain, backToBest }

    static let fixesToAct = 2
    static let between: TimeInterval = 30
    /// Back to Best once Best would leave this much spare.
    static let backToBestSpare: TimeInterval = 5 * 60
    /// The rider's pace is trusted after this much riding; until then the route's own estimate counts.
    static let paceAfter: TimeInterval = 60
    /// Pace never makes the ETA more optimistic than the route, nor more than twice as slow.
    static let paceRange = 1.0 ... 2.0

    private(set) var onFastest = false
    private var lateFixes = 0
    private var spareFixes = 0
    private var lastAction: Date?

    /// Seconds to spare at the station: departure − (now + ETA + boarding). Negative: the train is gone by then.
    static func spare(departs: Date, now: Date, eta: TimeInterval, boarding: TimeInterval) -> TimeInterval {
        departs.timeIntervalSince(now) - eta - boarding
    }

    /// The rider's ETA: the route's remaining time × pace (how much longer the rider has taken than the route said,
    /// over the ride so far), within ``paceRange``.
    static func eta(remaining: TimeInterval, riddenFor: TimeInterval, plannedForRidden: TimeInterval) -> TimeInterval {
        guard riddenFor >= paceAfter, plannedForRidden > 0 else { return remaining }
        let pace = min(max(riddenFor / plannedForRidden, paceRange.lowerBound), paceRange.upperBound)
        return remaining * pace
    }

    /// One fix. `eta` is the rider's on the current route; `bestETA` and `fastestETA` from here, when planned
    /// (nil: not known yet).
    mutating func evaluate(now: Date, departs: Date, boarding: TimeInterval, eta: TimeInterval,
                           bestETA: TimeInterval?, fastestETA: TimeInterval?) -> Action {
        let spare = Self.spare(departs: departs, now: now, eta: eta, boarding: boarding)
        if spare < 0 { lateFixes += 1 } else { lateFixes = 0 }
        if onFastest, let b = bestETA, Self.spare(departs: departs, now: now, eta: b, boarding: boarding) >= Self.backToBestSpare {
            spareFixes += 1
        } else {
            spareFixes = 0
        }
        guard lastAction.map({ now.timeIntervalSince($0) >= Self.between }) ?? true else { return .none }

        if lateFixes >= Self.fixesToAct {
            let action: Action
            if !onFastest, let f = fastestETA, Self.spare(departs: departs, now: now, eta: f, boarding: boarding) >= 0 {
                action = .switchToFastest
                onFastest = true
            } else {
                action = .nextTrain     // the route stays; back to Best follows once there is time (S5c)
            }
            act(now)
            return action
        }
        if spareFixes >= Self.fixesToAct {
            onFastest = false
            act(now)
            return .backToBest
        }
        return .none
    }

    private mutating func act(_ now: Date) {
        lastAction = now
        lateFixes = 0
        spareFixes = 0
    }
}
