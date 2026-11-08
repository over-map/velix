import Foundation
import Testing
@testable import Velix

/// M10 severe-weather notice: the MeteoAlarm feed, which warnings show, region matching and the notice copy.
@Suite struct WeatherTests {
    private final class Token {}
    static let rome = TimeZone(identifier: "Europe/Rome")!
    static let milan = LatLon(lat: 45.4642, lon: 9.1900)
    static let lombardy = WeatherPlace(region: "Lombardia", regionName: "Lombardy", city: "Milan", countryCode: "IT")

    /// Sunday 8 Nov 2026 at hh:mm, Rome time.
    static func nov8(_ h: Int, _ m: Int = 0, day: Int = 8) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = rome
        return c.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m))!
    }

    static func entry(_ area: String = "Lombardia", event: String = "Orange Thunderstorm Warning", severity: String = "Severe",
                      onset: Date = nov8(14), expires: Date = nov8(18), sent: Date = nov8(14, 5),
                      id: String = "a", status: String = "Actual", type: String = "Alert") -> MeteoAlarmFeed.Item {
        .init(identifier: id, areaDesc: area, geocode: "IT003", event: event, severity: severity, onset: onset,
              expires: expires, sent: sent, status: status, messageType: type)
    }

    // MARK: Parsing

    @Test func parsesTheRealItalyFeed() throws {
        let url = try #require(Bundle(for: Token.self).url(forResource: "meteoalarm-italy", withExtension: "xml"))
        let entries = MeteoAlarmFeed.parse(try Data(contentsOf: url))
        #expect(entries.count == 11)
        let puglia = try #require(entries.first)
        #expect(puglia.areaDesc == "Puglia")
        #expect(puglia.geocode == "IT015")
        #expect(puglia.event == "Yellow Fog Warning")
        #expect(puglia.severity == "Moderate")
        #expect(puglia.status == "Actual")
        #expect(puglia.messageType == "Alert")
        #expect(puglia.identifier == "2.49.0.0.380.3.IT.261108102502.007")
        #expect(puglia.onset == ISO8601DateFormatter().date(from: "2026-11-09T18:00:00Z"))
        #expect(puglia.expires == ISO8601DateFormatter().date(from: "2026-11-10T06:59:00Z"))
        #expect(puglia.sent == ISO8601DateFormatter().date(from: "2026-11-08T09:25:03Z"))
        #expect(entries.contains { $0.areaDesc == "Emilia e Romagna" })
    }

    @Test func todaysFeedIsAllYellowSoNoNotice() throws {
        let url = try #require(Bundle(for: Token.self).url(forResource: "meteoalarm-italy", withExtension: "xml"))
        let entries = MeteoAlarmFeed.parse(try Data(contentsOf: url))
        #expect(MeteoAlarm.pick(entries, region: "Lombardia", now: Self.nov8(22)) == nil)
    }

    @Test func builtFeedRoundTrips() {
        let items = [Self.entry(), Self.entry("Veneto", id: "b")]
        #expect(MeteoAlarmFeed.parse(MeteoAlarmFeed.xml(items)) == items)
    }

    @Test func brokenXMLGivesNothing() {
        #expect(MeteoAlarmFeed.parse(Data("<feed><entry><cap:areaDesc>Lomb".utf8)).isEmpty)
    }

    // MARK: Which warning shows

    @Test func onlyOrangeAndRed() {
        let now = Self.nov8(15)
        #expect(MeteoAlarm.pick([Self.entry(severity: "Moderate")], region: "Lombardia", now: now) == nil)
        #expect(MeteoAlarm.pick([Self.entry(severity: "Minor")], region: "Lombardia", now: now) == nil)
        #expect(MeteoAlarm.pick([Self.entry(severity: "Severe")], region: "Lombardia", now: now) != nil)
        #expect(MeteoAlarm.pick([Self.entry(severity: "Extreme")], region: "Lombardia", now: now) != nil)
    }

    @Test func activeNowOrWithin12Hours() {
        #expect(MeteoAlarm.pick([Self.entry()], region: "Lombardia", now: Self.nov8(18, 1)) == nil)        // expired
        #expect(MeteoAlarm.pick([Self.entry()], region: "Lombardia", now: Self.nov8(2)) != nil)            // in 12 h
        #expect(MeteoAlarm.pick([Self.entry()], region: "Lombardia", now: Self.nov8(1, 59)) == nil)        // further out
    }

    @Test func cancelledTestsAndAvalanchesDontShow() {
        let now = Self.nov8(15)
        #expect(MeteoAlarm.pick([Self.entry(type: "Cancel")], region: "Lombardia", now: now) == nil)
        #expect(MeteoAlarm.pick([Self.entry(status: "Test")], region: "Lombardia", now: now) == nil)
        #expect(MeteoAlarm.pick([Self.entry(event: "Red Avalanches Warning", severity: "Extreme")],
                                region: "Lombardia", now: now) == nil)
        #expect(MeteoAlarm.pick([Self.entry(type: "Update")], region: "Lombardia", now: now) != nil)
    }

    @Test func onlyTheRidersRegion() {
        #expect(MeteoAlarm.pick([Self.entry("Veneto")], region: "Lombardia", now: Self.nov8(15)) == nil)
    }

    @Test func mostSevereThenSoonest() {
        let now = Self.nov8(15)
        let orangeNow = Self.entry(id: "orange-now")
        let orangeLater = Self.entry(onset: Self.nov8(20), expires: Self.nov8(23), id: "orange-later")
        let redLater = Self.entry(event: "Red Wind Warning", severity: "Extreme", onset: Self.nov8(21), expires: Self.nov8(23),
                                  id: "red-later")
        #expect(MeteoAlarm.pick([orangeLater, orangeNow], region: "Lombardia", now: now)?.identifier == "orange-now")
        #expect(MeteoAlarm.pick([orangeLater, orangeNow, redLater], region: "Lombardia", now: now)?.identifier == "red-later")
    }

    // MARK: Region names (Photon's `state` with lang=default vs the feed's areaDesc)

    @Test(arguments: [
        ("Emilia-Romagna", "Emilia e Romagna"),
        ("Lombardia", "Lombardia"),
        ("Friuli Venezia Giulia", "Friuli Venezia Giulia"),
        ("Friuli-Venezia Giulia", "Friuli Venezia Giulia"),
        ("Valle d'Aosta", "Valle d'Aosta"),
        ("Valle d'Aosta / Vallée d'Aoste", "Valle d'Aosta"),
        ("Valle d’Aosta", "Valle d'Aosta"),
        ("Trentino-Alto Adige/Südtirol", "Trentino-Alto Adige"),
        ("Trentino-Alto Adige/Südtirol", "Trentino Alto Adige"),
    ])
    func regionNamesMatch(photon: String, feed: String) {
        #expect(MeteoAlarm.normalized(photon) == MeteoAlarm.normalized(feed))
    }

    @Test func everyItalianRegionInTheFeedMatchesItself() {
        let feed = ["Abruzzo", "Basilicata", "Calabria", "Campania", "Emilia e Romagna", "Friuli Venezia Giulia", "Lazio",
                    "Liguria", "Lombardia", "Marche", "Molise", "Piemonte", "Puglia", "Sardegna", "Sicilia", "Toscana",
                    "Umbria", "Veneto"]
        let keys = feed.map(MeteoAlarm.normalized)
        #expect(Set(keys).count == feed.count)       // no two regions collapse into one
        #expect(MeteoAlarm.normalized("Emilia-Romagna") == MeteoAlarm.normalized("Emilia e Romagna"))
        #expect(MeteoAlarm.normalized("Lombardia") != MeteoAlarm.normalized("Liguria"))
    }

    @Test func photonReverseGivesTheRegion() {
        let json = #"""
        {"features":[{"geometry":{"coordinates":[9.19,45.44],"type":"Point"},"type":"Feature",
         "properties":{"osm_id":42,"extent":[9.1,45.5,9.2,45.4],"housenumber":"20","street":"Via Soave","city":"Milano",
         "county":"Milano","state":"Lombardia","country":"Italia","countrycode":"IT","type":"house"}}],"type":"FeatureCollection"}
        """#
        let p = PhotonPlaceLookup.parse(Data(json.utf8))
        #expect(p?["state"] == "Lombardia")
        #expect(p?["countrycode"] == "IT")
        #expect(p?["city"] == "Milano")
        #expect(PhotonPlaceLookup.parse(Data(#"{"features":[]}"#.utf8)) == nil)
    }

    // MARK: Copy

    @Test func designCopyForAThunderstormNow() {
        let w = MeteoAlarm.warning(Self.entry(), place: Self.lombardy, issuer: "Aeronautica Militare", now: Self.nov8(15),
                                   timeZone: Self.rome)
        #expect(w.title == "Severe weather in Milan")
        #expect(w.message == "Thunderstorms until 18:00. Take care if you ride.")
        #expect(w.pill == "Storm until 18:00")
        #expect(w.credit == "Issued 14:05 by Aeronautica Militare via MeteoAlarm")
        #expect(w.link == URL(string: "https://meteoalarm.org?geocode=EMMA_ID:IT003"))
        #expect(w.id == "a")
        #expect(w.expires == Self.nov8(18))
    }

    @Test func startingLater() {
        let e = Self.entry(event: "Orange Wind Warning", onset: Self.nov8(20), expires: Self.nov8(23, 30))
        let w = MeteoAlarm.warning(e, place: Self.lombardy, issuer: "Aeronautica Militare", now: Self.nov8(15), timeZone: Self.rome)
        #expect(w.message == "Strong wind from 20:00 to 23:30. Take care if you ride.")
        #expect(w.pill == "Wind from 20:00")
    }

    @Test func endingAnotherDay() {
        let e = Self.entry(event: "Red Rain Warning", severity: "Extreme", onset: Self.nov8(12), expires: Self.nov8(7, day: 9),
                           sent: Self.nov8(9, 25, day: 7))
        let w = MeteoAlarm.warning(e, place: Self.lombardy, issuer: "Aeronautica Militare", now: Self.nov8(15), timeZone: Self.rome)
        #expect(w.message == "Heavy rain until tomorrow 07:00. Take care if you ride.")
        #expect(w.pill == "Rain until tomorrow 07:00")
        #expect(w.credit == "Issued yesterday 09:25 by Aeronautica Militare via MeteoAlarm")
        let far = Self.entry(onset: Self.nov8(12), expires: Self.nov8(7, day: 10))
        #expect(MeteoAlarm.warning(far, place: Self.lombardy, issuer: "X", now: Self.nov8(15), timeZone: Self.rome).message
                == "Thunderstorms until Tue 07:00. Take care if you ride.")
    }

    @Test func startingTomorrowMorning() {
        let e = Self.entry(event: "Orange Snow-Ice Warning", onset: Self.nov8(6, day: 9), expires: Self.nov8(18, day: 9))
        let w = MeteoAlarm.warning(e, place: Self.lombardy, issuer: "X", now: Self.nov8(22), timeZone: Self.rome)
        #expect(w.message == "Snow or ice from tomorrow 06:00 to 18:00. Take care if you ride.")
        #expect(w.pill == "Snow from tomorrow 06:00")
    }

    @Test func noCityNamesTheRegion() {
        let place = WeatherPlace(region: "Lombardia", regionName: "Lombardy", city: nil, countryCode: "IT")
        #expect(MeteoAlarm.warning(Self.entry(), place: place, issuer: "X", now: Self.nov8(15), timeZone: Self.rome).title
                == "Severe weather in Lombardy")
    }

    @Test(arguments: [
        ("Orange Thunderstorm Warning", "Thunderstorms", "Storm"),
        ("Orange Wind Warning", "Strong wind", "Wind"),
        ("Orange Rain Warning", "Heavy rain", "Rain"),
        ("Orange Rain-Flood Warning", "Flooding", "Flood"),
        ("Orange Flooding Warning", "Flooding", "Flood"),
        ("Orange Snow-Ice Warning", "Snow or ice", "Snow"),
        ("Orange Fog Warning", "Fog", "Fog"),
        ("Orange High-Temperature Warning", "Extreme heat", "Heat"),
        ("Orange Low-Temperature Warning", "Extreme cold", "Cold"),
        ("Orange Forest-Fire Warning", "Forest fire risk", "Fire"),
        ("Orange Coastal Event Warning", "Coastal storm", "Coast"),
        ("Orange Something New Warning", "Severe weather", "Weather"),
    ])
    func hazardWords(event: String, phrase: String, short: String) {
        let h = MeteoAlarm.Hazard(event: event)
        #expect(h.phrase == phrase)
        #expect(h.short == short)
    }

    // MARK: The source end to end (fetch, cache, place)

    actor Counter {
        var fetches = 0
        var urls: [URL] = []
        func hit(_ url: URL) { fetches += 1; urls.append(url) }
    }

    struct FixedPlace: WeatherPlaceLookup {
        var place: WeatherPlace?
        func place(at: LatLon) async -> WeatherPlace? { place }
    }

    final class Clock: @unchecked Sendable {
        var now: Date
        var offline = false
        init(_ now: Date) { self.now = now }
    }

    private func source(_ feed: Data, place: WeatherPlace? = lombardy, counter: Counter, clock: Clock) -> MeteoAlarm {
        MeteoAlarm(places: FixedPlace(place: place),
                   fetch: { url in
                       await counter.hit(url)
                       if clock.offline { throw URLError(.notConnectedToInternet) }
                       return feed
                   },
                   now: { clock.now }, timeZone: Self.rome)
    }

    @Test func currentWarningFromTheItalyFeed() async {
        let counter = Counter(), clock = Clock(Self.nov8(15))
        let w = await source(MeteoAlarmFeed.xml([Self.entry()]), counter: counter, clock: clock).current(near: Self.milan)
        #expect(w?.title == "Severe weather in Milan")
        #expect(await counter.urls == [URL(string: "https://feeds.meteoalarm.org/feeds/meteoalarm-legacy-atom-italy")!])
    }

    @Test func noLocationOrNoFeedForTheCountry() async {
        let counter = Counter(), clock = Clock(Self.nov8(15))
        let feed = MeteoAlarmFeed.xml([Self.entry()])
        #expect(await source(feed, counter: counter, clock: clock).current(near: nil) == nil)
        let swiss = WeatherPlace(region: "Ticino", regionName: "Ticino", city: "Lugano", countryCode: "CH")
        #expect(await source(feed, place: swiss, counter: counter, clock: clock).current(near: Self.milan) == nil)
        #expect(await counter.fetches == 0)
    }

    @Test func feedCachedFor15Minutes() async {
        let counter = Counter(), clock = Clock(Self.nov8(15))
        let s = source(MeteoAlarmFeed.xml([Self.entry()]), counter: counter, clock: clock)
        _ = await s.current(near: Self.milan)
        clock.now = Self.nov8(15, 14)
        _ = await s.current(near: Self.milan)
        #expect(await counter.fetches == 1)
        clock.now = Self.nov8(15, 16)
        _ = await s.current(near: Self.milan)
        #expect(await counter.fetches == 2)
    }

    @Test func offlineKeepsTheLastFeed() async {
        let counter = Counter(), clock = Clock(Self.nov8(15))
        let feed = MeteoAlarmFeed.xml([Self.entry()])
        clock.offline = true
        #expect(await source(feed, counter: counter, clock: clock).current(near: Self.milan) == nil)   // never fetched
        clock.offline = false
        let s = source(feed, counter: counter, clock: clock)
        #expect(await s.current(near: Self.milan) != nil)
        clock.offline = true
        clock.now = Self.nov8(16)                                   // cache stale, fetch fails: the last feed still counts
        #expect(await s.current(near: Self.milan) != nil)
        clock.now = Self.nov8(18, 30)                               // and its warning still ends on time
        #expect(await s.current(near: Self.milan) == nil)
    }

    @Test func debugFixturesShowANotice() async {
        for kind in ["orange", "red", "later"] {
            let now = Date()
            let s = MeteoAlarm(places: FixedPlace(place: Self.lombardy), fetch: { _ in MeteoAlarmFeed.debugFeed(kind, now: now) },
                               now: { now })
            #expect(await s.current(near: Self.milan) != nil, "\(kind)")
        }
    }
}
