import CoreLocation
import Observation

/// The rider's location for the Ride map and search bias (P7 S0 asks for "While Using App"; riding in M7 keeps its
/// own Ferrostar provider).
@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    enum Access: Equatable { case notAsked, denied, allowed }

    private(set) var access: Access = .notAsked
    private(set) var location: CLLocation?
    private(set) var heading: Double?
    /// Allowed but no fix after a while (S1f "Can't find your location").
    private(set) var cannotFind = false

    private let manager = CLLocationManager()
    private var fixTimer: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        update(manager.authorizationStatus)
    }

    var coordinate: LatLon? { location.map { LatLon(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude) } }

    func requestAccess() { manager.requestWhenInUseAuthorization() }

    private func start() {
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        fixTimer?.cancel()
        fixTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !Task.isCancelled else { return }
            if self.location == nil { self.cannotFind = true }
        }
    }

    private func update(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined: access = .notAsked
        case .authorizedAlways, .authorizedWhenInUse: access = .allowed; start()
        default: access = .denied; manager.stopUpdatingLocation()
        }
    }

    #if DEBUG
    /// Snapshot tests and previews: a fixed state, without CoreLocation.
    func setForTesting(access: Access, location: LatLon?, cannotFind: Bool = false) {
        manager.delegate = nil
        manager.stopUpdatingLocation()
        self.access = access
        self.location = location.map { CLLocation(latitude: $0.lat, longitude: $0.lon) }
        self.cannotFind = cannotFind
    }
    #endif

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        let status = m.authorizationStatus
        MainActor.assumeIsolated { update(status) }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        MainActor.assumeIsolated {
            location = last
            cannotFind = false
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateHeading h: CLHeading) {
        let value = h.trueHeading >= 0 ? h.trueHeading : h.magneticHeading
        MainActor.assumeIsolated { heading = value }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {}
}
