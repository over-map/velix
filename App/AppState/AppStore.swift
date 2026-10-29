import Foundation

/// What Velix remembers between launches (Application Support/state.json). Rides are in SwiftData (``RideHistory``).
struct AppState: Codable, Equatable, Sendable {
    var onboarded = false
    var rideType: RideType = .city
    /// Rule switches per ride type; a type not listed uses its defaults.
    var rules: [RideType: Set<Rule>] = [:]
    var home: Place?
    var work: Place?
    /// Newest first.
    var recents: [Place] = []
    var packAutoUpdate = true
    /// You → Routing: follow one-way restrictions (default off, Filippo 18 Oct).
    var respectOneways = false

    init() {}

    /// Every field is optional in stored state: a newer app reads an older file without losing it.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? false
        rideType = (try? c.decode(RideType.self, forKey: .rideType)) ?? .city
        rules = (try? c.decode([RideType: Set<Rule>].self, forKey: .rules)) ?? [:]
        home = try? c.decode(Place.self, forKey: .home)
        work = try? c.decode(Place.self, forKey: .work)
        recents = (try? c.decode([Place].self, forKey: .recents)) ?? []
        packAutoUpdate = try c.decodeIfPresent(Bool.self, forKey: .packAutoUpdate) ?? true
        respectOneways = try c.decodeIfPresent(Bool.self, forKey: .respectOneways) ?? false
    }

    static let recentsKept = 20
    static let recentsShown = 5

    func ruleSet(for type: RideType, litStreetsOnly: Bool = false) -> RuleSet {
        var set = RuleSet.defaults(for: type)
        if let enabled = rules[type] { set.enabled = enabled }
        set.litStreetsOnly = litStreetsOnly
        set.respectOneways = respectOneways
        return set
    }

    mutating func addRecent(_ place: Place) {
        recents.removeAll { $0.isSame(as: place) }
        recents.insert(place, at: 0)
        if recents.count > Self.recentsKept { recents.removeLast(recents.count - Self.recentsKept) }
    }
}

/// Loads and saves ``AppState`` as JSON; a missing or unreadable file starts fresh.
struct AppStore: Sendable {
    let url: URL

    static let live = AppStore(url: URL.applicationSupportDirectory.appending(path: "state.json"))

    func load() -> AppState {
        guard let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(AppState.self, from: data) else {
            return AppState()
        }
        return s
    }

    func save(_ state: AppState) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys]
            try enc.encode(state).write(to: url, options: .atomic)
        } catch {
            print("AppStore: \(error)")
        }
    }
}
