#if DEBUG
import Foundation

/// P4 sample places and notices (Milan), for previews and snapshot tests.
enum AppSamples {
    static let home = Place(id: "home", name: "Porta Venezia", subtitle: "Milan", kind: .address, lat: 45.4762, lon: 9.2047)
    static let work = Place(id: "work", name: "Politecnico, Città Studi", subtitle: "Piazza Leonardo da Vinci", kind: .poi,
                            lat: 45.4781, lon: 9.2272)
    static let recents = [
        Place(id: "r1", name: "Milano Centrale", subtitle: "Railway station", kind: .station, lat: 45.4859, lon: 9.2040),
        Place(id: "r2", name: "Villa Reale", subtitle: "Monza", kind: .park, lat: 45.5915, lon: 9.2747),
        Place(id: "r3", name: "Piazza Leonardo da Vinci", subtitle: "Città Studi", kind: .poi, lat: 45.4782, lon: 9.2271),
    ]
    static let centrResults = [
        Place(id: "c1", name: "Milano Centrale", subtitle: "Railway station · Piazza Duca d’Aosta", kind: .station, lat: 45.4859, lon: 9.2040),
        Place(id: "c2", name: "Centrale", subtitle: "Metro station", kind: .metro, lat: 45.4848, lon: 9.2048, lines: ["M2", "M3"], lineFamilies: ["green", "yellow"]),
        Place(id: "c3", name: "Piazza Duca d’Aosta", subtitle: "Square by Milano Centrale", kind: .poi, lat: 45.4850, lon: 9.2040),
    ]
    // MARK: S3 route options (P4 copy, Porta Venezia → Politecnico)

    static let portaVenezia = LatLon(lat: 45.4746, lon: 9.2050)
    static let politecnico = Place(id: "poli", name: "Politecnico", subtitle: "Piazza Leonardo da Vinci", kind: .poi,
                                   lat: 45.4781, lon: 9.2272)

    static func option(minutes: Double, km: Double, mix: [MixCategory: Double], hazards: [RouteHazard] = []) -> RouteOption {
        var a = RouteAnalysis(shape: [portaVenezia, politecnico.location], edges: [])
        a.lengthM = km * 1000
        a.mix = mix
        a.hazards = hazards
        return RouteOption(costing: RoutingProfile(costing: "bicycle", costingOptions: [:]), osrmJSON: "{}",
                           seconds: minutes * 60, meters: km * 1000, analysis: a, exclusions: [])
    }

    static let bestHazards = [
        RouteHazard(type: .tram, distanceAlong: 300, lengthM: 0, street: "Piazza Oberdan", detail: "", osm: "n1"),
        RouteHazard(type: .tram, distanceAlong: 900, lengthM: 0, street: "Via Melzo", detail: "", osm: "n2"),
        RouteHazard(type: .tram, distanceAlong: 1500, lengthM: 0, street: "P.za Adelaide di Savoia", detail: "", osm: "n3"),
        RouteHazard(type: .tram, distanceAlong: 2600, lengthM: 0, street: "P.za Ascoli", detail: "", osm: "n4"),
        RouteHazard(type: .cobbles, distanceAlong: 2650, lengthM: 70, street: "Piazza Ascoli", detail: "", osm: "w5"),
    ]

