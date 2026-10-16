import Foundation

/// The one line that explains Best against Fastest (HANDOFF: "Fastest is compared by difference, never ranked").
/// Copy patterns from design/tools/p4gen.js:
///   "+5 min · avoids 300 m cobbles and busy Corso Buenos Aires"
///   "+7 min · avoids 3.6 km on busy Viale Fulvio Testi"
///   "+9 min · bike lanes all the way, no steps, no cobbles"
///   Single card: "Fastest is only 30 s quicker, with rails along Corso Buenos Aires. So there's one route."
enum DifferenceCopy {
    /// Fastest must be at least this much quicker to get its own card.
    static let singleCardThreshold = 0.05

    enum Reason: Equatable, Sendable {
        case railsAlong(String?)
        case cobbles(Double)
        case busy(String, Double)
        case steps(Int)
        case unpaved(Double)
        case climb(Double)
        case moreOffRoad(Double)
        case parkPath(Double)

        var text: String {
            switch self {
            case let .railsAlong(street): street.map { "rails along \($0)" } ?? "rails along the lane"
            case let .cobbles(m): "\(DifferenceCopy.distance(m)) cobbles"
            case let .busy(name, m): m >= 1000 ? "\(DifferenceCopy.distance(m)) on busy \(name)" : "busy \(name)"
            case let .steps(n): n == 1 ? "1 flight of steps" : "\(n) flights of steps"
            case let .unpaved(m): "\(DifferenceCopy.distance(m)) unpaved"
            case let .climb(m): "\(Int(m.rounded())) m of climbing"
            case let .moreOffRoad(m): "\(DifferenceCopy.distance(m)) more off-road"
            case let .parkPath(m): "\(DifferenceCopy.distance(m)) of park path"
            }
        }
    }

    static func showsSingleCard(bestSeconds: Double, fastestSeconds: Double, sameRoute: Bool) -> Bool {
        sameRoute || bestSeconds - fastestSeconds < singleCardThreshold * bestSeconds
    }

    /// What Fastest has that Best avoids (for City, E-bike, Road, Cargo), most important first.
    static func avoidedReasons(best: RouteAnalysis, fastest: RouteAnalysis, rideType: RideType) -> [Reason] {
        var out: [Reason] = []
        let alongExtra = fastest.hazardMeters(.along) - best.hazardMeters(.along)
        if alongExtra >= 30 {
            let street = fastest.hazards.filter { $0.type == .along }.max { $0.lengthM < $1.lengthM }?.street
            out.append(.railsAlong(street))
        }
        let cobbles = fastest.meters(.cobbles) - best.meters(.cobbles)
        if cobbles >= 30 { out.append(.cobbles(cobbles)) }
        if let (name, m) = fastest.busyByName.map({ ($0.key, $0.value - (best.busyByName[$0.key] ?? 0)) }).max(by: { $0.1 < $1.1 }),
           m >= 150 {
            out.append(.busy(name, m))
        }
        let steps = fastest.hazardCount(.steps) - best.hazardCount(.steps)
        if steps > 0 { out.append(.steps(steps)) }
        let unpaved = fastest.meters(.unpaved) - best.meters(.unpaved)
        if !rideType.seeksUnpaved, unpaved >= 200 { out.append(.unpaved(unpaved)) }
        let climb = fastest.climbM - best.climbM
        if climb >= 30 { out.append(.climb(climb)) }
        return out
    }

    /// What Best gains, for Gravel and MTB (they look for unpaved and paths).
    static func gainedReasons(best: RouteAnalysis, fastest: RouteAnalysis) -> [Reason] {
        var out: [Reason] = []
        let offRoad = best.meters(.unpaved) - fastest.meters(.unpaved)
        if offRoad >= 300 { out.append(.moreOffRoad(offRoad)) }
        let park = best.pathMeters - fastest.pathMeters
        if park >= 300 { out.append(.parkPath(park)) }
        return out
    }

