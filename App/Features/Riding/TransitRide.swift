import CoreLocation
import Foundation
import Observation

/// A bike + transit ride (P6 S5): ride to the station, one train or metro run, ride on. One ``RideSession`` carries
/// the whole trip (one log, one Live Activity, one summary); this coordinator moves it through the stages, checks
/// the train in stage 1 (``TrainCatch``: late → Fastest, missed → the next run, time again → Best) and times stage 2
/// from the timetable (the 2-minute buzz, the stop).
@MainActor
@Observable
final class TransitRide {
    enum Stage: Int, Sendable { case toStation = 1, onTrain = 2, ride = 3 }

    let session: RideSession
    let destination: Place
    private(set) var plan: TransitPlan
    private(set) var stage: Stage = .toStation
    /// Late / missed, shown in the hazard card's place for 8 s (P6), and in the island until the next change.
    private(set) var notice: (kind: TransitNotice.Kind, title: String, message: String, short: String, at: Date)?
    static let noticeFor: TimeInterval = 8

    private let planner: TransitPlanner?
    private var catchPolicy = TrainCatch()
    /// Best and Fastest from the rider to the station, planned when the spare time runs low (re-planned each minute).
    private var routes: (best: RouteOption, fastest: RouteOption?, at: Date)?
    private var planning = false
    private var buzzed = false
    private var clock: Task<Void, Never>?

    /// The spare time under which Best and Fastest from here are planned (so a decision has both at hand).
    static let planBelow: TimeInterval = 4 * 60
    static let replanAfter: TimeInterval = 60
    /// The stop-coming buzz (P6 S5d "Velix buzzes 2 min before").
    static let buzzBefore: TimeInterval = 2 * 60

    init(plan: TransitPlan, destination: Place, rules: RuleSet, planner: TransitPlanner?) {
        self.plan = plan
        self.destination = destination
        self.planner = planner
        let station = plan.departure.board
        session = RideSession(destination: Place(id: "station-\(station.id)", name: TransitCopy.short(station), subtitle: destination.name,
                                                 kind: .station, lat: station.location.lat, lon: station.location.lon),
                              option: plan.rideIn, rules: rules, choice: .best, planner: planner?.planner)
        session.onLegEnd = { [weak self] in self?.boarded() }
        session.onFixed = { [weak self] fix in self?.fixed(fix) }
        session.decorateActivity = { [weak self] state in self?.decorate(&state) }
    }

