import ActivityKit
import Combine
import CoreLocation
@preconcurrency import FerrostarCore
@preconcurrency import FerrostarCoreFFI
import Foundation
import Observation
import UIKit

/// A ride on the route chosen in S3 (tap 2 of the commute). Ferrostar follows the planned route as is and advances
/// the steps; the app decides when to reroute (``ReroutePolicy``), plans reroutes with the ride's rules
/// (``PlannedRouteProvider``), tracks the next hazard and its alert, ends the ride at the door and keeps the Live
/// Activity and the ride log up to date. The P5 screen (M7b) reads everything from here.
@MainActor
@Observable
final class RideSession {
    enum Failure: Error { case badRoute }

    let destination: Place
    let rules: RuleSet
    let choice: RideChoice

    private(set) var navigationState: NavigationState?
    private(set) var option: RouteOption
    private(set) var track: RouteTrack
    private(set) var nextHazard: HazardTracker.Next?
    private(set) var gps: GPSQuality = .good
    /// Roads Best leaves out (S4f: tagged near the rider).
    private(set) var avoided: [AvoidedRoad]
    /// The last accepted fix, and the course to point the map along (GPS course when moving, else the route's).
    private(set) var here: LatLon?
    private(set) var course: Double = 0
    private(set) var policy = ReroutePolicy()
    private(set) var ended = false
    /// Set when the ride ended at the destination (S6 opens), not by End.
    private(set) var arrived = false
    var onEnd: (RideSession) -> Void = { _ in }

    let voice = RideVoice()
    private let haptics = RideHaptics()
    private var tracker: HazardTracker
    private let location = RideLocationProvider()
    private let coordinator = RideCoordinator()
    private let provider: PlannedRouteProvider
    private(set) var core: FerrostarCore?
    private(set) var log: RideLog?
    /// The ride as GPX, written when it ends (S6 Share GPX).
    private(set) var gpx: URL?
    private var cancellables = Set<AnyCancellable>()
    private var activity: Activity<RideActivityAttributes>?
    private var lastActivityPosition = -Double.infinity
    private var lastActivityKey = ""
    /// Wakes already sent (a hazard or a turn lights the screen once).
    private var alertedWakes = Set<String>()

    /// Within this of the destination the screen shows "Arriving" (S4i).
    static let arrivingWithin = 150.0
    /// The ride ends by itself this close to the destination, after most of the route (Ferrostar's arrival step
    /// alone can miss the door when the last step is short).
    nonisolated static let arrivedWithin = 30.0
    nonisolated static let arrivedAfterShare = 0.8
    /// The Live Activity updates every this many metres (P5 L1 "Updates every 10 m"), or at once on a change.
    static let activityStep = 10.0

    init(destination: Place, option: RouteOption, avoided: [AvoidedRoad] = [], rules: RuleSet, choice: RideChoice,
         planner: RoutePlanner?) {
        self.destination = destination
        self.option = option
        self.avoided = choice == .best ? avoided : []
        self.rules = rules
        self.choice = choice
        track = RouteTrack(shape: option.analysis.shape)
        tracker = HazardTracker(hazards: option.analysis.hazards)
        if let planner {
            provider = PlannedRouteProvider(planner: planner, rules: rules, choice: choice)
        } else {
            provider = PlannedRouteProvider(choice: choice) { _, _, _ in .noRoute }
        }
    }

    /// The planned option as a Ferrostar route (Valhalla's OSRM response, polyline6).
    nonisolated static func route(from option: RouteOption) throws -> Route {
        let parser = createOsrmResponseParser(polylinePrecision: 6)
        guard let route = try parser.parseResponse(response: Data(option.osrmJSON.utf8)).first else { throw Failure.badRoute }
        return route
    }

