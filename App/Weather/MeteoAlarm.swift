import Foundation

/// Where the rider is, in the words a weather feed uses: the region in its local name (matched to MeteoAlarm's
/// `areaDesc`), and in English with the city for the notice title.
struct WeatherPlace: Equatable, Sendable {
    var region: String          // "Lombardia" (Photon lang=default)
    var regionName: String      // "Lombardy" (lang=en)
    var city: String?           // "Milan"
    var countryCode: String     // "IT"
}

protocol WeatherPlaceLookup: Sendable {
    func place(at: LatLon) async -> WeatherPlace?
}

/// Severe-weather warnings from MeteoAlarm (EUMETNET; for Italy issued by Aeronautica Militare), M10.
/// One Atom feed per country, free and keyless, cached 15 minutes. Shows orange and red warnings for the rider's region
/// that are on now or start within 12 hours: the most severe, then the soonest. Terms (≈ CC BY 4.0) ask for the issuer,
/// the issue time, a link to meteoalarm.org and a "may be delayed" disclaimer (credit line + You → About).
struct MeteoAlarm: WeatherWarnings {
    struct Country: Sendable {
        let feed: String        // meteoalarm-legacy-atom-<feed>
        let issuer: String      // credited on the notice
    }

    /// Countries with a feed. Europe later (M11) is more rows here.
    static let countries: [String: Country] = ["IT": Country(feed: "italy", issuer: "Aeronautica Militare")]
    static let cacheFor: TimeInterval = 15 * 60
    static let lookAhead: TimeInterval = 12 * 3600

    let countries: [String: Country]
    let places: WeatherPlaceLookup
    let fetch: @Sendable (URL) async throws -> Data
    let now: @Sendable () -> Date
    let timeZone: TimeZone
    private let cache = Cache()

    init(countries: [String: Country] = MeteoAlarm.countries, places: WeatherPlaceLookup = PhotonPlaceLookup(),
         fetch: @escaping @Sendable (URL) async throws -> Data = { try await MeteoAlarm.download($0) },
         now: @escaping @Sendable () -> Date = { Date() }, timeZone: TimeZone = .current) {
        self.countries = countries
        self.places = places
        self.fetch = fetch
        self.now = now
        self.timeZone = timeZone
    }

    static func feedURL(_ country: Country) -> URL {
        URL(string: "https://feeds.meteoalarm.org/feeds/meteoalarm-legacy-atom-\(country.feed)")!
    }

    func current(near: LatLon?) async -> WeatherWarning? {
        guard let near, let place = await cache.place(near: near, lookup: places),
              let country = countries[place.countryCode],
              let data = await cache.feed(Self.feedURL(country), now: now(), fetch: fetch) else { return nil }
        let entries = MeteoAlarmFeed.parse(data)
        let pick = Self.pick(entries, region: place.region, now: now())
        NSLog("[weather] %d warnings in the %@ feed, %@: %@", entries.count, country.feed, place.region, pick?.event ?? "none")
        return pick.map { Self.warning($0, place: place, issuer: country.issuer, now: now(), timeZone: timeZone) }
    }

    // MARK: Which warning

    /// Orange (Severe) or red (Extreme), actual, not cancelled, for the region, on now or within 12 h; avalanche
    /// warnings left out (mountain slopes, not riding). The most severe first, then the soonest.
    static func pick(_ entries: [MeteoAlarmFeed.Item], region: String, now: Date) -> MeteoAlarmFeed.Item? {
        let key = normalized(region)
        return entries.filter { e in
            guard e.status == "Actual", e.messageType != "Cancel", e.level >= 3, Hazard(event: e.event) != .avalanche,
                  let end = e.expires, end > now, normalized(e.areaDesc) == key else { return false }
            return (e.onset ?? now) <= now.addingTimeInterval(lookAhead)
        }
        .min { a, b in
            a.level != b.level ? a.level > b.level : (a.onset ?? .distantPast) < (b.onset ?? .distantPast)
        }
    }

