import ActivityKit
import Combine
import CoreLocation
@preconcurrency import FerrostarCore
@preconcurrency import FerrostarCoreFFI
import Foundation
import MapLibreSwiftUI
import Observation
import UIKit

/// A ride on the route chosen in S3 (tap 2 of the commute): Ferrostar follows the planned route as is — no new
/// plan — reroutes with the same costing, and keeps the Live Activity up to date. The P5 riding UI comes in M7.
@MainActor
@Observable
final class RideSession {
    enum Failure: Error { case noEngine, badRoute }

    let destination: Place
    private(set) var navigationState: NavigationState?
    private(set) var ended = false
    var camera: MapViewCamera = .automotiveNavigation(zoom: 17)

    private(set) var core: FerrostarCore?
    private var cancellables = Set<AnyCancellable>()
    private var activity: Activity<RideActivityAttributes>?
    private let location = CoreLocationProvider(activityType: .otherNavigation, allowBackgroundLocationUpdates: true)
    var onEnd: () -> Void = {}

    init(destination: Place) { self.destination = destination }

    /// The planned option as a Ferrostar route (Valhalla's OSRM response, polyline6).
    static func route(from option: RouteOption) throws -> Route {
        let parser = createOsrmResponseParser(polylinePrecision: 6)
        guard let route = try parser.parseResponse(response: Data(option.osrmJSON.utf8)).first else { throw Failure.badRoute }
        return route
    }

    func start(option: RouteOption, engine: ValhallaOnDeviceProvider?) throws {
        guard let engine else { throw Failure.noEngine }
        engine.profile = option.costing   // reroutes keep the chosen route's costing
        let route = try Self.route(from: option)
        let config = SwiftNavigationControllerConfig(
            waypointAdvance: .waypointWithinRange(30),
            stepAdvanceCondition: stepAdvanceDistanceEntryAndExit(distanceToEndOfStep: 20, distanceAfterEndOfStep: 5, minimumHorizontalAccuracy: 25),
            arrivalStepAdvanceCondition: stepAdvanceDistanceToEndOfStep(distance: 10, minimumHorizontalAccuracy: 25),
            routeDeviationTracking: .staticThreshold(minimumHorizontalAccuracy: 25, maxAcceptableDeviation: 30),
            snappedLocationCourseFiltering: .snapToRoute
        )
        let core = FerrostarCore(customRouteProvider: engine, locationProvider: location, navigationControllerConfig: config)
        core.$state.receive(on: DispatchQueue.main).sink { [weak self] state in
            guard let self else { return }
            self.navigationState = state
            self.updateActivity(state)
            if case .complete = state?.tripState { self.end() }
        }.store(in: &cancellables)
        location.startUpdating()
        try core.startNavigation(route: route)
        self.core = core
        UIApplication.shared.isIdleTimerDisabled = true
        startActivity(route: route)
    }

    func end() {
        guard !ended else { return }
        ended = true
        core?.stopNavigation()
        core = nil
        cancellables.removeAll()
        location.stopUpdating()
        UIApplication.shared.isIdleTimerDisabled = false
        activity = nil
        Task {
            for a in Activity<RideActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
        }
        onEnd()
    }

    // MARK: Live Activity

    private func startActivity(route: Route) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = Self.content(nil, destination: destination, fallbackMeters: route.distance)
        activity = try? Activity.request(attributes: RideActivityAttributes(), content: .init(state: state, staleDate: nil))
    }

    private func updateActivity(_ nav: NavigationState?) {
        guard activity != nil, let nav else { return }
        let state = Self.content(nav, destination: destination, fallbackMeters: 0)
        Task {
            for a in Activity<RideActivityAttributes>.activities { await a.update(.init(state: state, staleDate: nil)) }
        }
    }

    static func content(_ nav: NavigationState?, destination: Place, fallbackMeters: Double) -> RideActivityAttributes.ContentState {
        let progress = nav?.currentProgress
        let instruction = nav?.currentVisualInstruction?.primaryContent
        let remaining = progress?.durationRemaining ?? fallbackMeters / 4.2
        let arrival = Date().addingTimeInterval(remaining)
        let clock = arrival.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        return .init(maneuver: Maneuver(type: instruction?.maneuverType, modifier: instruction?.maneuverModifier),
                     distance: distance(progress?.distanceToNextManeuver ?? fallbackMeters),
                     street: instruction?.text ?? destination.name, arrival: clock,
                     minutesLeft: "\(max(1, Int((remaining / 60).rounded()))) min",
                     distanceLeft: Format.km(progress?.distanceRemaining ?? fallbackMeters))
    }

    /// "200 m", "1.2 km" (rounded like the P5 ManeuverBanner).
    static func distance(_ m: Double) -> String {
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
