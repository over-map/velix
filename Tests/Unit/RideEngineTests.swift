import CoreLocation
@preconcurrency import FerrostarCore
@preconcurrency import FerrostarCoreFFI
import Foundation
import Testing
@testable import Velix

struct ReroutePolicyTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    @Test func needsThreeOffRouteFixesOrEightSeconds() {
        var p = ReroutePolicy()
        p.fix(offRoute: true, at: at(0))
        p.fix(offRoute: true, at: at(1))
        #expect(!p.shouldReroute(at: at(1)))
        p.fix(offRoute: true, at: at(2))
        #expect(p.shouldReroute(at: at(2)))

        var slow = ReroutePolicy()          // weak GPS: one fix every 5 s
        slow.fix(offRoute: true, at: at(0))
        slow.fix(offRoute: true, at: at(9))
        #expect(slow.isOffRoute)
        #expect(slow.shouldReroute(at: at(9)))
    }

    @Test func backOnTheRouteResetsTheCount() {
        var p = ReroutePolicy()
        p.fix(offRoute: true, at: at(0))
        p.fix(offRoute: true, at: at(1))
        p.fix(offRoute: false, at: at(2))
        p.fix(offRoute: true, at: at(3))
        #expect(!p.isOffRoute)
    }

    @Test func reroutesAreSpacedAndBackOffWhenTheRiderKeepsLeaving() {
        var p = ReroutePolicy()
        for s in 0 ... 2 { p.fix(offRoute: true, at: at(Double(s))) }
        p.requested(at: at(2))
        #expect(!p.shouldReroute(at: at(3)))       // in flight
        p.succeeded(at: at(3))
        // Riding their own way: off the new route at once (M1: 9–10 reroutes 7–10 s apart).
        for s in 4 ... 6 { p.fix(offRoute: true, at: at(Double(s))) }
        #expect(!p.shouldReroute(at: at(10)))      // 15 s since the last request
        #expect(p.shouldReroute(at: at(17)))
        p.requested(at: at(17))
        #expect(p.wait == 30)
        p.succeeded(at: at(18))
        for s in 19 ... 21 { p.fix(offRoute: true, at: at(Double(s))) }
        #expect(!p.shouldReroute(at: at(40)))
        #expect(p.shouldReroute(at: at(48)))
        p.requested(at: at(48))
        #expect(p.wait == 60)
    }

    @Test func calmOnTheRouteResetsTheWait() {
        var p = ReroutePolicy()
        for s in 0 ... 2 { p.fix(offRoute: true, at: at(Double(s))) }
        p.requested(at: at(2)); p.succeeded(at: at(3))
        for s in 4 ... 6 { p.fix(offRoute: true, at: at(Double(s))) }
        p.requested(at: at(20)); p.succeeded(at: at(21))
        #expect(p.wait == 30)
        p.fix(offRoute: false, at: at(22))
        p.fix(offRoute: false, at: at(22 + ReroutePolicy.calmAfter))
        #expect(p.wait == ReroutePolicy.baseWait)
    }

    @Test func aFailedRerouteIsRetriedStandingStillAndShownAfterThree() {
        var p = ReroutePolicy()
        for s in 0 ... 2 { p.fix(offRoute: true, at: at(Double(s))) }
        for i in 0 ..< 3 {
            let t = 2 + Double(i) * 15
            #expect(p.shouldReroute(at: at(t)))
            p.requested(at: at(t))
            p.failed(at: at(t + 1))
            p.fix(offRoute: true, at: at(t + 2))     // same place: standing still
        }
        #expect(p.cannotFindRoute)
        #expect(p.shouldReroute(at: at(47)))
    }
}

struct RideLocationTests {
    private func fix(_ lat: Double, _ lon: Double, acc: Double = 5, at t: Date) -> CLLocation {
        CLLocation(coordinate: .init(latitude: lat, longitude: lon), altitude: 120, horizontalAccuracy: acc,
                   verticalAccuracy: 5, course: 0, speed: 5, timestamp: t)
    }

