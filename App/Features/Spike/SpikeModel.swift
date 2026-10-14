#if DEBUG
import ActivityKit
import Combine
import CoreLocation
@preconcurrency import FerrostarCore
@preconcurrency import FerrostarCoreFFI
import Foundation
import MapLibreSwiftUI
import Observation
import UIKit

/// M1 tech spike: on-device Valhalla → Ferrostar session → MapLibre, with measurements.
/// Debug builds only; replaced by the real Ride / Riding flows in M6–M7.
@MainActor
@Observable
final class SpikeModel {
    enum LocationSource: String, CaseIterable, Identifiable {
        case device = "Device GPS"
        case simulated = "Simulated"
        var id: String { rawValue }
    }

    var status = "Starting…"
    var engineInitMs: Double?
    var results: [String] = []
    var isBusy = false
    var locationSource: LocationSource = .device
    var camera: MapViewCamera = .center(SpikeTrip.portaVenezia, zoom: 14)
    var navigationState: NavigationState?
    var lastRouteMs: Double?
    var reroutes: [Double] = []

    private(set) var core: FerrostarCore?
    private var provider: ValhallaOnDeviceProvider?
    private var cancellables = Set<AnyCancellable>()
    private var batteryTimer: Timer?
    private var activity: Activity<RideActivityAttributes>?
    private let deviceLocation = CoreLocationProvider(activityType: .otherNavigation, allowBackgroundLocationUpdates: true)
    private let metrics = SpikeMetrics.shared

