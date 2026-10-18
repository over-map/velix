import Foundation

/// What Velix remembers between launches (Application Support/state.json). Rides come with SwiftData in M9.
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

    static let recentsKept = 20
    static let recentsShown = 5

    func ruleSet(for type: RideType, litStreetsOnly: Bool = false) -> RuleSet {
        var set = RuleSet.defaults(for: type)
        if let enabled = rules[type] { set.enabled = enabled }
        set.litStreetsOnly = litStreetsOnly
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