    @Test func dropsStaleFixesAndJumps() {
        let now = Date()
        let a = fix(45.47, 9.20, at: now.addingTimeInterval(-1))
        #expect(!RideLocationProvider.accepts(fix(45.47, 9.20, at: now.addingTimeInterval(-30)), after: nil, now: now))
        #expect(RideLocationProvider.accepts(a, after: nil, now: now))
        // 300 m in 1 s: a GPS jump.
        #expect(!RideLocationProvider.accepts(fix(45.4727, 9.20, at: now), after: a, now: now))
        // 5 m in 1 s: riding.
        #expect(RideLocationProvider.accepts(fix(45.47005, 9.20, at: now), after: a, now: now))
        // A weak fix may wander.
        #expect(RideLocationProvider.accepts(fix(45.4727, 9.20, acc: 60, at: now), after: a, now: now))
        #expect(RideLocationProvider.quality(of: fix(45.47, 9.2, acc: 60, at: now)) == .weak)
    }
}

struct RouteTrackTests {
    // 1 km east, then 1 km north.
    private let shape = [LatLon(lat: 45.47, lon: 9.20), LatLon(lat: 45.47, lon: 9.2128), LatLon(lat: 45.479, lon: 9.2128)]

    @Test func followsTheRiderAndTrimsWhatIsBehind() {
        var t = RouteTrack(shape: shape)
        t.update(LatLon(lat: 45.4701, lon: 9.2064))          // 500 m along, a few metres off the line
        #expect(abs(t.position - 500) < 15)
        #expect(t.ahead.count == 3)
        t.update(LatLon(lat: 45.4745, lon: 9.2129))          // 1.5 km along
        #expect(abs(t.position - 1500) < 15)
        #expect(t.ahead.count == 2)
        #expect(abs(t.remaining - 500) < 20)
    }

    @Test func offRouteFixesDoNotMoveIt() {
        var t = RouteTrack(shape: shape)
        t.update(LatLon(lat: 45.4701, lon: 9.2064))
        let p = t.position
        t.update(LatLon(lat: 45.475, lon: 9.2064))           // 550 m north of the line
        #expect(t.position == p)
    }
}

struct HazardTrackerTests {
    private func h(_ type: HazardType, _ at: Double, length: Double = 0, detail: String = "") -> RouteHazard {
        RouteHazard(type: type, distanceAlong: at, lengthM: length, street: nil, detail: detail, osm: "w1")
    }

    @Test func oneCardAtATimeAndOneAlertEach() {
        var t = HazardTracker(hazards: [h(.cobbles, 400, length: 120), h(.tram, 160)])
        #expect(t.next(at: 0)?.hazard.type == .tram)
        #expect(t.next(at: 0)?.approaching == false)
        #expect(t.alert(at: 100) == nil)
        #expect(t.alert(at: 115)?.type == .tram)             // 45 m before
        #expect(t.alert(at: 130) == nil)                     // once
        #expect(t.next(at: 170)?.hazard.type == .cobbles)    // passed the rails
        #expect(t.next(at: 600) == nil)
    }

    @Test func aRerouteDoesNotRepeatAnAlert() {
        var t = HazardTracker(hazards: [h(.tram, 60)])
        #expect(t.alert(at: 20)?.type == .tram)
        var after = HazardTracker(hazards: [h(.tram, 30)], alerted: t.alerted)   // the same rails on the new route
        #expect(after.alert(at: 0) == nil)
    }

    @Test func weakGPSAlertsEarlier() {
        var t = HazardTracker(hazards: [h(.tram, 160)])
        #expect(t.alert(at: 95) == nil)
        #expect(t.alert(at: 95, gps: .weak)?.type == .tram)  // 65 m before
    }

    @Test func onlyNarrowGapsAlert() {
        let t = HazardTracker(hazards: [h(.gap, 100, detail: "gate"), h(.gap, 200, detail: "cycle_barrier")])
        #expect(t.hazards.count == 1)
        #expect(t.next(at: 0)?.hazard.detail == "cycle_barrier")
    }