    /// Region names as both sides spell them: "Emilia-Romagna" = "Emilia e Romagna", "Trentino-Alto Adige/Südtirol" =
    /// "Trentino Alto Adige", "Valle d’Aosta / Vallée d'Aoste" = "Valle d'Aosta". Bilingual names keep the first part;
    /// case, accents, punctuation and the joining words "e", "d" and "and" don't count.
    static func normalized(_ name: String) -> String {
        let first = name.split(separator: "/").first.map(String.init) ?? name
        let folded = first.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !["e", "d", "and"].contains($0) }
            .joined(separator: " ")
    }

    // MARK: Copy

    /// What a warning is about, from its event ("Orange Thunderstorm Warning"): the message phrase and the pill word.
    enum Hazard: Equatable, Sendable {
        case storm, wind, rain, flood, snow, fog, heat, cold, fire, coast, avalanche, other

        init(event: String) {
            let e = event.lowercased()
            func has(_ words: String...) -> Bool { words.contains { e.contains($0) } }
            if has("avalanche") { self = .avalanche }
            else if has("thunderstorm") { self = .storm }
            else if has("flood") { self = .flood }
            else if has("wind") { self = .wind }
            else if has("snow", "ice") { self = .snow }
            else if has("fog") { self = .fog }
            else if has("high-temperature", "high temperature", "heat") { self = .heat }
            else if has("low-temperature", "low temperature", "cold") { self = .cold }
            else if has("fire") { self = .fire }
            else if has("coastal") { self = .coast }
            else if has("rain") { self = .rain }
            else { self = .other }
        }

        var phrase: String {
            switch self {
            case .storm: "Thunderstorms"
            case .wind: "Strong wind"
            case .rain: "Heavy rain"
            case .flood: "Flooding"
            case .snow: "Snow or ice"
            case .fog: "Fog"
            case .heat: "Extreme heat"
            case .cold: "Extreme cold"
            case .fire: "Forest fire risk"
            case .coast: "Coastal storm"
            case .avalanche: "Avalanches"
            case .other: "Severe weather"
            }
        }

        var short: String {
            switch self {
            case .storm: "Storm"
            case .wind: "Wind"
            case .rain: "Rain"
            case .flood: "Flood"
            case .snow: "Snow"
            case .fog: "Fog"
            case .heat: "Heat"
            case .cold: "Cold"
            case .fire: "Fire"
            case .coast: "Coast"
            case .avalanche: "Avalanche"
            case .other: "Weather"
            }
        }
    }

    /// P4 S1a: "Severe weather in Milan" / "Thunderstorms until 18:00. Take care if you ride." / "Storm until 18:00",
    /// and the credit the terms ask for: "Issued 14:05 by Aeronautica Militare via MeteoAlarm".
    static func warning(_ e: MeteoAlarmFeed.Item, place: WeatherPlace, issuer: String, now: Date,
                        timeZone: TimeZone) -> WeatherWarning {
        let clock = Clock(now: now, timeZone: timeZone)
        let hazard = Hazard(event: e.event)
        let end = e.expires ?? now
        let when: String, pillWhen: String
        if let start = e.onset, start > now {
            let from = clock.time(start, sameDayAs: now)
            when = "from \(from) to \(clock.time(end, sameDayAs: start))"
            pillWhen = "from \(from)"
        } else {
            when = "until \(clock.time(end, sameDayAs: now))"
            pillWhen = when
        }
        let credit = e.sent.map { "Issued \(clock.time($0, sameDayAs: now)) by \(issuer) via MeteoAlarm" }
            ?? "\(issuer) via MeteoAlarm"
        return WeatherWarning(title: "Severe weather in \(place.city ?? place.regionName)",
                              message: "\(hazard.phrase) \(when). Take care if you ride.",
                              pill: "\(hazard.short) \(pillWhen)",
                              id: e.identifier, credit: credit,
                              link: URL(string: "https://meteoalarm.org?geocode=EMMA_ID:\(e.geocode)"),
                              expires: e.expires)
    }

    /// "18:00" on the reference's day, else "tomorrow 07:00", "yesterday 09:25" or "Tue 07:00" (days counted from now).
    struct Clock {
        let now: Date
        let calendar: Calendar
        let hm: DateFormatter
        let weekday: DateFormatter

        init(now: Date, timeZone: TimeZone) {
            self.now = now
            var c = Calendar(identifier: .gregorian)
            c.timeZone = timeZone
            calendar = c
            func formatter(_ f: String) -> DateFormatter {
                let d = DateFormatter()
                d.locale = Locale(identifier: "en_US_POSIX")
                d.timeZone = timeZone
                d.dateFormat = f
                return d
            }
            hm = formatter("HH:mm")
            weekday = formatter("EEE")
        }

        func time(_ date: Date, sameDayAs reference: Date) -> String {
            let t = hm.string(from: date)
            if calendar.isDate(date, inSameDayAs: reference) { return t }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                               to: calendar.startOfDay(for: date)).day ?? 0
            switch days {
            case 1: return "tomorrow \(t)"
            case -1: return "yesterday \(t)"
            default: return "\(weekday.string(from: date)) \(t)"
            }
        }
    }

    // MARK: Network and cache

    static func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(PhotonSearch.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    /// The feed per URL for 15 minutes (one download at a time; offline, the last one, whose warnings still end on
    /// time), and the place until the rider moves 5 km.
    actor Cache {
        private var feeds: [URL: (at: Date, data: Data)] = [:]
        private var loading: [URL: Task<Data?, Never>] = [:]
        private var lastPlace: (at: LatLon, place: WeatherPlace)?

        func feed(_ url: URL, now: Date, fetch: @escaping @Sendable (URL) async throws -> Data) async -> Data? {
            if let cached = feeds[url], now.timeIntervalSince(cached.at) < MeteoAlarm.cacheFor { return cached.data }
            if let running = loading[url] { return await running.value }
            let task = Task { try? await fetch(url) }
            loading[url] = task
            let data = await task.value
            loading[url] = nil
            if let data { feeds[url] = (now, data) }
            return data ?? feeds[url]?.data
        }

        func place(near p: LatLon, lookup: WeatherPlaceLookup) async -> WeatherPlace? {
            if let last = lastPlace, Geo.distance(last.at, p) < 5_000 { return last.place }
            guard let place = await lookup.place(at: p) else { return lastPlace?.place }
            lastPlace = (p, place)
            return place
        }
    }
}

