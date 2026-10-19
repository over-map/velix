import Foundation

/// The six ride types (BRIEF §8). Each has its own "best" and its own rules (edited in You).
enum RideType: String, CaseIterable, Codable, Sendable {
    case city, ebike, road, gravel, mtb, cargo

    /// Copy from design/tools/p4gen.js and p7gen.js.
    var name: String {
        switch self {
        case .city: "City"
        case .ebike: "E-bike"
        case .road: "Road"
        case .gravel: "Gravel"
        case .mtb: "MTB"
        case .cargo: "Cargo / kids"
        }
    }

    /// Name of the Best route card for this ride type.
    var bestName: String {
        switch self {
        case .city: "Calmest for city"
        case .ebike: "Best for e-bike"
        case .road: "Smoothest asphalt"
        case .gravel: "Most scenic"
        case .mtb: "Most off-road"
        case .cargo: "Step-free and smooth"
        }
    }

    /// Off-road types turn the difference line around: unpaved is what they look for, not what they avoid.
    var seeksUnpaved: Bool { self == .gravel || self == .mtb }

    /// Rules shown in You for this type, in design order, with their default value (design/tools/p7gen.js `RULES`).
    var ruleDefaults: [(Rule, Bool)] {
        switch self {
        case .city: [(.noCobbles, true), (.neverAlongTramRails, true), (.bikeLanesOnly, false), (.noStepsOrGaps, true)]
        case .ebike: [(.noCobbles, false), (.neverAlongTramRails, true), (.bikeLanesOnly, false)]
        case .road: [(.pavedOnly, true), (.noCobbles, true), (.neverAlongTramRails, true)]
        case .gravel: [(.neverAlongTramRails, true), (.maxGrade6, false)]
        case .mtb: [(.neverAlongTramRails, true), (.maxGrade6, false)]
        case .cargo: [(.noCobbles, true), (.neverAlongTramRails, true), (.bikeLanesOnly, true), (.maxGrade6, true),
                      (.noStepsOrGaps, true)]
        }
    }
}

enum Rule: String, CaseIterable, Codable, Sendable {
    case noCobbles, neverAlongTramRails, bikeLanesOnly, noStepsOrGaps, pavedOnly, maxGrade6, litStreetsOnly
    /// Not a ride-type rule: active when You → Routing → "Allow walking stretches" is off.
    case noWalking

    var title: String {
        switch self {
        case .noCobbles: "No cobbles"
        case .neverAlongTramRails: "Never along tram rails"
        case .bikeLanesOnly: "Bike lanes only"
        case .noStepsOrGaps: "No steps or narrow gaps"
        case .pavedOnly: "Paved roads only"
        case .maxGrade6: "Max grade 6%"
        case .litStreetsOnly: "Lit streets only"
        case .noWalking: "No walking stretches"
        }
    }
}

/// The rules in force for one route request: the ride type's switches plus the session-only lit-streets switch.
struct RuleSet: Equatable, Sendable {
    let rideType: RideType
    var enabled: Set<Rule>
    /// Session only: switches off when the ride ends (HANDOFF decision 12, confirmed by Filippo 11 Oct).
    var litStreetsOnly = false
    /// Off by default: one-way streets are routed both ways (many Milan streets allow contraflow cycling and OSM
    /// often lacks oneway:bicycle=no). On: follow one-way restrictions (You → Routing).
    var respectOneways = false
    /// On by default: short passages for pedestrians only are ridden slowly (bicycle=yes in the tiles, listed in walk_ways). Off: excluded.
    var allowWalking = true

    static func defaults(for type: RideType) -> RuleSet {
        RuleSet(rideType: type, enabled: Set(type.ruleDefaults.filter(\.1).map(\.0)))
    }

    /// Rules to enforce, in the order used to name the blocking rule (design order, lit streets last).
    var active: [Rule] {
        rideType.ruleDefaults.map(\.0).filter(enabled.contains) + (allowWalking ? [] : [.noWalking])
            + (litStreetsOnly ? [.litStreetsOnly] : [])
    }
}