    static func options(single: Bool = false, rideType: RideType = .city, lit: Bool = false) -> RouteOptions {
        let best = option(minutes: rideType == .cargo ? 27 : (single ? 13 : 23), km: rideType == .cargo ? 5.6 : (single ? 3.1 : 5.4),
                          mix: [.protected: 2200, .painted: 1300, .quiet: 1600, .mixed: 300], hazards: bestHazards)
        let fastest = option(minutes: 18, km: 4.6, mix: [.protected: 700, .painted: 900, .quiet: 500, .mixed: 2000, .cobbles: 300])
        let bestLine = single ? "Fastest is only 30 s quicker, with rails along Corso Buenos Aires. So there’s one route."
            : rideType == .cargo ? "+9 min · bike lanes all the way, no steps, no cobbles"
            : "+5 min · avoids 300 m cobbles and busy Corso Buenos Aires"
        return RouteOptions(rules: .defaults(for: rideType), best: best, fastest: single ? nil : fastest, fastestAnalysis: fastest.analysis,
                            bestName: single ? "Best and fastest" : rideType.bestName, bestLine: bestLine,
                            fastestLine: single ? nil : (rideType == .cargo ? "9 min quicker · cobbles, mixed traffic, a kerb at Piazza Bacone"
                                                         : "5 min quicker · 300 m cobbles on Via Morgagni, busy Corso Buenos Aires"),
                            litLine: lit ? "Lit streets only: avoids 2 dark park paths, +2 min" : nil,
                            avoided: [AvoidedRoad(name: "Viale Piave", meters: 400, reason: "Rails along lane", shape: []),
                                      AvoidedRoad(name: "Via Morgagni", meters: 300, reason: "Cobbles 300 m", shape: [])],
                            unavoidable: [], rounds: 1, milliseconds: 420)
    }

    // MARK: S4 riding (P5 copy, the Politecnico trip)

    /// Porta Venezia → a turn 580 m on → Politecnico: quiet street, then a main road (P5 pill "Quiet · 160 m" at 420 m).
    static func rideOption() -> RouteOption {
        let turn = LatLon(lat: 45.4762, lon: 9.2121)
        var a = RouteAnalysis(shape: [portaVenezia, turn, politecnico.location])
        a.edges = [RouteEdge(wayId: 1, lengthKm: 0.58, roadClass: "residential", beginShapeIndex: 0, endShapeIndex: 1),
                   RouteEdge(wayId: 2, lengthKm: 1.2, roadClass: "secondary", beginShapeIndex: 1, endShapeIndex: 2)]
        a.lengthM = 1780
        a.hazards = [RouteHazard(type: .tram, distanceAlong: 580, lengthM: 0, street: "P.za Adelaide di Savoia", detail: "", osm: "n3")]
        return RouteOption(costing: RoutingProfile(costing: "bicycle", costingOptions: [:]), osrmJSON: "{}",
                           seconds: 18 * 60, meters: 4400, analysis: a, exclusions: [])
    }

    /// The ride `position` metres in, at 08:24, with P5 S4a's turn (Via Nino Bixio, then P.za Adelaide).
    static func ride(at position: Double = 420) -> RideScreenState.Ride {
        let option = rideOption()
        var track = RouteTrack(shape: option.analysis.shape)
        track.update(track.point(at: position))
        let tracker = HazardTracker(hazards: option.analysis.hazards)
        let now = Calendar.current.date(bySettingHour: 8, minute: 24, second: 0, of: Date(timeIntervalSince1970: 1_791_000_000))!
        return .init(turn: RideTurn(maneuver: .left, meters: 160, street: "Via Nino Bixio",
                                    then: .init(maneuver: .right, street: "P.za Adelaide"), secondsLeft: 18 * 60, metersLeft: 4400),
                     option: option, track: track, next: tracker.next(at: track.position),
                     destination: Place(id: "poli", name: "Politecnico, on the left", subtitle: "", kind: .poi,
                                        lat: politecnico.lat, lon: politecnico.lon),
                     avoided: [AvoidedRoad(name: "Viale Piave", meters: 400, reason: "Rails along lane",
                                           shape: [LatLon(lat: 45.4745, lon: 9.2090), LatLon(lat: 45.4720, lon: 9.2100)])],
                     rider: track.point(at: track.position), heading: 75, now: now)
    }

    static let storm = WeatherWarning(title: "Severe weather in Milan", message: "Thunderstorms until 18:00. Take care if you ride.",
                                      pill: "Storm until 18:00")
}
#endif
