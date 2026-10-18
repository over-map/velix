import Foundation
import Observation

/// S3 Route options: plans Best + Fastest for one destination and turns the result into what the sheet shows.
@MainActor
@Observable
final class RouteOptionsModel {
    enum State {
        case computing
        case options(RouteOptions)
        /// Cargo / kids (strict): no way meets every rule (S3f).
        case blocked(rule: Rule, rideType: RideType, closest: RouteOption?)
        case noRoute
        /// No location fix to start from (S1f: pick a start in a later version).
        case needsLocation
        case failed(String)
    }

    let destination: Place
    private(set) var state: State = .computing
    var fastestSelected = false
    var whyExpanded = false

    init(destination: Place, state: State = .computing) {
        self.destination = destination
        self.state = state
    }

    func plan(app: AppModel) async {
        guard let origin = app.location.coordinate else { state = .needsLocation; return }
        state = .computing
        fastestSelected = false
        do {
            let planner = try await app.engine.planner()
            switch try await planner.plan(from: origin, to: destination.location, heading: app.location.heading, rules: app.rules) {
            case let .options(o): state = .options(o)
            case let .noRouteMeetsRules(rule, type, closest, _): state = .blocked(rule: rule, rideType: type, closest: closest)
            case .noRoute: state = .noRoute
            }
        } catch EngineHost.Failure.noPack {
            state = .failed("Routes start when the \(app.pack.regionName) download is done.")
        } catch {
            state = .failed("Velix couldn’t plan this route.")
        }
    }

    // MARK: What the sheet shows

    var options: RouteOptions? { if case let .options(o) = state { o } else { nil } }

    /// The route Start rides: Best, or Fastest when its card is selected.
    var chosen: RouteOption? {
        guard let o = options else { return nil }
        return fastestSelected ? (o.fastest ?? o.best) : o.best
    }

    var cards: [RouteCard.Model] {
        guard let o = options else { return [] }
        var out = [Self.card(name: o.bestName, option: o.best, line: o.bestLine, selected: !fastestSelected)]
        if let f = o.fastest { out.append(Self.card(name: "Fastest", option: f, line: o.fastestLine, selected: fastestSelected)) }
        return out
    }

    static func card(name: String, option: RouteOption, line: String?, selected: Bool) -> RouteCard.Model {
        RouteCard.Model(name: name, distance: Format.km(option.meters), minutes: max(1, Int((option.seconds / 60).rounded())),
                        mix: option.analysis.mix, line: line.map(DifferenceCopy.markup), selected: selected)
    }

    /// WhyThisRoute "On your route": hazards of the chosen route, grouped by type, with streets and how many.
    var hazardRows: [WhyThisRoute.Hazard] {
        guard let a = chosen?.analysis else { return [] }
        let order: [HazardType] = [.tram, .along, .cobbles, .steps, .gap, .lane, .dismount, .door, .descent, .climb]
        return order.compactMap { type in
            let hs = a.hazards.filter { $0.type == type }
            guard !hs.isEmpty else { return nil }
            var streets: [String] = []
            for h in hs { if let s = h.street, !streets.contains(s) { streets.append(s) } }
            let subtitle = streets.isEmpty ? "On your route" : streets.prefix(4).joined(separator: ", ")
            let meters = hs.reduce(0) { $0 + $1.lengthM }
            if [.cobbles, .along, .descent, .climb].contains(type), meters >= 10 {
                return .init(type: type, subtitle: subtitle, count: nil, amount: DifferenceCopy.distance(meters))
            }
            return .init(type: type, subtitle: subtitle, count: hs.count)
        }
    }

    /// WhyThisRoute "Avoided": roads Fastest uses and Best doesn't.
    var avoidedRows: [WhyThisRoute.Avoided] {
        (options?.avoided ?? []).map { .init(name: $0.name, reason: $0.reason) }
    }

    /// The map: both routes, the avoided roads and Best's hazards; the blocked attempt as an alternative.
    var mapRoute: MapRouteModel? {
        switch state {
        case let .options(o):
            if fastestSelected, let f = o.fastest {
                return MapRouteModel(best: f.analysis.shape, alternatives: [o.best.analysis.shape], hazards: f.analysis.hazards,
                                     endName: destination.name)
            }
            return MapRouteModel(options: o, endName: destination.name)
        case let .blocked(_, _, closest?):
            var m = MapRouteModel(best: [], alternatives: [closest.analysis.shape], endName: destination.name)
            m.start = closest.analysis.shape.first
            m.end = destination.location
            return m
        default:
            return nil
        }
    }

    /// Points to fit the camera on.
    var fitPoints: [LatLon] {
        switch state {
        case let .options(o): o.best.analysis.shape + (o.fastest?.analysis.shape ?? [])
        case let .blocked(_, _, closest?): closest.analysis.shape
        default: []
        }
    }

    /// S3f copy: "Every street into Piazza del Duomo has cobbles. No cobbles is on for Cargo / kids."
    static func blockedMessage(rule: Rule, rideType: RideType, destination: String) -> (String, String) {
        let why: String = switch rule {
        case .noCobbles: "Every street into \(destination) has cobbles."
        case .neverAlongTramRails: "Every way to \(destination) runs along tram rails."
        case .noStepsOrGaps: "Every way to \(destination) has steps or a narrow gap."
        case .pavedOnly: "Every way to \(destination) has unpaved stretches."
        case .maxGrade6: "Every way to \(destination) climbs more than 6%."
        case .bikeLanesOnly: "Every way to \(destination) leaves the bike lanes."
        case .litStreetsOnly: "Every way to \(destination) uses unlit paths."
        }
        return (why, "**\(rule.title)** is on for \(rideType.name).")
    }
}

extension DifferenceCopy {
    /// Bold lead for ``DifferenceLine`` (P4): "**+5 min** · avoids …", "**5 min quicker** · …",
    /// "Fastest is **only 30 s quicker**, with …".
    static func markup(_ line: String) -> String {
        if line.hasPrefix("Fastest is "), let comma = line.firstIndex(of: ",") {
            let lead = line[line.index(line.startIndex, offsetBy: 11) ..< comma]
            return "Fastest is **\(lead)**\(line[comma...])"
        }
        if let dot = line.range(of: " · ") {
            return "**\(line[..<dot.lowerBound])**\(line[dot.lowerBound...])"
        }
        return line
    }
}
