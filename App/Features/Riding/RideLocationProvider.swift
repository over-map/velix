import CoreLocation
@preconcurrency import FerrostarCore
@preconcurrency import FerrostarCoreFFI
import Foundation

/// GPS quality while riding (P5 S4h "GPS is weak").
enum GPSQuality: Equatable, Sendable { case good, weak }

/// The ride's location source (M7; M1 finding 2): Ferrostar's `CoreLocationProvider` keeps iOS's automatic pausing on,
/// which left a 2.5-minute gap while Filippo stood still on the M1 ride. Ours never pauses, drops stale fixes and
/// implausible jumps, and tells the screen when the fix is weak.
final class RideLocationProvider: NSObject, LocationProviding, CLLocationManagerDelegate, @unchecked Sendable {   // main thread only
    weak var delegate: LocationManagingDelegate?
    private(set) var lastLocation: UserLocation?
    private(set) var lastHeading: Heading?
    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    /// Every accepted fix, with its quality (the ride log, the screen).
    var onFix: (CLLocation, GPSQuality) -> Void = { _, _ in }

    private let manager = CLLocationManager()
    private var lastAccepted: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .otherNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
    }

    func startUpdating() {
        #if DEBUG
        if simulated != nil { return startSimulation() }
        #endif
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }

    func stopUpdating() {
        #if DEBUG
        simulationTimer?.invalidate()
        simulationTimer = nil
        #endif
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    #if DEBUG
    /// `-simulate-ride`: ride the planned route at `simulatedSpeed` (`-simulate-speed 3`), one fix a second of app time
    /// (``AppClock/scale``), so the riding screen, hazard alerts, voice, the Live Activity and the transit stages can be
    /// tried away from Lombardy. Simulated fixes skip the jump filter (time runs faster than the fixes' timestamps).
    static var simulates: Bool { ProcessInfo.processInfo.arguments.contains("-simulate-ride") }
    static let simulatedSpeed: CLLocationSpeed = {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-simulate-speed"), i + 1 < args.count, let v = Double(args[i + 1]), v > 0 { return v }
        return 5
    }()
    private var simulated: (shape: [LatLon], along: [Double])?
    private var simulatedDistance = 0.0
    /// A train run: along the line between these app times, standing at the start until the departure.
    private var simulatedRun: (departs: Date, arrives: Date)?
    private var simulationTimer: Timer?

    func simulate(_ shape: [LatLon], from position: Double = 0) {
        simulated = (shape, RouteAnalyzer.cumulative(shape))
        simulatedDistance = position
        simulatedRun = nil
    }

    func simulate(_ line: [LatLon], departs: Date, arrives: Date) {
        simulate(line)
        simulatedRun = (departs, arrives)
        if simulationTimer == nil { startSimulation() }
    }

    private func startSimulation() {
        simulationTimer?.invalidate()
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 1 / AppClock.scale, repeats: true) { [weak self] _ in
            self?.simulationStep()
        }
    }

    private func simulationStep() {
        guard let (shape, along) = simulated, let length = along.last else { return }
        var speed = Self.simulatedSpeed
        if let run = simulatedRun {
            let total = max(1, run.arrives.timeIntervalSince(run.departs))
            let share = min(1, max(0, AppClock.now.timeIntervalSince(run.departs) / total))
            speed = length / total
            simulatedDistance = share * length
        } else {
            simulatedDistance = min(simulatedDistance + Self.simulatedSpeed, length)
        }
        let p = RuleChecker.point(at: simulatedDistance, on: shape, along: along)
        let ahead = RuleChecker.point(at: min(simulatedDistance + 5, length), on: shape, along: along)
        let fix = CLLocation(coordinate: .init(latitude: p.lat, longitude: p.lon), altitude: 120, horizontalAccuracy: 5,
                             verticalAccuracy: 5, course: Geo.bearing(p, ahead), speed: speed, timestamp: Date())
        lastAccepted = fix
        lastLocation = fix.userLocation
        onFix(fix, .good)
        delegate?.locationManager(self, didUpdateLocations: [fix.userLocation])
    }
    #endif

    // MARK: Filtering (pure, tested)

    /// Older than this, a fix is a cached one iOS hands over on resume.
    static let maxAge: TimeInterval = 10
    /// Faster than this between two fixes is a GPS jump, not a bike (≈ 90 km/h).
    static let maxSpeed: CLLocationSpeed = 25
    /// Worse than this, the fix is weak (S4h).
    static let weakAccuracy: CLLocationAccuracy = 25

    static func accepts(_ fix: CLLocation, after previous: CLLocation?, now: Date) -> Bool {
        guard fix.horizontalAccuracy >= 0, now.timeIntervalSince(fix.timestamp) <= maxAge else { return false }
        guard let previous else { return true }
        let dt = fix.timestamp.timeIntervalSince(previous.timestamp)
        guard dt > 0 else { return false }
        // A jump only counts when both fixes are precise; a weak fix wanders and is allowed to.
        if fix.horizontalAccuracy < weakAccuracy, previous.horizontalAccuracy < weakAccuracy {
            return fix.distance(from: previous) / dt <= maxSpeed
        }
        return true
    }

    static func quality(of fix: CLLocation) -> GPSQuality {
        fix.horizontalAccuracy > weakAccuracy ? .weak : .good
    }

    // MARK: CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        var accepted: [CLLocation] = []
        for fix in locations where Self.accepts(fix, after: lastAccepted, now: Date()) {
            accepted.append(fix)
            lastAccepted = fix
        }
        guard let last = accepted.last else { return }
        lastLocation = last.userLocation
        onFix(last, Self.quality(of: last))
        delegate?.locationManager(self, didUpdateLocations: accepted.map(\.userLocation))
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard let heading = Heading(clHeading: newHeading) else { return }
        lastHeading = heading
        delegate?.locationManager(self, didUpdateHeading: heading)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        delegate?.locationManager(self, didFailWithError: error)
    }
}