    /// "+N min · …" for the Best card when Fastest has its own card.
    static func line(best: RouteAnalysis, bestSeconds: Double, fastest: RouteAnalysis, fastestSeconds: Double,
                     rules: RuleSet) -> String {
        let delta = "+\(max(1, Int(((bestSeconds - fastestSeconds) / 60).rounded()))) min"
        if rules.rideType.seeksUnpaved {
            let gained = gainedReasons(best: best, fastest: fastest).prefix(2).map(\.text)
            if !gained.isEmpty { return "\(delta) · " + join(gained) }
        }
        if best.laneShare >= 0.9 {
            var parts = ["bike lanes all the way"]
            if rules.enabled.contains(.noStepsOrGaps), best.hazardCount(.steps) == 0 { parts.append("no steps") }
            if rules.enabled.contains(.noCobbles), best.meters(.cobbles) == 0 { parts.append("no cobbles") }
            return "\(delta) · " + parts.joined(separator: ", ")
        }
        let avoided = avoidedReasons(best: best, fastest: fastest, rideType: rules.rideType).prefix(2).map(\.text)
        if avoided.isEmpty { return "\(delta) · calmer streets" }
        return "\(delta) · avoids " + join(avoided)
    }

    /// "5 min quicker · 300 m cobbles on Via Morgagni, busy Corso Buenos Aires" for the Fastest card.
    static func fastestLine(best: RouteAnalysis, bestSeconds: Double, fastest: RouteAnalysis, fastestSeconds: Double,
                            rideType: RideType) -> String {
        let delta = "\(max(1, Int(((bestSeconds - fastestSeconds) / 60).rounded()))) min quicker"
        let parts = avoidedReasons(best: best, fastest: fastest, rideType: rideType).prefix(2).map { reason -> String in
            switch reason {
            case let .cobbles(m):
                let street = fastest.hazards.filter { $0.type == .cobbles }.max { $0.lengthM < $1.lengthM }?.street
                return street.map { "\(distance(m)) cobbles on \($0)" } ?? reason.text
            case let .busy(name, m) where m >= 1000: return "\(distance(m)) on \(name)"
            default: return reason.text
            }
        }
        return parts.isEmpty ? delta : "\(delta) · " + parts.joined(separator: ", ")
    }

    /// The one line under a single "Best and fastest" card.
    static func singleCardLine(best: RouteAnalysis, bestSeconds: Double, fastest: RouteAnalysis,
                               fastestSeconds: Double, rideType: RideType) -> String {
        let gap = max(0, bestSeconds - fastestSeconds)
        guard gap >= 5 else { return "Fastest takes the same way. So there’s one route." }
        let quicker = gap < 90 ? "\(Int((gap / 10).rounded() * 10)) s" : "\(Int((gap / 60).rounded())) min"
        if let reason = avoidedReasons(best: best, fastest: fastest, rideType: rideType).first {
            return "Fastest is only \(quicker) quicker, with \(reason.text). So there’s one route."
        }
        return "Fastest is only \(quicker) quicker. So there’s one route."
    }

    /// "Lit streets only: avoids 2 dark park paths, +2 min"
    static func litLine(unlitPathsAvoided: Int, extraSeconds: Double) -> String {
        let paths = unlitPathsAvoided == 1 ? "1 dark park path" : "\(unlitPathsAvoided) dark park paths"
        return "Lit streets only: avoids \(paths), +\(max(1, Int((extraSeconds / 60).rounded()))) min"
    }

    static func distance(_ m: Double) -> String {
        if m < 1000 { return "\(Int((m / 10).rounded() * 10)) m" }
        let km = (m / 100).rounded() / 10
        return km == km.rounded() ? "\(Int(km)) km" : String(format: "%.1f km", km)
    }

    private static func join(_ parts: [String]) -> String {
        parts.count > 1 ? parts.dropLast().joined(separator: ", ") + " and " + parts.last! : parts.first ?? ""
    }
}