    static let navigationConfig = SwiftNavigationControllerConfig(
        waypointAdvance: .waypointWithinRange(30),
        stepAdvanceCondition: stepAdvanceDistanceEntryAndExit(distanceToEndOfStep: 20, distanceAfterEndOfStep: 5, minimumHorizontalAccuracy: 25),
        arrivalStepAdvanceCondition: stepAdvanceDistanceToEndOfStep(distance: 10, minimumHorizontalAccuracy: 25),
        routeDeviationTracking: .staticThreshold(minimumHorizontalAccuracy: 25, maxAcceptableDeviation: 30),
        snappedLocationCourseFiltering: .snapToRoute
    )

    func start() throws {
        let route = try Self.route(from: option)
        let core = FerrostarCore(customRouteProvider: provider, locationProvider: location,
                                 navigationControllerConfig: Self.navigationConfig, spokenInstructionObserver: voice.turns)
        // The app's policy decides when to reroute: Ferrostar asks on every off-route fix, standing still included.
        core.minimumTimeBeforeRecalculation = 1
        core.minimumMovementBeforeRecalculation = 0
        coordinator.session = self
        core.delegate = coordinator
        provider.onFailure = { [weak self] in Task { @MainActor in self?.rerouteFailed() } }
        let log = RideLog()
        log.event(.start(destination: destination.name, meters: option.meters))
        self.log = log
        location.onFix = { [weak self] fix, quality in
            MainActor.assumeIsolated { self?.fix(fix, quality: quality) }
        }
        core.$state.receive(on: DispatchQueue.main).sink { [weak self] state in
            self?.stateChanged(state)
        }.store(in: &cancellables)
        voice.start()
        #if DEBUG
        if RideLocationProvider.simulates { location.simulate(track.shape) }
        #endif
        location.startUpdating()
        try core.startNavigation(route: route)
        self.core = core
        UIApplication.shared.isIdleTimerDisabled = true
        startActivity()
    }

    /// End (the End button, or at the door).
    func end(arrived: Bool = false) {
        guard !ended else { return }
        ended = true
        self.arrived = arrived
        log?.event(.end(arrived ? "arrived" : "ended"))
        log?.close()
        gpx = try? log?.gpx(name: "Velix · \(destination.name)")
        core?.stopNavigation()
        core = nil
        cancellables.removeAll()
        location.stopUpdating()
        voice.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        activity = nil
        Task {
            for a in Activity<RideActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
        }
        onEnd(self)
    }

    // MARK: Progress, hazards, arrival

    var isRerouting: Bool { policy.isOffRoute || navigationState?.isCalculatingNewRoute == true }
    var isArriving: Bool { track.remaining <= Self.arrivingWithin }
    var stats: RideStats { log?.stats ?? RideStats() }

    private func fix(_ fix: CLLocation, quality: GPSQuality) {
        if quality != gps {
            gps = quality
            log?.event(.gps(quality == .weak ? "weak" : "good"))
        }
        log?.fix(fix)
        let here = LatLon(lat: fix.coordinate.latitude, lon: fix.coordinate.longitude)
        track.update(here)
        self.here = here
        course = Self.course(fix: fix, track: track)
        nextHazard = tracker.next(at: track.position, gps: gps)
        if let h = tracker.alert(at: track.position, gps: gps) {
            haptics.hazard()
            voice.speakHazard(HazardPrompt.voice(h))
            log?.event(.hazard(type: h.type.rawValue, distance: max(0, h.distanceAlong - track.position), at: here))
        }
        if Self.hasArrived(remaining: track.remaining, position: track.position, length: track.length,
                           toDestination: Geo.distance(here, destination.location)) {
            end(arrived: true)
            return
        }
        updateActivity()
    }

    /// Heading up: the GPS course while moving (≥ 2 m/s, like ``LocationService/travelHeading``), else the route's
    /// direction at the rider, so the map doesn't spin at a light.
    static func course(fix: CLLocation, track: RouteTrack) -> Double {
        if fix.speed >= 2, fix.course >= 0 { return fix.course }
        return Geo.bearing(track.point(at: track.position), track.point(at: track.position + 15))
    }

