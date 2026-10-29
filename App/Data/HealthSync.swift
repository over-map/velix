import CoreLocation
import Foundation
import HealthKit

/// A ride as an Apple Health workout (M9b): outdoor cycling, one activity per ridden leg (a bike + train trip
/// doesn't count the train), the cycling distance and the route. No energy: Velix doesn't know the rider's weight.
struct HealthWorkout: Sendable {
    struct Leg: Sendable, Equatable {
        var start: Date
        var end: Date
        var meters: Double
    }

    var start: Date
    var end: Date
    var legs: [Leg]
    /// The ridden fixes (not the train's), for the workout route.
    var route: [CLLocation]

    var meters: Double { legs.reduce(0) { $0 + $1.meters } }

    /// From a ride log's lines (RideLog format): a leg is a run of ridden fixes, the train's split them.
    static func from(lines: [String]) -> HealthWorkout? {
        var legs: [Leg] = []
        var route: [CLLocation] = []
        var stats = RideStats(), legStart: Date?, legEnd: Date?
        func close() {
            if let s = legStart, let e = legEnd, e > s { legs.append(Leg(start: s, end: e, meters: stats.meters)) }
            stats = RideStats(); legStart = nil; legEnd = nil
        }
        for line in lines {
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], o["e"] == nil,
                  let t = o["t"] as? Double, let lat = o["lat"] as? Double, let lon = o["lon"] as? Double else { continue }
            if o["train"] != nil { close(); continue }
            let time = Date(timeIntervalSince1970: t)
            let l = CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), altitude: o["alt"] as? Double ?? 0,
                               horizontalAccuracy: o["acc"] as? Double ?? -1, verticalAccuracy: o["alt"] == nil ? -1 : 10,
                               course: o["c"] as? Double ?? -1, speed: o["v"] as? Double ?? -1, timestamp: time)
            stats.add(l)
            legStart = legStart ?? time
            legEnd = time
            if l.horizontalAccuracy >= 0, l.horizontalAccuracy <= 30 { route.append(l) }
        }
        close()
        guard let first = legs.first, let last = legs.last else { return nil }
        return HealthWorkout(start: first.start, end: last.end, legs: legs, route: route)
    }
}

/// Where workouts go: HealthKit on the phone, a fake in tests.
protocol HealthStoring: Sendable {
    var available: Bool { get }
    /// Asks to write workouts, cycling distance and routes (nothing is read); true when workouts may be saved.
    func authorize() async throws -> Bool
    func save(_ workout: HealthWorkout) async throws
}

struct HealthKitStore: HealthStoring {
    private let store = HKHealthStore()

    var available: Bool { HKHealthStore.isHealthDataAvailable() }

    private var types: Set<HKSampleType> {
        [HKObjectType.workoutType(), HKQuantityType(.distanceCycling), HKSeriesType.workoutRoute()]
    }

    func authorize() async throws -> Bool {
        try await store.requestAuthorization(toShare: types, read: [])
        return store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    func save(_ w: HealthWorkout) async throws {
        let config = HKWorkoutConfiguration()
        config.activityType = .cycling
        config.locationType = .outdoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        try await builder.beginCollection(at: w.start)
        let distance = HKQuantityType(.distanceCycling)
        let samples = w.legs.map {
            HKQuantitySample(type: distance, quantity: HKQuantity(unit: .meter(), doubleValue: $0.meters), start: $0.start, end: $0.end)
        }
        try await builder.addSamples(samples)
        if w.legs.count > 1 {
            for leg in w.legs {
                try await builder.addWorkoutActivity(HKWorkoutActivity(workoutConfiguration: config, start: leg.start, end: leg.end,
                                                                       metadata: nil))
            }
        }
        try await builder.endCollection(at: w.end)
        guard let workout = try await builder.finishWorkout() else { return }
        guard !w.route.isEmpty else { return }
        let route = HKWorkoutRouteBuilder(healthStore: store, device: .local())
        try await route.insertRouteData(w.route)
        _ = try await route.finishRoute(with: workout, metadata: nil)
    }
}

/// Saves finished rides to Apple Health when You → Apple Health is on.
@MainActor
enum HealthSync {
    static func save(_ record: RideRecord, to store: HealthStoring, history: RideHistory) async {
        guard store.available, !record.healthSaved,
              let lines = try? String(contentsOf: RideHistory.directory.appending(path: record.logFile), encoding: .utf8)
                .split(separator: "\n").map(String.init),
              let workout = HealthWorkout.from(lines: lines) else { return }
        do {
            try await store.save(workout)
            record.healthSaved = true
            history.save()
        } catch {
            print("Health save failed: \(error)")
        }
    }
}
