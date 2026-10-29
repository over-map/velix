import SnapshotTesting
import SwiftUI
import XCTest
@testable import Velix

/// Full-screen states of S0–S2 (and S3/S8 in M6b), light and dark, at 393 × 852. The map is a flat backdrop here
/// (MapLibre isn't deterministic in tests); docs/reviews/m6 has the live screens next to P4/P7.
@MainActor
final class ScreenSnapshotTests: XCTestCase {
    private let size = CGSize(width: 393, height: 852)
    private let portaVenezia = LatLon(lat: 45.4746, lon: 9.2050)

    struct NoSearch: PlaceSearch { func search(_ q: String, near: LatLon?) async throws -> [Place] { [] } }
    struct Warning: WeatherWarnings {
        func current(near: LatLon?) async -> WeatherWarning? { AppSamples.storm }
    }

    private func app(onboarded: Bool = true, home: Bool = true, work: Bool = true, recents: Bool = true,
                     access: LocationService.Access = .allowed, here: LatLon? = LatLon(lat: 45.4746, lon: 9.2050),
                     cannotFind: Bool = false, pack: PackService.State = .ready(.sideloaded), expensive: Bool = false,
                     rideType: RideType = .city, weather: WeatherWarnings = NoWeatherWarnings(), rides: Bool = false) -> AppModel {
        let dir = FileManager.default.temporaryDirectory.appending(path: "velix-snap-\(UUID().uuidString)")
        let store = AppStore(url: dir.appending(path: "state.json"))
        var s = AppState()
        s.onboarded = onboarded
        s.rideType = rideType
        if home { s.home = AppSamples.home }
        if work { s.work = AppSamples.work }
        if recents { s.recents = AppSamples.recents }
        store.save(s)
        let location = LocationService()
        location.setForTesting(access: access, location: here, cannotFind: cannotFind)
        let packService = PackService(installer: RegionPackInstaller(root: dir.appending(path: "RegionPack")), catalog: { nil })
        packService.setForTesting(pack, expensive: expensive)
        let prefs = MapStylePreference(defaults: UserDefaults(suiteName: "velix-snap-\(UUID().uuidString)")!)
        let history = RideHistory(inMemory: true)
        if rides { Self.sampleRides.forEach(history.add) }
        return AppModel(store: store, location: location, pack: packService, search: NoSearch(), weather: weather,
                        mapPreference: prefs, history: history)
    }