    /// What the S4 screen shows now.
    func screen(chevron: Bool, now: Date = Date()) -> RideScreenState {
        RideScreenState(.init(turn: RideTurn(navigationState), option: option, track: track, next: nextHazard, gps: gps,
                              rerouting: isRerouting, cannotFindRoute: policy.cannotFindRoute, arriving: isArriving,
                              destination: destination, avoided: avoided, rider: here.map { track.rider($0) },
                              heading: course, chevron: chevron, now: now))
    }

    /// At the door: close to the destination after most of the route, or at the end of the route line.
    nonisolated static func hasArrived(remaining: Double, position: Double, length: Double, toDestination: Double) -> Bool {
        guard length > 0 else { return toDestination <= arrivedWithin }
        return position >= arrivedAfterShare * length && (toDestination <= arrivedWithin || remaining <= 5)
    }

    private func stateChanged(_ state: NavigationState?) {
        navigationState = state
        if case let .navigating(_, _, _, _, _, _, _, deviation, _, _, _) = state?.tripState {
            let off: Bool = if case .deviation(.completelyOffRoute) = deviation { true } else { false }
            policy.fix(offRoute: off, at: Date())
        }
        if case .complete = state?.tripState { end(arrived: true) }
    }

    // MARK: Rerouting (``RideCoordinator``)

    /// Ferrostar asks whether to reroute (on the main thread, every off-route fix).
    func rerouteRequested() -> Bool {
        let now = Date()
        guard policy.shouldReroute(at: now) else { return false }
        policy.requested(at: now)
        log?.event(.reroute("requested"))
        return true
    }

    /// New routes from ``PlannedRouteProvider``: ride the first, with the option's analysis for hazards and the map.
    func rerouted(_ routes: [Route]) {
        guard let route = routes.first, let core, let planned = provider.lastOption else {
            rerouteFailed()
            return
        }
        do {
            try core.startNavigation(route: route)
            option = planned
            avoided = provider.lastAvoided
            track = RouteTrack(shape: planned.analysis.shape)
            if let here { track.update(here) }
            tracker = HazardTracker(hazards: planned.analysis.hazards, alerted: tracker.alerted)
            policy.succeeded(at: Date())
            log?.event(.reroute("accepted"))
            lastActivityKey = ""
            updateActivity()
        } catch {
            rerouteFailed()
        }
    }

    private func rerouteFailed() {
        policy.failed(at: Date())
        log?.event(.reroute("failed"))
    }

    // MARK: Live Activity (P5 L1–L2, D1–D5; M7c redesigns it)

