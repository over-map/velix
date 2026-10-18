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
                     rideType: RideType = .city) -> AppModel {
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
        return AppModel(store: store, location: location, pack: packService, search: NoSearch(), mapPreference: prefs)
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
        let weather = app()
        weather.warning = AppSamples.storm
        check(RootView(app: weather), named: "S1a-weather")
        let panned = app()
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
}
