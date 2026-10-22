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
                     rideType: RideType = .city, weather: WeatherWarnings = NoWeatherWarnings()) -> AppModel {
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
        return AppModel(store: store, location: location, pack: packService, search: NoSearch(), weather: weather,
                        mapPreference: prefs)
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
                pack: PackService.State = .ready(.sideloaded), place: Place = AppSamples.politecnico) -> some View {
            let a = app(pack: pack, rideType: rideType)
            a.litStreetsOnly = lit
            let m = RouteOptionsModel(destination: place, state: state)
            m.whyExpanded = why
            return RouteOptionsView(app: a, model: m, onClose: {}, onStart: { _, _, _ in }, onEditRules: {}, plansOnAppear: false)
        }
        check(s3(.options(AppSamples.options())), named: "S3a-bestFastest")
        check(s3(.options(AppSamples.options()), why: true), named: "S3b-why")
        check(s3(.options(AppSamples.options(single: true)),
                 place: Place(id: "c", name: "Milano Centrale", subtitle: "", kind: .station, lat: 45.4859, lon: 9.204)), named: "S3c-single")
        check(s3(.blocked(rule: .noCobbles, rideType: .cargo, closest: nil), rideType: .cargo,
                 place: Place(id: "d", name: "Piazza del Duomo", subtitle: "", kind: .poi, lat: 45.4641, lon: 9.1919)), named: "S3f-blocked")
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
    }
}