    func start() throws {
        try session.start()
        // The train stage has no route to follow: a clock moves it on (and keeps the countdown fresh).
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1 / AppClock.scale))
                self?.tick()
            }
        }
    }

    func end() {
        clock?.cancel()
        session.end()
    }

    // MARK: Stage 1: will the rider make the train?

    private func fixed(_ fix: CLLocation) {
        guard stage == .toStation else { return }
        let now = AppClock.now
        let eta = riderETA(now: now)
        let mode = plan.departure.route.mode
        let spare = TrainCatch.spare(departs: plan.departure.departs, now: now, eta: eta, boarding: DirectPlanner.boarding(mode))
        // Best and Fastest from here: when the spare time runs low, and while on Fastest (to know when Best fits again);
        // each minute, so they stay from where the rider is.
        if spare < Self.planBelow || catchPolicy.onFastest, !planning,
           routes.map({ now.timeIntervalSince($0.at) >= Self.replanAfter }) ?? true {
            planFromHere(fix)
        }
        // Late, but Best and Fastest from here aren't known yet: wait for them rather than give up on the train.
        guard spare >= 0 || routes != nil else { return }
        let pace = paceFactor(now: now)
        let action = catchPolicy.evaluate(now: now, departs: plan.departure.departs, boarding: DirectPlanner.boarding(mode), eta: eta,
                                          bestETA: routes.map { $0.best.seconds * pace },
                                          fastestETA: routes?.fastest.map { $0.seconds * pace })
        switch action {
        case .none: break
        case .switchToFastest:
            guard let r = routes, let fastest = r.fastest else { return }
            session.switchRoute(to: fastest, choice: .fastest)
            session.log?.event(.transit("late: fastest to catch \(TransitCopy.clock(plan.departure.departs))"))
            let copy = TransitCopy.late(plan.departure, cost: TransitCopy.lateCost(best: r.best.analysis, fastest: fastest.analysis))
            show(.late, copy.title, copy.message, short: copy.short, voice: TransitCopy.lateVoice)
        case .nextTrain:
            nextTrain()
        case .backToBest:
            if let best = routes?.best { session.switchRoute(to: best, choice: .best) }
            session.log?.event(.transit("back to best"))
        }
    }

    /// Ferrostar's remaining time on the leg × the rider's pace so far.
    private func riderETA(now: Date) -> TimeInterval {
        let remaining = session.navigationState?.currentProgress?.durationRemaining
            ?? session.option.seconds * session.track.remaining / max(1, session.track.length)
        return TrainCatch.eta(remaining: remaining, riddenFor: now.timeIntervalSince(session.legStarted),
                              plannedForRidden: plannedForRidden)
    }

    private func paceFactor(now: Date) -> Double {
        let ridden = now.timeIntervalSince(session.legStarted)
        guard ridden >= TrainCatch.paceAfter, plannedForRidden > 0 else { return 1 }
        return min(max(ridden / plannedForRidden, TrainCatch.paceRange.lowerBound), TrainCatch.paceRange.upperBound)
    }

    /// The route's time for the stretch ridden so far.
    private var plannedForRidden: TimeInterval {
        session.option.seconds * session.track.position / max(1, session.track.length)
    }

    private func planFromHere(_ fix: CLLocation) {
        guard let planner else { return }
        planning = true
        let from = LatLon(lat: fix.coordinate.latitude, lon: fix.coordinate.longitude)
        let to = plan.departure.board.location
        let rules = session.rules
        let heading = fix.speed >= 2 && fix.course >= 0 ? fix.course : nil
        Task {
            let result = try? await planner.planner.plan(from: from, to: to, heading: heading, rules: rules)
            planning = false
            switch result {
            case let .options(o)?: routes = (o.best, o.fastest, AppClock.now)
            case let .noRouteMeetsRules(_, _, closest?, _)?: routes = (closest, nil, AppClock.now)
            default: break
            }
        }
    }

    /// Missed: the next run of the same pair, still from this station, with its own stops (S5c).
    private func nextTrain() {
        guard let planner else { return }
        let old = plan.departure
        guard let d = DirectPlanner.later(planner.store, than: old, count: 1).first else { return }
        let next = TransitPlan(rideIn: plan.rideIn, departure: d, rule: planner.store.bikeRule(for: d), stops: planner.store.stopTimes(of: d),
                               rideOut: plan.rideOut, planned: plan.planned)
        plan = next
        session.log?.event(.transit("missed \(TransitCopy.clock(old.departs)): next \(TransitCopy.clock(d.departs))"))
        let copy = TransitCopy.missed(old, next: next)
        show(.missed, copy.title, copy.message, short: copy.message, voice: TransitCopy.missedVoice(next))
    }

    private func show(_ kind: TransitNotice.Kind, _ title: String, _ message: String, short: String, voice: String) {
        notice = (kind, title, message, short, AppClock.now)
        session.voice.speakHazard(voice)
        session.updateActivity()
    }

    // MARK: Stage 2: on the train

    private func boarded() {
        stage = .onTrain
        session.log?.event(.transit("at the station, train \(TransitCopy.clock(plan.departure.departs))"))
        notice = nil
        #if DEBUG
        if RideLocationProvider.simulates {
            session.simulateTrain(plan.stops.map(\.stop.location), departs: plan.departure.departs, arrives: plan.departure.arrives)
        }
        #endif
        session.updateActivity()
    }

    private func tick() {
        guard stage == .onTrain else { return }
        let now = AppClock.now
        if !buzzed, now >= plan.departure.arrives.addingTimeInterval(-Self.buzzBefore) {
            buzzed = true
            session.buzz(TransitCopy.getOffVoice(plan))
        }
        if now >= plan.departure.arrives { getOff() } else { session.updateActivity() }
    }

    // MARK: Stage 3: ride on

    /// At the stop (the timetable's arrival): the ride from the station to the destination, the session ends there.
    private func getOff() {
        stage = .ride
        session.log?.event(.transit("off at \(plan.departure.alight.name)"))
        session.onLegEnd = nil
        try? session.rideLeg(plan.rideOut, to: destination)
    }

    // MARK: Screen and Live Activity

    /// Stage 1 and 3 on top of the S4 screen (the strip, the station ETA, the notice); stage 2 is ``onTrain``.
    func decorate(_ s: inout RideScreenState, now: Date = AppClock.now) {
        s.stage = StageStrip(current: stage.rawValue, metro: plan.departure.route.mode == .metro)
        if stage == .toStation {
            s.eta = TransitCopy.stationEta(plan, now: now, eta: riderETA(now: now))
        }
        if let n = notice, now.timeIntervalSince(n.at) < Self.noticeFor {
            s.notice = .init(kind: n.kind, title: n.title, message: n.message)
        }
        if stage == .onTrain {
            s.onTrain = TransitCopy.onTrain(plan, now: now, destination: destination)
        }
        switch stage {
        case .toStation:
            // The leg being ridden is the session's (fade, rider); the train leg and the last ride come after it.
            let trip = MapRouteModel(transit: plan, endName: destination.name)
            s.map.legs = trip.legs
            s.map.rides = trip.rides
            s.map.end = trip.end
            s.map.endName = destination.name
        case .onTrain:
            // P6 S5d: the whole trip, the rider on the train leg.
            var trip = MapRouteModel(transit: plan, endName: destination.name)
            trip.puck = s.rider
            trip.heading = s.course
            s.map = trip
            s.ahead = plan.rideIn.analysis.shape + plan.stops.map(\.stop.location) + plan.rideOut.analysis.shape
        case .ride:
            break
        }
    }

    private func decorate(_ state: inout RideActivityAttributes.ContentState) {
        let now = AppClock.now
        if stage == .onTrain {
            state.train = TransitCopy.trainActivity(plan, now: now)
            state.arrival = TransitCopy.clock(plan.arrival)
            return
        }
        if stage == .toStation, case let .transit(_, _, _, spare, _) = TransitCopy.stationEta(plan, now: now, eta: riderETA(now: now)) {
            state.spare = spare
            if let n = notice, now.timeIntervalSince(n.at) < 60 { state.notice = .init(title: n.title, message: n.short) }
        }
    }
}