    @Test func promptsFollowTheDesign() {
        #expect(HazardPrompt.voice(h(.tram, 0)) == "Tram rails ahead. Cross straight.")
        #expect(HazardPrompt.voice(h(.cobbles, 0, length: 287)) == "Cobbles for 300 metres.")
        #expect(HazardPrompt.advice(h(.dismount, 0, length: 38)) == "Walk your bike for 40 m")
        #expect(HazardPrompt.advice(h(.steps, 0, detail: "12")) == "Carry your bike up 12 steps")
        #expect(HazardPrompt.advice(h(.descent, 0, detail: "−9% for 200 m")) == "−9% for 200 m, brake early")
        #expect(HazardPrompt.title(h(.tram, 0)) == "Tram rails")
        for type in HazardType.allCases {
            let words = HazardPrompt.voice(h(type, 0, length: 300)).split(separator: " ").count
            #expect(words <= 6, "\(type): \(HazardPrompt.voice(h(type, 0, length: 300)))")
        }
    }
}

struct RideRulesTests {
    @Test func endsAtTheDoorNotOnTheWay() {
        // 2 km route: near the destination only after most of it (a loop passes close to the door early).
        #expect(!RideSession.hasArrived(remaining: 1500, position: 500, length: 2000, toDestination: 20))
        #expect(RideSession.hasArrived(remaining: 40, position: 1960, length: 2000, toDestination: 25))
        #expect(!RideSession.hasArrived(remaining: 40, position: 1960, length: 2000, toDestination: 60))
        #expect(RideSession.hasArrived(remaining: 3, position: 1997, length: 2000, toDestination: 45))
    }

    @Test func voiceModesCycle() {
        #expect(VoiceMode.all.next == .alerts)
        #expect(VoiceMode.alerts.next == .mute)
        #expect(VoiceMode.mute.next == .all)
        #expect(VoiceMode.alerts.speaksHazards && !VoiceMode.alerts.speaksTurns)
        #expect(!VoiceMode.mute.speaksHazards)
    }

    @Test func statsCountMovingTimeAndClimb() {
        var s = RideStats()
        let t0 = Date()
        func f(_ i: Int, lat: Double, alt: Double) -> CLLocation {
            CLLocation(coordinate: .init(latitude: lat, longitude: 9.2), altitude: alt, horizontalAccuracy: 5,
                       verticalAccuracy: 5, course: 0, speed: 5, timestamp: t0.addingTimeInterval(Double(i)))
        }
        s.add(f(0, lat: 45.4700, alt: 120))
        s.add(f(1, lat: 45.47005, alt: 121))        // 5.6 m/s, +1 m (noise)
        s.add(f(2, lat: 45.4701, alt: 123))         // +3 m from 120 → counts
        s.add(f(12, lat: 45.4701, alt: 123))        // stopped 10 s at a light
        #expect(abs(s.meters - 11) < 1)
        #expect(s.movingSeconds == 2)
        #expect(s.climb == 3)
    }
}

struct PlannedRouteProviderTests {
    @Test func picksTheRidersCardAndTheClosestWhenRulesBlock() throws {
        let options = AppSamples.options()
        let best = options.best
        let fast = try #require(options.fastest)
        #expect(PlannedRouteProvider.pick(.options(options), choice: .best)?.meters == best.meters)
        #expect(PlannedRouteProvider.pick(.options(options), choice: .fastest)?.meters == fast.meters)
        #expect(best.meters != fast.meters)
        #expect(PlannedRouteProvider.pick(.noRouteMeetsRules(.noCobbles, .cargo, closest: best, remaining: []), choice: .best)?.meters == best.meters)
        #expect(PlannedRouteProvider.pick(.noRoute, choice: .best) == nil)
    }

    @Test func aFailedPlanIsReportedAndThrown() async {
        final class Flag: @unchecked Sendable { var set = false }
        let flag = Flag()
        let provider = PlannedRouteProvider(choice: .best) { _, _, _ in .noRoute }
        provider.onFailure = { flag.set = true }
        let here = UserLocation(clCoordinateLocation2D: .init(latitude: 45.47, longitude: 9.2))
        let to = Waypoint(coordinate: GeographicCoordinate(lat: 45.48, lng: 9.22), kind: .break)
        await #expect(throws: (any Error).self) { try await provider.getRoutes(userLocation: here, waypoints: [to]) }
        #expect(flag.set)
    }
}