/// A MeteoAlarm legacy Atom feed: one `<entry>` per warning and area, with `cap:` fields.
enum MeteoAlarmFeed {
    struct Item: Equatable, Sendable {
        var identifier: String
        var areaDesc: String
        var geocode: String      // EMMA_ID, e.g. IT003
        var event: String        // "Orange Thunderstorm Warning"
        var severity: String     // Minor (green), Moderate (yellow), Severe (orange), Extreme (red)
        var onset: Date?         // `effective` when there's no onset
        var expires: Date?
        var sent: Date?
        var status: String       // Actual, Test, Exercise…
        var messageType: String  // Alert, Update, Cancel

        var level: Int { ["Minor": 1, "Moderate": 2, "Severe": 3, "Extreme": 4][severity] ?? 0 }
    }

    static func parse(_ data: Data) -> [Item] {
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        return parser.parse() ? reader.items : []
    }

    private final class Reader: NSObject, XMLParserDelegate {
        var items: [Item] = []
        private var fields: [String: String]?
        private var text = ""
        private let dates = ISO8601DateFormatter()

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            if name == "entry" { fields = [:] }
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            defer { text = "" }
            guard fields != nil else { return }
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if name == "entry" {
                if let f = fields, let item = item(f) { items.append(item) }
                fields = nil
            } else if name == "value" {
                fields?["value"] = value            // the EMMA_ID inside cap:geocode
            } else if name.hasPrefix("cap:"), !value.isEmpty {
                fields?[String(name.dropFirst(4))] = value
            }
        }

