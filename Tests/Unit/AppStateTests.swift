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

    @Test func olderStateFilesStillLoad() throws {
        // M6a wrote places without lineFamilies; a future field must not reset onboarding or Home / Work.
        let json = #"{"onboarded":true,"rideType":"city","rules":[],"recents":[],"work":{"id":"N1","kind":"address","lat":45.47,"lines":[],"lon":9.22,"name":"Politecnico","subtitle":"Piazza Leonardo da Vinci"},"futureField":1}"#
        let url = dir.appending(path: "old.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)
        let s = AppStore(url: url).load()
        #expect(s.onboarded)
        #expect(s.work?.name == "Politecnico")
        #expect(s.packAutoUpdate)
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
        #expect(city.active == [.bikeLanesOnly, .noWalking, .litStreetsOnly])
    }

    @Test func oneWaysAreIgnoredUnlessRespected() throws {
        var s = AppState()
        let city = try RideProfile.load(.city)
        let free = city.adjusted(for: s.ruleSet(for: .city))
        #expect(free.best.costingOptions["ignore_oneways"] == .bool(true))
        #expect(free.fastest.costingOptions["ignore_oneways"] == .bool(true))
        s.respectOneways = true
        let strict = city.adjusted(for: s.ruleSet(for: .city))
        #expect(strict.best.costingOptions["ignore_oneways"] == nil)
        #expect(strict.fastest.costingOptions["ignore_oneways"] == nil)
    }

    @Test func walkingStretchesAreACityRuleOffByDefault() {
        var s = AppState()
        #expect(s.ruleSet(for: .city).active.contains(.noWalking))
        #expect(!s.ruleSet(for: .city).active.contains(.walkingStretches))
        s.rules[.city] = RuleSet.defaults(for: .city).enabled.union([.walkingStretches])
        #expect(!s.ruleSet(for: .city).active.contains(.noWalking))
        #expect(s.ruleSet(for: .city, litStreetsOnly: true).active.last == .litStreetsOnly)
        #expect(s.ruleSet(for: .road).active.contains(.noWalking))
        #expect(RideType.road.ruleDefaults.contains { $0.0 == .bikeLanesOnly && !$0.1 })
    }

    /// Filippo, 5 Nov: tap a POI or station on the map and route to it.
    @Test func tappedFeaturesBecomePlaces() throws {
        let at = LatLon(lat: 45.45, lon: 9.16)
        let cafe = try #require(MapFeaturePlace.place(attributes: ["name": "Bar Magenta", "class": "cafe", "subclass": "cafe", "id": NSNumber(value: 42)], at: at))
        #expect(cafe.kind == .poi && cafe.subtitle == "Café" && cafe.id == "tap-42" && cafe.lat == 45.45)
        let bikes = try #require(MapFeaturePlace.place(attributes: ["name": "Rossignoli", "class": "shop", "subclass": "bicycle"], at: at))
        #expect(bikes.subtitle == "Bike shop" && bikes.id.hasPrefix("tap-45.45"))
        let park = try #require(MapFeaturePlace.place(attributes: ["name": "Parco Sempione", "class": "park", "subclass": "park"], at: at))
        #expect(park.kind == .park && park.subtitle == "Park")
        let rail = try #require(MapFeaturePlace.place(attributes: ["name": "Porta Nuova", "mode": "train"], at: at))
        #expect(rail.kind == .station && rail.subtitle == "Railway station")
        let metro = try #require(MapFeaturePlace.place(attributes: ["name": "Loreto", "mode": "metro", "tiles": "M1.red.0,M2.green.0"], at: at))
        #expect(metro.kind == .metro && metro.lines == ["M1", "M2"] && metro.lineFamilies == ["red", "green"])
        // Online tiles have no velix_stations: OpenMapTiles' railway POIs.
        let online = try #require(MapFeaturePlace.place(attributes: ["name": "Gare de Lyon", "class": "railway", "subclass": "station"], at: at))
        #expect(online.kind == .station)
        #expect(MapFeaturePlace.place(attributes: ["class": "cafe"], at: at) == nil)    // no name: nothing to route to
        #expect(PoiCategory.name("ice_rink") == "Ice rink" && PoiCategory.name("yes") == nil)
    }

    @Test func photonPOIsSayWhatTheyAre() throws {
        let json = #"""
        {"features":[{"geometry":{"coordinates":[9.17,45.45]},"properties":{"osm_id":7,"osm_type":"N","osm_key":"shop",
         "osm_value":"bicycle","type":"house","name":"Cicli Rossignoli","street":"Corso Garibaldi","housenumber":"71",
         "city":"Milano"}}]}
        """#
        let places = try PhotonSearch.parse(Data(json.utf8))
        #expect(places.first?.subtitle == "Bike shop · Corso Garibaldi 71 · Milano")
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
        // A café with a house number is a POI (Filippo, 5 Nov: search a POI); a plain house is an address.
        #expect(PhotonSearch.kind(key: "amenity", value: "cafe", type: "house") == .poi)
        #expect(PhotonSearch.kind(key: "building", value: "yes", type: "house") == .address)
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

/// P8: VoiceOver labels are written to be heard (units spelled out, the decision first).
@MainActor
struct SpokenLabelTests {
    @Test func unitsAreSpelledOut() {
        #expect(Format.spoken("0.3 km") == "0.3 kilometres")
        #expect(Format.spoken("Tram rails in 160 m") == "Tram rails in 160 metres")
        #expect(Format.spoken("5 min slower: 300 m of cobbles") == "5 minutes slower: 300 metres of cobbles")
        #expect(Format.spoken("132 of 220 MB") == "132 of 220 megabytes")
        #expect(Format.spoken("Via Morgagni") == "Via Morgagni")   // no unit, no change
    }

    @Test func maneuversAreAnnouncedAt100And30Metres() {
        #expect(ManeuverBanner.band(450) == nil)
        #expect(ManeuverBanner.band(100) == 100)
        #expect(ManeuverBanner.band(64) == 100)
        #expect(ManeuverBanner.band(30) == 30)
        #expect(ManeuverBanner.band(4) == 30)
    }

    @Test func aRouteCardReadsAsOneSentence() {
        let card = RouteCard.Model(name: "Calmest for city", distance: "5.4 km", minutes: 23,
                                   mix: [.protected: 0.6, .quiet: 0.3, .mixed: 0.1],
                                   line: "**5 min slower** than fastest: avoids 300 m of cobbles", selected: true)
        #expect(card.spoken == "Calmest for city. 23 minutes, 5.4 kilometres. 5 minutes slower than fastest: avoids 300 metres of cobbles. "
                + "Mostly protected lanes, then quiet streets.")
        #expect(ComfortMixBar.spokenSummary([.quiet: 0.4, .painted: 0.35, .cobbles: 0.25]) == "Quiet streets and painted lanes.")
        #expect(ComfortMixBar.spokenSummary([:]) == nil)
    }

    @Test func aHazardRowCountsAndNamesThePlaces() {
        let h = WhyThisRoute.Hazard(type: .tram, subtitle: "Piazza Oberdan, Via Melzo", count: 4)
        #expect(h.spoken == "Tram rails crossing, 4 on your route: Piazza Oberdan, Via Melzo")
        #expect(WhyThisRoute.Hazard(type: .cobbles, subtitle: "Via Pascoli", amount: "70 m").spoken == "Cobbles, 70 metres: Via Pascoli")
    }
}