struct RideCameraTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    @Test func viewCyclesAndSetsTheFollowCamera() {
        var c = RideCamera()
        let here = LatLon(lat: 45.47, lon: 9.2)
        #expect(c.follow(at: here, course: 90) == MapCamera(center: here, zoom: 16.6, bearing: 90, anchor: 0.62))
        c.cycleView()
        #expect(c.view == .threeD)
        #expect(c.follow(at: here, course: 90).pitch == 50)
        c.cycleView()
        #expect(c.view == .north)
        #expect(c.follow(at: here, course: 90).bearing == 0)
        #expect(!c.showsChevron && c.drawsRider)       // North up: the dot and cone, on screen too
        c.cycleView()
        #expect(c.view == .twoD && c.showsChevron)
    }

    @Test func overviewGoesBackToFollowAfterTenSecondsOrASecondTap() {
        var c = RideCamera()
        c.toggleOverview(at: at(0))
        #expect(c.isOverview && !c.isFollowing)
        let early = c.tick(at: at(9))
        #expect(!early)
        let due = c.tick(at: at(10))
        #expect(due)
        #expect(c.isFollowing)
        c.toggleOverview(at: at(20))
        c.toggleOverview(at: at(21))
        #expect(c.isFollowing)
    }

    @Test func aPanPausesFollowUntilRecenterOrTenSeconds() {
        var c = RideCamera()
        c.cycleView()                                   // 3D
        c.userPanned(at: at(0))
        #expect(c.isPanned && !c.showsChevron && !c.drawsRider)
        c.cycleView()                                   // the view control while panned only resumes
        #expect(c.isFollowing && c.view == .threeD)
        c.userPanned(at: at(5))
        let resumed = c.tick(at: at(15))
        #expect(resumed)
        #expect(c.isFollowing)
        c.userPanned(at: at(20))
        c.recenter()
        #expect(c.isFollowing)
    }
}

struct RideScreenStateTests {
    private func h(_ type: HazardType, _ at: Double, length: Double = 0) -> RouteHazard {
        RouteHazard(type: type, distanceAlong: at, lengthM: length, street: nil, detail: "", osm: "w1")
    }

    @Test func hazardsBehindTheRiderAreDropped() {
        let ahead = RideScreenState.hazardsAhead([h(.tram, 100), h(.cobbles, 150, length: 200), h(.steps, 600)], from: 200)
        #expect(ahead.map(\.type) == [.cobbles, .steps])
        #expect(ahead[0].distanceAlong == 150)                             // the cobbles still under the wheels
        // Just passed (within 4 m) stays a moment longer.
        #expect(RideScreenState.hazardsAhead([h(.tram, 198)], from: 200).count == 1)
    }

    @Test func theRouteAheadMovesInStepsUnderTheRider() {
        let shape = [LatLon(lat: 45.47, lon: 9.20), LatLon(lat: 45.47, lon: 9.2128)]
        var t = RouteTrack(shape: shape)
        t.update(t.point(at: 101))
        let a = RideScreenState.trimmed(t)
        t.update(t.point(at: 104))
        #expect(RideScreenState.trimmed(t) == a)                    // same 15 m step: the map gets nothing new
        #expect(abs(Geo.distance(shape[0], a[0]) - 90) < 0.5)
        t.update(t.point(at: 106))
        #expect(RideScreenState.trimmed(t) != a)
    }

    @Test func avoidedRoadsShowOnlyNearTheRider() {
        let piave = AvoidedRoad(name: "Viale Piave", meters: 400, reason: "Rails along lane",
                                shape: [LatLon(lat: 45.4740, lon: 9.2050), LatLon(lat: 45.4700, lon: 9.2060)])
        let near = RideScreenState.avoidedNear(LatLon(lat: 45.4720, lon: 9.2080), [piave])       // ≈ 160 m from the line
        #expect(near.map(\.reason) == ["Skipping Viale Piave: rails"])
        #expect(RideScreenState.avoidedNear(LatLon(lat: 45.4800, lon: 9.2200), [piave]).isEmpty)   // ≈ 1.4 km
        #expect(AvoidedRoad(name: "Steps", meters: 120, reason: "Steps", shape: []).ridingTag == "Skipping steps")
    }