    private func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = Self.content(nil, destination: destination, fallbackMeters: option.meters)
        activity = try? Activity.request(attributes: RideActivityAttributes(), content: .init(state: state, staleDate: nil))
    }

    /// Every `activityStep` metres, or at once when the maneuver, the street or the hazard changes.
    private func updateActivity() {
        guard activity != nil, let nav = navigationState else { return }
        var state = Self.content(nav, destination: destination, fallbackMeters: 0)
        if let n = nextHazard {
            Self.addHazard(n, to: &state)
        }
        // With the phone locked the screen goes dark after a few seconds: light it up for a close hazard and a turn
        // coming (the alert carries a silent sound; the voice and the haptic already speak).
        let wake = UIApplication.shared.applicationState == .active ? nil
            : Self.wake(state, hazard: nextHazard, toTurn: nav.currentProgress?.distanceToNextManeuver, step: nav.remainingSteps?.count)
        let alert = wake.flatMap { alertedWakes.contains($0.key) ? nil : $0 }
        if let alert { alertedWakes.insert(alert.key) }
        let key = "\(state.maneuver)|\(state.street)|\(state.hazard?.title ?? "")|\(state.nextHazard?.glyph.rawValue ?? "")"
        guard alert != nil || key != lastActivityKey || abs(track.position - lastActivityPosition) >= Self.activityStep else { return }
        lastActivityKey = key
        lastActivityPosition = track.position
        let config = alert.map {
            AlertConfiguration(title: LocalizedStringResource(stringLiteral: $0.title), body: LocalizedStringResource(stringLiteral: $0.body),
                               sound: .named(Self.silentSound))
        }
        Task {
            for a in Activity<RideActivityAttributes>.activities {
                await a.update(.init(state: state, staleDate: nil), alertConfiguration: config)
            }
        }
    }

    /// A reason to light up the locked screen, once each.
    struct Wake: Equatable {
        var key: String
        var title: String
        var body: String
    }

    static let silentSound = "velix-silent.caf"
    /// A turn wakes the screen this far before it (P8: turns re-announced at 100 m).
    static let wakeBeforeTurn = 100.0

    /// A hazard under 50 m (P5 L2), else a turn within 100 m; not "straight on".
    static func wake(_ state: RideActivityAttributes.ContentState, hazard: HazardTracker.Next?, toTurn: Double?, step: Int?) -> Wake? {
        if let h = state.hazard, let n = hazard {
            return Wake(key: "hazard-\(HazardTracker.key(n.hazard))", title: h.title, body: "\(h.advice) · \(h.distance)")
        }
        guard let d = toTurn, d <= wakeBeforeTurn, state.maneuver != .straight, let step else { return nil }
        let title = state.maneuver == .arrive ? "Arriving" : "\(state.maneuver.spoken) in \(state.distance)"
        return Wake(key: "turn-\(step)-\(state.street)", title: title, body: state.street)
    }

    /// Close: the hazard leads (L2, D2, D5). Further: the footer line (L1, D4 "Tram rails in 160 m").
    static func addHazard(_ n: HazardTracker.Next, to state: inout RideActivityAttributes.ContentState) {
        let title = HazardPrompt.title(n.hazard), distance = Self.distance(n.distance)
        if n.approaching {
            state.hazard = .init(glyph: n.hazard.type.glyph, title: title, advice: HazardPrompt.short(n.hazard),
                                 longAdvice: HazardPrompt.advice(n.hazard), distance: distance)
        }
        state.nextHazard = .init(glyph: n.hazard.type.glyph, text: "\(title) in \(distance)")
    }

    static func content(_ nav: NavigationState?, destination: Place, fallbackMeters: Double) -> RideActivityAttributes.ContentState {
        let progress = nav?.currentProgress
        let instruction = nav?.currentVisualInstruction?.primaryContent
        let remaining = progress?.durationRemaining ?? fallbackMeters / 4.2
        let arrival = Date().addingTimeInterval(remaining)
        let clock = arrival.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        let maneuver = Maneuver(type: instruction?.maneuverType, modifier: instruction?.maneuverModifier)
        // An unnamed way reads as the turn, like the riding banner.
        let street = instruction.map { RideTurn.street($0.text) ?? maneuver.spoken } ?? destination.name
        return .init(maneuver: maneuver,
                     distance: distance(progress?.distanceToNextManeuver ?? fallbackMeters),
                     street: street, arrival: clock,
                     minutesLeft: "\(max(1, Int((remaining / 60).rounded()))) min",
                     distanceLeft: Format.km(progress?.distanceRemaining ?? fallbackMeters))
    }

    /// "200 m", "1.2 km" (rounded like the P5 ManeuverBanner).
    nonisolated static func distance(_ m: Double) -> String {
        m >= 1000 ? Format.km(m) : "\(Int((m / 10).rounded()) * 10) m"
    }
}

extension Maneuver {
    init(type: ManeuverType?, modifier: ManeuverModifier?) {
        switch type {
        case .arrive?: self = .arrive
        case .merge?: self = .merge
        case .roundabout?, .rotary?, .roundaboutTurn?, .exitRoundabout?, .exitRotary?: self = .roundabout
        default:
            switch modifier {
            case .uTurn?: self = .uTurn
            case .sharpRight?: self = .sharpRight
            case .right?: self = .right
            case .slightRight?: self = .slightRight
            case .slightLeft?: self = .slightLeft
            case .left?: self = .left
            case .sharpLeft?: self = .sharpLeft
            default: self = .straight
            }
        }
    }
}