        private func item(_ f: [String: String]) -> Item? {
            guard let id = f["identifier"], let area = f["areaDesc"], let event = f["event"], let severity = f["severity"]
            else { return nil }
            let date = { (key: String) in f[key].flatMap { self.dates.date(from: $0) } }
            return Item(identifier: id, areaDesc: area, geocode: f["value"] ?? "", event: event, severity: severity,
                        onset: date("onset") ?? date("effective"), expires: date("expires"), sent: date("sent"),
                        status: f["status"] ?? "Actual", messageType: f["message_type"] ?? "Alert")
        }
    }

    #if DEBUG
    /// A feed in the legacy Atom shape, for tests and `-weather-fixture`.
    static func xml(_ items: [Item]) -> Data {
        let iso = ISO8601DateFormatter()
        func d(_ date: Date?) -> String { date.map { iso.string(from: $0) } ?? "" }
        let entries = items.map { i in
            """
              <entry>
                <cap:geocode><valueName>EMMA_ID</valueName><value>\(i.geocode)</value></cap:geocode>
                <cap:areaDesc>\(i.areaDesc)</cap:areaDesc>
                <cap:event>\(i.event)</cap:event>
                <cap:sent>\(d(i.sent))</cap:sent>
                <cap:expires>\(d(i.expires))</cap:expires>
                <cap:onset>\(d(i.onset))</cap:onset>
                <cap:severity>\(i.severity)</cap:severity>
                <cap:message_type>\(i.messageType)</cap:message_type>
                <cap:status>\(i.status)</cap:status>
                <cap:identifier>\(i.identifier)</cap:identifier>
              </entry>
            """
        }
        return Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <feed xmlns="http://www.w3.org/2005/Atom" xmlns:cap="urn:oasis:names:tc:emergency:cap:1.2">
            \(entries.joined(separator: "\n"))
            </feed>
            """.utf8)
    }

    /// `-weather-fixture orange|red|later`: a Lombardy warning around now, to see the notice while the live feed has
    /// none (orange: thunderstorms for 3 h; red: wind until tomorrow; later: heavy rain in 4 h).
    static func debugFeed(_ kind: String, now: Date) -> Data {
        let hour = TimeInterval(3600)
        let start = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / hour).rounded(.down) * hour)
        let item: Item = switch kind {
        case "red": Item(identifier: "debug-red", areaDesc: "Lombardia", geocode: "IT003", event: "Red Wind Warning",
                         severity: "Extreme", onset: start, expires: start + 20 * hour, sent: now - 1800,
                         status: "Actual", messageType: "Alert")
        case "later": Item(identifier: "debug-later", areaDesc: "Lombardia", geocode: "IT003", event: "Orange Rain Warning",
                           severity: "Severe", onset: start + 4 * hour, expires: start + 7 * hour, sent: now - 1800,
                           status: "Actual", messageType: "Alert")
        default: Item(identifier: "debug-orange", areaDesc: "Lombardia", geocode: "IT003",
                      event: "Orange Thunderstorm Warning", severity: "Severe", onset: start, expires: start + 3 * hour,
                      sent: now - 1800, status: "Actual", messageType: "Alert")
        }
        return xml([item])
    }
    #endif
}

extension MeteoAlarm {
    /// The app's source: the live feeds, or a fixture with `-weather-fixture <kind>` (debug builds).
    static func live() -> MeteoAlarm {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-weather-fixture"), i + 1 < args.count {
            let kind = args[i + 1]
            return MeteoAlarm(fetch: { _ in MeteoAlarmFeed.debugFeed(kind, now: Date()) })
        }
        #endif
        return MeteoAlarm()
    }
}