    @Test func thePillShowsWhatIsUnderTheWheelsAndForHowLong() {
        let shape = [LatLon(lat: 45.47, lon: 9.20), LatLon(lat: 45.47, lon: 9.2064), LatLon(lat: 45.47, lon: 9.2128)]
        var a = RouteAnalysis(shape: shape)
        a.edges = [RouteEdge(wayId: 1, lengthKm: 0.25, roadClass: "residential", beginShapeIndex: 0, endShapeIndex: 1),
                   RouteEdge(wayId: 2, lengthKm: 0.25, roadClass: "secondary", beginShapeIndex: 1, endShapeIndex: 2)]
        let run = RideScreenState.roadType(a, at: 340)
        #expect(run?.category == .quiet)
        #expect(abs((run?.meters ?? 0) - 160) < 5)
        #expect(RideScreenState.roadType(a, at: 600)?.category == .mixed)
    }
}

struct RideTurnTests {
    @Test func unnamedWaysShowNoStreet() {
        #expect(RideTurn.street("Turn right.") == nil)
        #expect(RideTurn.street("Viale Giovanni Brahms") == "Viale Giovanni Brahms")
        #expect(RideTurn.street(" ") == nil)
    }
}

struct RideRecordTests {
    @Test func gpxHasTheFixesAndNotTheEvents() {
        let lines = [#"{"t":1791000000,"e":"start","to":"Politecnico","m":4400}"#,
                     #"{"t":1791000001,"lat":45.47,"lon":9.2,"acc":5,"alt":120.4,"v":5,"c":90}"#,
                     #"{"t":1791000002,"lat":45.47005,"lon":9.2,"acc":5,"alt":121,"v":5,"c":90}"#,
                     #"{"t":1791000003,"e":"end","s":"arrived"}"#]
        let gpx = RideLog.gpx(lines: lines, name: "Velix · Politecnico & co")
        #expect(gpx.components(separatedBy: "<trkpt").count - 1 == 2)
        #expect(gpx.contains(#"<trkpt lat="45.47" lon="9.2"><ele>120.4</ele><time>2026-10-03T04:00:01Z</time>"#))
        #expect(gpx.contains("<name>Velix · Politecnico &amp; co</name>"))
    }

    @Test func theRiddenTrackKeepsAPointEveryTenMetres() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "velix-log-\(UUID().uuidString)")
        let log = RideLog(directory: dir)
        let t0 = Date()
        for i in 0 ..< 30 {   // 1.1 m apart: 33 m in all
            log.fix(CLLocation(coordinate: .init(latitude: 45.47 + Double(i) * 0.00001, longitude: 9.2), altitude: 120,
                               horizontalAccuracy: 5, verticalAccuracy: 5, course: 0, speed: 5, timestamp: t0.addingTimeInterval(Double(i))))
        }
        log.close()
        #expect(log.ridden.count == 4)
        let url = try log.gpx(name: "test")
        #expect(try String(contentsOf: url, encoding: .utf8).components(separatedBy: "<trkpt").count - 1 == 30)
    }
}

@MainActor
struct RideActivityContentTests {
    private func next(_ d: Double, approaching: Bool) -> HazardTracker.Next {
        HazardTracker.Next(index: 0, hazard: RouteHazard(type: .tram, distanceAlong: 0, lengthM: 0, street: nil, detail: "", osm: "n1"),
                           distance: d, approaching: approaching)
    }

    @Test func farHazardsGoInTheFooterAndCloseOnesLead() {
        var far = RideActivityAttributes.ContentState.sampleClear
        RideSession.addHazard(next(160, approaching: false), to: &far)
        #expect(far.hazard == nil)
        #expect(far.nextHazard?.text == "Tram rails in 160 m")      // P5 L1
        var close = RideActivityAttributes.ContentState.sampleClear
        RideSession.addHazard(next(35, approaching: true), to: &close)
        #expect(close.hazard?.advice == "Cross straight")            // P5 L2
        #expect(close.hazard?.longAdvice == "Cross straight, at a right angle")
    }

    @Test func lockScreenAdviceStaysShort() {
        for type in HazardType.allCases {
            let h = RouteHazard(type: type, distanceAlong: 0, lengthM: 300, street: nil, detail: "", osm: "w1")
            #expect(HazardPrompt.short(h).count <= 18, "\(type): \(HazardPrompt.short(h))")
        }
    }
}
