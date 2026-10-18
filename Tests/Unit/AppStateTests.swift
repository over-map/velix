import Foundation
import Testing
@testable import Velix

private final class Token {}

struct AppStateTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "velix-state-\(UUID().uuidString)")

    @Test func storeRoundTrips() {
        let store = AppStore(url: dir.appending(path: "state.json"))
        #expect(store.load() == AppState())          // missing file: fresh state
        var s = AppState()
        s.onboarded = true
        s.rideType = .gravel
        s.rules[.city] = [.noCobbles]
        s.work = AppSamples.work
        s.addRecent(AppSamples.recents[0])
        store.save(s)
        #expect(store.load() == s)
    }

    @Test func recentsDedupeAndCap() {
        var s = AppState()
        for i in 0 ..< 30 {
            s.addRecent(Place(id: "p\(i)", name: "Place \(i)", subtitle: "", kind: .poi, lat: 45 + Double(i) * 0.01, lon: 9))
        }
        #expect(s.recents.count == AppState.recentsKept)
        #expect(s.recents.first?.id == "p29")
        // Same name within 50 m counts as the same place and moves to the top.
        s.addRecent(Place(id: "other", name: "Place 10", subtitle: "", kind: .poi, lat: 45.1000, lon: 9.0002))
        #expect(s.recents.first?.id == "other")
        #expect(s.recents.filter { $0.name == "Place 10" }.count == 1)
    }

    @Test func rulesPerTypeFallBackToDefaults() {
        var s = AppState()
        #expect(s.ruleSet(for: .cargo) == RuleSet.defaults(for: .cargo))
        s.rules[.city] = [.bikeLanesOnly]
        let city = s.ruleSet(for: .city, litStreetsOnly: true)
        #expect(city.enabled == [.bikeLanesOnly])
        #expect(city.active == [.bikeLanesOnly, .litStreetsOnly])
    }

    @Test func photonResultsParse() throws {
        let url = try #require(Bundle(for: Token.self).url(forResource: "photon-centr", withExtension: "json"))
        let places = try PhotonSearch.parse(Data(contentsOf: url))
        #expect(!places.isEmpty)
        let centrale = try #require(places.first { $0.name == "Centrale FS" })
        #expect(centrale.kind == .station)
        #expect(centrale.subtitle.hasPrefix("Railway station"))
        #expect(places.filter { $0.name == "Centrale FS" }.count <= 2)
        #expect(places.allSatisfy { $0.lat > 44 && $0.lat < 47 })
    }

    @Test func photonKinds() {
        #expect(PhotonSearch.kind(key: "railway", value: "station", type: "house") == .station)
        #expect(PhotonSearch.kind(key: "highway", value: "residential", type: "street") == .street)
        #expect(PhotonSearch.kind(key: "leisure", value: "park", type: nil) == .park)
        #expect(PhotonSearch.kind(key: "amenity", value: "cafe", type: "house") == .address)
    }

    @Test func regionBoxContainsMilanNotRome() {
        #expect(RegionPackManifest.sideloaded.contains(LatLon(lat: 45.4746, lon: 9.2050)))
        #expect(!RegionPackManifest.sideloaded.contains(LatLon(lat: 41.9, lon: 12.5)))
    }

    @Test func formats() {
        #expect(Format.km(320) == "0.3 km")
        #expect(Format.km(5400) == "5.4 km")
        #expect(Format.km(14_200) == "14 km")
        #expect(Format.megabytes(132_000_000, of: 220_000_000) == "132 of 220 MB")
    }
}
