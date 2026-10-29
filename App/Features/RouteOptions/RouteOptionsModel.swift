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
    /// Bike + transit (M8): the first run still caught and the next ones of the same pair, when a trigger fires.
    private(set) var transit: [TransitPlan] = []
    var transitSelected = false
    var departureIndex = 0

    init(destination: Place, state: State = .computing, transit: [TransitPlan] = []) {
        self.destination = destination
        self.state = state
        self.transit = transit
    }

    func plan(app: AppModel) async {
        guard let origin = app.location.coordinate else { state = .needsLocation; return }
        state = .computing
        fastestSelected = false
        do {
            let planner = try await app.engine.planner()
            switch try await planner.plan(from: origin, to: destination.location, heading: app.location.travelHeading, rules: app.rules) {
            case let .options(o):
                state = .options(o)
                await planTransit(app: app, from: origin, bike: o)
            case let .noRouteMeetsRules(rule, type, closest, _): state = .blocked(rule: rule, rideType: type, closest: closest)
            case .noRoute: state = .noRoute
            }
        } catch EngineHost.Failure.noPack {
            state = .failed("Routes start when the \(app.pack.regionName) download is done.")
        } catch {
            state = .failed("Velix couldn’t plan this route.")
        }
    }

    /// In the background, after the bike routes are on screen: one direct connection, kept only when a trigger
    /// fires (BRIEF §8: a suggestion, never a third card).
    private func planTransit(app: AppModel, from origin: LatLon, bike: RouteOptions) async {
        transit = []
        transitSelected = false
        departureIndex = 0
        guard let planner = try? await app.engine.transitPlanner() else { return }
        let plans = await planner.plans(from: origin, to: destination.location, rules: app.rules, at: AppClock.now)
        guard let first = plans.first else { return }
        let outside = app.engine.cityArea.map { !$0.contains(destination.location) } ?? false
        let b = bike.best
        if TransitTrigger.shows(bike: .init(seconds: b.seconds, meters: b.meters, climb: b.analysis.climbM), transit: first,
                                destinationOutsideCity: outside) {
            transit = plans
        }
    }

    // MARK: Bike + transit (P4 S3d, S3e)

    var transitPlan: TransitPlan? { transit.indices.contains(departureIndex) ? transit[departureIndex] : transit.first }

    var transitRow: (mode: TransitMode, title: String, subtitle: String)? {
        guard let p = transit.first, let o = options else { return nil }
        return (Self.mode(p), TransitCopy.rowTitle(p), TransitCopy.rowSubtitle(p, bikeSeconds: o.best.seconds, destination: destination))
    }

    var transitCard: TransitCard.Model? {
        guard let p = transitPlan else { return nil }
        let ticket = TransitCopy.ticket(p)
        return TransitCard.Model(title: TransitCopy.cardTitle(p), subtitle: TransitCopy.cardSubtitle(p),
                                 minutes: TransitCopy.minutes(p.seconds), segments: TransitCopy.segments(p),
                                 departures: transit.map { TransitCopy.clock($0.departure.departs) },
                                 train: TransitCopy.trainLine(p), detail: TransitCopy.detail(p, destination: destination),
                                 ticketsLabel: ticket.label, footnote: TransitCopy.footnote)
    }

    var bikeOnlyText: String? {
        options.map { TransitCopy.bikeOnly(best: $0.best.seconds, fastest: $0.fastest?.seconds) }
    }

    static func mode(_ p: TransitPlan) -> TransitMode {
        p.departure.route.mode == .metro
            ? .metro(MetroBadge.family(TransitCopy.metroFamily(p.departure.route), name: p.departure.route.shortName)) : .train
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
        let order: [HazardType] = [.tram, .along, .cobbles, .steps, .gap, .lane, .dismount, .door, .descent, .climb].filter(\.shown)
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
        if transitSelected, let p = transitPlan { return MapRouteModel(transit: p, endName: destination.name) }
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
        if transitSelected, let p = transitPlan { return p.rideIn.analysis.shape + p.stops.map(\.stop.location) + p.rideOut.analysis.shape }
        switch state {
        case let .options(o): return o.best.analysis.shape + (o.fastest?.analysis.shape ?? [])
        case let .blocked(_, _, closest?): return closest.analysis.shape
        default: return []
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
        case .noWalking, .walkingStretches: "Every way to \(destination) has a stretch where you push the bike."
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