    static let ridesNow = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 18))!

    /// P7 S8's rides: Politecnico today 08:24, Villa Reale yesterday by bike + train, Centrale on Tue 7 Oct.
    static var sampleRides: [RideRecord] {
        let cal = Calendar.current
        let today = cal.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 8, minute: 24))!
        let yesterday = cal.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 9, minute: 2))!
        let oct7 = cal.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 18, minute: 10))!
        let track = AppSamples.rideOption().analysis.shape
        return [
            RideRecord(started: today, ended: today.addingTimeInterval(21 * 60), destination: "Politecnico", rideType: .city,
                       meters: 5400, movingSeconds: 21 * 60, climb: 8, arrived: true, track: track, logFile: "a.jsonl", gpxFile: nil),
            RideRecord(started: yesterday, ended: yesterday.addingTimeInterval(50 * 60), destination: "Villa Reale, Monza", rideType: .city,
                       meters: 14_000, movingSeconds: 30 * 60, climb: 20, arrived: true, transit: "Trenord RE80", track: track,
                       logFile: "b.jsonl", gpxFile: nil),
            RideRecord(started: oct7, ended: oct7.addingTimeInterval(13 * 60), destination: "Milano Centrale", rideType: .city,
                       meters: 3100, movingSeconds: 12 * 60, climb: 4, arrived: true, track: track, logFile: "c.jsonl", gpxFile: nil),
        ]
    }

    private func check(_ view: some View, named name: String, file: StaticString = #filePath, testName: String = #function,
                       line: UInt = #line) {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let vc = UIHostingController(rootView: view.environment(\.liveMap, false))
            vc.overrideUserInterfaceStyle = style
            assertSnapshot(of: vc, as: .image(on: .init(safeArea: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0), size: size,
                                                       traits: .init(userInterfaceStyle: style)),
                                              precision: 0.99, perceptualPrecision: 0.98),
                           named: "\(name)-\(style == .dark ? "dark" : "light")", file: file, testName: testName, line: line)
        }
    }

    // MARK: S0 First launch

    func testS0FirstLaunch() {
        check(OnboardingView(app: app(onboarded: false, access: .notAsked), onDone: {}), named: "S0a-location")
        check(OnboardingView(app: app(onboarded: false, access: .denied), onDone: {}), named: "S0c-denied")
        check(OnboardingView(app: app(onboarded: false, access: .allowed), step: 1, onDone: {}), named: "S0d-rideType")
        let mb = Int64(1_000_000)
        check(RootView(app: app(pack: .downloading(received: 132 * mb, total: 220 * mb), expensive: true), showDownload: true),
              named: "S0e-downloading")
        let ready = RegionPackManifest(schema: 1, pack: "lombardy", name: "Lombardy", version: "2026.10", built: "2026-10-16",
                                       valhalla: "3.9.0", bbox: RegionPackManifest.sideloaded.bbox, files: [],
                                       downloadBytes: 220 * mb, unpackedBytes: 0, budgetBytes: 0, sources: [])
        check(RootView(app: app(pack: .ready(ready)), showDownload: true), named: "S0f-ready")
        check(RootView(app: app(pack: .failed(received: 132 * mb, total: 220 * mb)), showDownload: true), named: "S0g-failed")
    }

    // MARK: S1 Ride

    func testS1Ride() async {
        // The weather comes from the source (RootView refreshes it on appear), not set directly: no race with that task.
        let weather = app(weather: Warning())
        weather.warning = AppSamples.storm
        check(RootView(app: weather), named: "S1a-weather")
        let panned = app(weather: Warning())
        panned.warning = AppSamples.storm
        panned.warningDismissed = true
        check(RootView(app: panned, following: false), named: "S1b-panned")
        check(RootView(app: app(home: false, work: false)), named: "S1c-unset")
        let mb = Int64(1_000_000)
        check(RootView(app: app(pack: .downloading(received: 132 * mb, total: 220 * mb))), named: "S1d-downloading")
        check(RootView(app: app(here: LatLon(lat: 41.9, lon: 12.5))), named: "S1e-outside")
        check(RootView(app: app(here: nil, cannotFind: true), following: false), named: "S1f-noGPS")
        check(RootView(app: app(), sheet: .rideType), named: "S1g-rideType")
        check(RootView(app: app(), sheet: .mapStyle), named: "S1h-mapStyle-city")
        check(RootView(app: app(rideType: .gravel), sheet: .mapStyle), named: "S1i-mapStyle-gravel")
    }

    // MARK: S2 Search

    func testS2Search() {
        check(SearchView(app: app(), purpose: .destination, onDone: { _ in }), named: "S2a-focused")
        check(SearchView(app: app(), purpose: .destination, query: "Centr", results: AppSamples.centrResults, onDone: { _ in }),
              named: "S2b-results")
        check(SearchView(app: app(home: false, work: false, recents: false), purpose: .destination, onDone: { _ in }), named: "S2c-firstUse")
        check(SearchView(app: app(), purpose: .destination, query: "Via Brerra", results: [], onDone: { _ in }), named: "S2d-noMatch")
        check(SearchView(app: app(), purpose: .destination, query: "Navig", offline: true, onDone: { _ in }), named: "S2e-offline")
    }

    // MARK: S3 Route options

    func testS3RouteOptions() {
        func s3(_ state: RouteOptionsModel.State, rideType: RideType = .city, why: Bool = false, lit: Bool = false,
                pack: PackService.State = .ready(.sideloaded), place: Place = AppSamples.politecnico,
                transit: [TransitPlan] = [], transitSelected: Bool = false) -> some View {
            let a = app(pack: pack, rideType: rideType)
            a.litStreetsOnly = lit
            let m = RouteOptionsModel(destination: place, state: state, transit: transit)
            m.whyExpanded = why
            m.transitSelected = transitSelected
            return RouteOptionsView(app: a, model: m, onClose: {}, onStart: { _, _, _ in }, onEditRules: {}, plansOnAppear: false)
        }
        check(s3(.options(AppSamples.options())), named: "S3a-bestFastest")
        check(s3(.options(AppSamples.options()), why: true), named: "S3b-why")
        check(s3(.options(AppSamples.options(single: true)),
                 place: Place(id: "c", name: "Milano Centrale", subtitle: "", kind: .station, lat: 45.4859, lon: 9.204)), named: "S3c-single")
        check(s3(.blocked(rule: .noCobbles, rideType: .cargo, closest: nil), rideType: .cargo,
                 place: Place(id: "d", name: "Piazza del Duomo", subtitle: "", kind: .poi, lat: 45.4641, lon: 9.1919)), named: "S3f-blocked")
        check(s3(.options(AppSamples.monzaOptions()), place: AppSamples.villaReale, transit: AppSamples.monzaTransit()),
              named: "S3d-transitRow")
        check(s3(.options(AppSamples.monzaOptions()), place: AppSamples.villaReale, transit: AppSamples.monzaTransit(), transitSelected: true),
              named: "S3e-transitCard")
        check(s3(.computing), named: "S3g-computing")
        check(s3(.options(AppSamples.options(lit: true)), lit: true), named: "S3h-lit")
        check(s3(.options(AppSamples.options(rideType: .cargo)), rideType: .cargo), named: "S3i-cargo")
        let mb = Int64(1_000_000)
        check(s3(.options(AppSamples.options()), pack: .downloading(received: 132 * mb, total: 220 * mb)), named: "S3-downloading")
    }

    // MARK: S4 Riding

    func testS4Riding() {
        func s4(_ name: String, at position: Double = 420, camera: RideCamera = RideCamera(),
                _ edit: (inout RideScreenState.Ride) -> Void = { _ in }) {
            var r = AppSamples.ride(at: position)
            edit(&r)
            r.chevron = camera.drawsRider
            let state = RideScreenState(r)
            let target = state.rider.map { camera.follow(at: $0, course: state.course) }
            check(RidingScreen(state: state, camera: camera, voice: .all, target: target), named: name, testName: "testS4Riding")
        }
        var threeD = RideCamera(); threeD.cycleView()
        var north = threeD; north.cycleView()
        var overview = RideCamera(); overview.toggleOverview(at: Date())
        var panned = north; panned.userPanned(at: Date())

        s4("S4a-2d")
        s4("S4b-3d", camera: threeD)
        s4("S4c-north", camera: north)
        s4("S4d-overview", camera: overview)
        s4("S4e-approaching", at: 545) { $0.turn?.meters = 40 }
        s4("S4f-avoided", at: 510) {
            $0.turn = RideTurn(maneuver: .left, meters: 50, street: "Via Paolo Mascagni", then: .init(maneuver: .right, street: "Via Sirtori"),
                               secondsLeft: 18 * 60, metersLeft: 4400)
        }
        s4("S4g-rerouting") { $0.rerouting = true }
        s4("S4h-weakGPS", at: 1100) {
            $0.gps = .weak
            $0.turn = RideTurn(maneuver: .slightRight, meters: 120, street: "Piazza Ascoli", then: .init(maneuver: .slightRight, street: "Via Pascoli"),
                               secondsLeft: 12 * 60, metersLeft: 2900)
        }
        s4("S4i-arriving", at: 1740) { $0.arriving = true }
        s4("S4j-panned", camera: panned)
    }

    // MARK: S5 Riding with transit (P6 copy; P6's illustrative 08:16 train)

    func testS5RidingWithTransit() {
        func s5(_ name: String, at position: Double = 420, _ edit: (inout RideScreenState) -> Void) {
            var r = AppSamples.ride(at: position)
            r.chevron = true
            var state = RideScreenState(r)
            edit(&state)
            let camera = RideCamera()
            let target = state.rider.map { camera.follow(at: $0, course: state.course) }
            check(RidingScreen(state: state, camera: camera, voice: .all, target: target), named: name, testName: "testS5RidingWithTransit")
        }
        s5("S5a-timeToSpare") {
            $0.stage = StageStrip(current: 1)
            $0.eta = .transit(arrival: "08:12", at: "Centrale", train: "08:16 ·", spare: "4 min to spare", tight: false)
        }
        s5("S5b-late") {
            $0.stage = StageStrip(current: 1)
            $0.notice = .init(kind: .late, title: "Running late",
                              message: "Switched to the fastest route to catch the 08:16. It adds 120 m of cobbles.")
            $0.eta = .transit(arrival: "08:14", at: "Centrale", train: "08:16 ·", spare: "2 min to spare", tight: true)
        }
        s5("S5c-missed") {
            $0.stage = StageStrip(current: 1)
            $0.notice = .init(kind: .missed, title: "You’d miss the 08:16", message: "Moved you to the 08:46. Arrival 09:05.")
            $0.eta = .transit(arrival: "08:19", at: "Centrale", train: "08:46 ·", spare: "27 min to spare", tight: false)
        }
        s5("S5d-onTrain") {
            $0.stage = StageStrip(current: 2)
            $0.onTrain = OnTrainCard.sample
        }
        s5("S5e-rideOn", at: 1200) { $0.stage = StageStrip(current: 3) }
    }

    // MARK: S7 Routes

    /// P7's four routes (design/tools/p7gen.js `RT`), as the pack would give them.
    static let p7Routes: [CycleRoute] = {
        func r(_ id: Int64, _ kind: CycleRoute.Kind, _ network: String, _ name: String, ev: Int? = nil, km: Double,
               mix: CycleRoute.Mix, climb: Double, description: String = "", from: String = "", to: String = "") -> CycleRoute {
            let a = LatLon(lat: 45.45 + Double(id) * 0.01, lon: 9.15), b = LatLon(lat: 45.30 + Double(id) * 0.01, lon: 9.16)
            return CycleRoute(id: id, kind: kind, network: network, name: name, ref: "", eurovelo: ev, meters: km * 1000,
                              pavedShare: 1 - mix.unpaved, mix: mix, climb: climb, descent: climb, description: description,
                              from: from, to: to, line: [a, b], pieces: [[a, b]])
        }
        return [
            r(1, .bicycle, "icn", "Alzaia Naviglio Pavese", ev: 5, km: 33, mix: .init(carFree: 0.62, quiet: 0.08, unpaved: 0.30), climb: 40,
              description: "Flat towpath from the Darsena to Pavia, on EuroVelo 5. Mostly car-free; the last third is packed gravel.",
              from: "the Darsena", to: "Pavia"),
            r(2, .bicycle, "rcn", "Naviglio Martesana", km: 38, mix: .init(carFree: 0.85, quiet: 0.10, unpaved: 0.05), climb: 60,
              from: "Milano", to: "Cassano d’Adda"),
            r(3, .mtb, "", "Groane MTB trails", km: 14, mix: .init(carFree: 0.2, quiet: 0.1, unpaved: 0.7), climb: 120,
              description: "Heath and woods, short steep pitches"),
            r(4, .bicycle, "lcn", "Parco Nord loop", km: 9, mix: .init(carFree: 1, quiet: 0, unpaved: 0), climb: 15,
              description: "Paved park loop, no cars"),
        ]
    }()

    private func routes(_ setup: (RoutesModel) -> Void, rideType: RideType = .gravel) -> some View {
        let a = app(rideType: rideType)
        let m = RoutesModel(rideType: rideType, home: .init(center: portaVenezia, name: "Milan"))
        m.show(Self.p7Routes, area: .init(center: portaVenezia, name: "Milan"))
        setup(m)
        return ZStack(alignment: .bottom) {
            RoutesView(app: a, model: m, sheet: .constant(nil), loadsOnAppear: false)
                .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 44) }
            VStack(spacing: 0) { Spacer(minLength: 0); TabBar(selected: .routes) { _ in } }.ignoresSafeArea(edges: .bottom)
        }
    }

    func testS7Routes() {
        check(routes { _ in }, named: "S7a-fitsGravel")
        check(routes { $0.filterIndex = 1; $0.tapped(4) }, named: "S7b-all")
        check(routes { $0.select(1) }, named: "S7c-selected")
        check(routes { $0.mapMoved(to: LatLon(lat: 45.98, lon: 9.26), name: "Lake Como") }, named: "S7e-searched")
        check(routes { m in
            m.show(Array(Self.p7Routes.prefix(2)), area: .init(center: LatLon(lat: 45.98, lon: 9.26), name: "Lake Como"))
            m.filterIndex = 4
        }, named: "S7f-noRoutes")
        check(routes { m in
            m.load(store: nil, inside: { _ in false })
            m.search(.init(center: LatLon(lat: 46.0037, lon: 8.9511), name: "Lugano"))
        }, named: "S7g-outside")
        let route = Self.p7Routes[0]
        let leg = RouteRide.Leg(line: route.line, from: route.from, to: route.to, reversed: false)
        let option = AppSamples.rideOption()
        let m = RouteOptionsModel(follow: route, state: .options(RouteOptionsModel.followOptions(option, rules: .defaults(for: .gravel), leg: leg,
                                                                                                    approachMeters: 3800)),
                                  approachMeters: 3800, leg: leg)
        check(RouteOptionsView(app: app(rideType: .gravel), model: m, onClose: {}, onStart: { _, _, _ in }, onEditRules: {},
                               plansOnAppear: false), named: "S7d-rideThisRoute")
    }

    // MARK: S6 Ride summary

    func testS6Summary() {
        let model = RideSummaryModel(arrived: Calendar.current.date(bySettingHour: 8, minute: 42, second: 0, of: Date(timeIntervalSince1970: 1_791_000_000))!,
                                     place: "Politecnico", rideType: .city, option: "Calmest for city", meters: 5400,
                                     movingSeconds: 21 * 60, climb: 8, track: AppSamples.rideOption().analysis.shape,
                                     gpx: URL(fileURLWithPath: "/tmp/ride.gpx"))
        check(RideSummaryView(model: model, connections: .synced), named: "S6a-synced")
        check(RideSummaryView(model: model), named: "S6b-notConnected")
        check(RideSummaryView(model: model, connections: .synced, issue: RideSummary.sampleIssue), named: "S6c-dataIssue")
    }

    // MARK: S8 You

    func testS8You() {
        check(YouView(app: app()), named: "S8a-you")
        check(YouView(app: app(rides: true), now: Self.ridesNow).defaultScrollAnchor(.bottom), named: "S8a-you-rides")
        check(RideHistoryView(history: app(rides: true).history, now: Self.ridesNow), named: "S8b-allRides")
    }
}