    var isNavigating: Bool { core?.state?.isNavigating == true }

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        deviceLocation.startUpdating()
    }

    // MARK: Engine

    func loadEngine() async {
        guard provider == nil else { return }
        guard let tiles = RegionPack.tileExtract else {
            status = "No tiles. Side-load valhalla_tiles.tar into Documents (pipeline/spike/README.md)."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let profile = try RoutingProfile.load("city")
            let start = Date()
            let provider = try await Task.detached(priority: .userInitiated) {
                try ValhallaOnDeviceProvider(tileExtract: tiles, profile: profile)
            }.value
            let ms = Date().timeIntervalSince(start) * 1000
            engineInitMs = ms
            let sizeMB = ((try? FileManager.default.attributesOfItem(atPath: tiles.path)[.size] as? Int) ?? 0) / 1_048_576
            metrics.log("engine_init", ["ms": ms.rounded(), "tilesMB": sizeMB, "device": Self.deviceModel])
            provider.onRouteComputed = { [weak self] ms, route in
                Task { @MainActor in self?.routeComputed(ms: ms, route: route) }
            }
            self.provider = provider
            status = "Engine ready in \(Int(ms)) ms · tiles \(sizeMB) MB"
        } catch {
            status = "Engine failed: \(error)"
            metrics.log("engine_error", ["error": String(describing: error)])
        }
    }

    private func routeComputed(ms: Double, route: Route?) {
        lastRouteMs = ms
        if isNavigating {
            reroutes.append(ms)
            metrics.log("reroute", ["ms": ms.rounded(), "m": Int(route?.distance ?? 0)])
        }
    }

    // MARK: Benchmark

    /// Each benchmark trip 5×: first call (cold caches) and median of the rest.
    func runBenchmark() async {
        guard let provider else { return }
        isBusy = true
        defer { isBusy = false }
        results = []
        for trip in SpikeTrip.benchmark {
            var times: [Double] = []
            var km = 0.0
            for _ in 0 ..< 5 {
                let start = Date()
                do {
                    let routes = try await provider.getRoutes(
                        userLocation: UserLocation(clCoordinateLocation2D: trip.from),
                        waypoints: [Waypoint(coordinate: GeographicCoordinate(cl: trip.to), kind: .break)]
                    )
                    km = (routes.first?.distance ?? 0) / 1000
                } catch {
                    results.append("\(trip.id): \(error)")
                    metrics.log("benchmark_error", ["trip": trip.id, "error": String(describing: error)])
                    break
                }
                times.append(Date().timeIntervalSince(start) * 1000)
            }
            guard !times.isEmpty else { continue }
            let warm = times.dropFirst().sorted()
            let median = warm.isEmpty ? times[0] : warm[warm.count / 2]
            results.append(String(format: "%@ · %.1f km · first %.0f ms · median %.0f ms", trip.id, km, times[0], median))
            metrics.log("benchmark", ["trip": trip.id, "m": Int(km * 1000), "firstMs": times[0].rounded(), "medianMs": median.rounded()])
        }
        status = "Benchmark done · memory \(Int(SpikeMetrics.memoryFootprintMB)) MB"
    }

    // MARK: Ride

    /// Starts guidance. Simulated: from Porta Venezia along the route. Device: from the current GPS fix.
    func startRide(to destination: CLLocationCoordinate2D, name: String) async {
        guard let provider else { return }
        isBusy = true
        defer { isBusy = false }

        let origin: CLLocationCoordinate2D
        let locationProvider: LocationProviding
        let simulated = SimulatedLocationProvider(coordinate: SpikeTrip.portaVenezia)
        switch locationSource {
        case .simulated:
            origin = SpikeTrip.portaVenezia
            simulated.warpFactor = 2
            locationProvider = simulated
        case .device:
            guard let fix = deviceLocation.lastLocation else {
                status = "Waiting for a GPS fix…"
                return
            }
            origin = fix.clLocation.coordinate
            locationProvider = deviceLocation
        }

        let config = SwiftNavigationControllerConfig(
            waypointAdvance: .waypointWithinRange(30),
            stepAdvanceCondition: stepAdvanceDistanceEntryAndExit(distanceToEndOfStep: 20, distanceAfterEndOfStep: 5, minimumHorizontalAccuracy: 25),
            arrivalStepAdvanceCondition: stepAdvanceDistanceToEndOfStep(distance: 10, minimumHorizontalAccuracy: 25),
            routeDeviationTracking: .staticThreshold(minimumHorizontalAccuracy: 25, maxAcceptableDeviation: 30),
            snappedLocationCourseFiltering: .snapToRoute
        )
        let core = FerrostarCore(customRouteProvider: provider, locationProvider: locationProvider, navigationControllerConfig: config)
        core.$state.receive(on: DispatchQueue.main).sink { [weak self] state in
            self?.navigationState = state
            if case .complete = state?.tripState { self?.rideEnded(reason: "arrived") }
        }.store(in: &cancellables)

        do {
            let routes = try await core.getRoutes(
                initialLocation: UserLocation(clCoordinateLocation2D: origin),
                waypoints: [Waypoint(coordinate: GeographicCoordinate(cl: destination), kind: .break)]
            )
            guard let route = routes.first else { throw RoutingError.noRoute("empty response") }
            if locationSource == .simulated {
                try simulated.setSimulatedRoute(route, resampleDistance: 5)
                simulated.startUpdating()
            }
            try core.startNavigation(route: route)
            self.core = core
            reroutes = []
            camera = .automotiveNavigation(zoom: 17)
            UIApplication.shared.isIdleTimerDisabled = true
            metrics.log("ride_start", ["to": name, "source": locationSource.rawValue, "m": Int(route.distance), "routeMs": (lastRouteMs ?? -1).rounded()])
            startLiveActivity()
            batteryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [metrics] _ in
                MainActor.assumeIsolated { metrics.log("ride_tick") }
            }
            status = String(format: "Riding to %@ · %.1f km · route %.0f ms", name, route.distance / 1000, lastRouteMs ?? -1)
        } catch {
            status = "Route failed: \(error)"
            metrics.log("route_error", ["to": name, "error": String(describing: error)])
        }
    }

    func stopRide() {
        rideEnded(reason: "stopped")
    }

    private func rideEnded(reason: String) {
        guard let core else { return }
        core.stopNavigation()
        self.core = nil
        cancellables.removeAll()
        batteryTimer?.invalidate()
        batteryTimer = nil
        UIApplication.shared.isIdleTimerDisabled = false
        activity = nil
        Task {
            for activity in Activity<RideActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        camera = .center(deviceLocation.lastLocation?.clLocation.coordinate ?? SpikeTrip.portaVenezia, zoom: 14)
        metrics.log("ride_end", ["reason": reason, "reroutes": reroutes.count, "rerouteMaxMs": (reroutes.max() ?? 0).rounded()])
        status = "Ride \(reason) · \(reroutes.count) reroutes"
    }

    /// Checks that the free Personal Team can run a Live Activity (M1 capability check).
    private func startLiveActivity() {
        let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        do {
            activity = try Activity.request(
                attributes: RideActivityAttributes(),
                content: .init(state: .init(), staleDate: nil)
            )
            metrics.log("live_activity", ["started": true, "enabled": enabled])
        } catch {
            metrics.log("live_activity", ["started": false, "enabled": enabled, "error": String(describing: error)])
        }
    }

    func metricsLog() -> String {
        (try? String(contentsOf: metrics.fileURL, encoding: .utf8)) ?? ""
    }

    private static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}
#endif
