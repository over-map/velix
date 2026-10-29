import Foundation
import Observation

/// S7 Routes (P7): cycle routes around a place, a filter, the one in focus (map ↔ list), the selected one, and the
/// map moved away ("Search routes in this area": the list never jumps on its own).
@MainActor
@Observable
final class RoutesModel {
    struct Area: Equatable {
        var center: LatLon
        /// "Milan", "Lake Como"; nil for "this area" after a pan.
        var name: String?
    }

    /// Routes this far around the area's centre.
    static let radius = 15_000.0
    static let filterNames = ["All", "Paved", "Gravel", "MTB"]

    let rideType: RideType
    private(set) var area: Area
    /// Where Back to Milan goes (the rider, or Milan).
    let home: Area
    var filterIndex = 0 { didSet { if filterIndex != oldValue { refilter() } } }
    /// Every route in the area (the S7f "There are 2 other routes here" count), and those the filter keeps, in key order.
    private(set) var all: [CycleRoute] = []
    private(set) var results: [CycleRoute] = []
    /// Card order: key order, with a route tapped on the map moved to the top (S7b).
    private(set) var order: [Int64] = []
    var focus: Int64?
    private(set) var selected: Int64?
    /// The map's centre after the rider moved it (S7e pill), or a searched place to look at.
    private(set) var moved: Area?
    private(set) var outside = false

    private var store: RouteStore?
    private var inside: (LatLon) -> Bool = { _ in true }

    init(rideType: RideType, home: Area) {
        self.rideType = rideType
        self.home = home
        area = home
    }

    var filter: RouteFilter {
        switch filterIndex {
        case 0: .fits(rideType)
        case 2: .paved
        case 3: .gravel
        case 4: .mtb
        default: .all
        }
    }

    var chips: [String] { ["Fits \(rideType.name)"] + Self.filterNames }

    // MARK: Search

    func load(store: RouteStore?, inside: @escaping (LatLon) -> Bool) {
        self.store = store
        self.inside = inside
        search(area)
    }

    func search(_ a: Area) {
        area = a
        moved = nil
        selected = nil
        outside = !inside(a.center)
        all = outside ? [] : (store?.routes(in: Geo.bbox([a.center], padding: Self.radius), near: a.center, filter: .all, limit: 300) ?? [])
        refilter()
    }

    /// Fixture routes (snapshot tests, previews).
    func show(_ routes: [CycleRoute], area a: Area) {
        area = a
        all = routes
        refilter()
    }

    private func refilter() {
        let keep = filter
        results = Array(all.filter(keep.keeps).prefix(RouteStore.limit))
        order = results.map(\.id)
        focus = results.first?.id
        if let s = selected, !results.contains(where: { $0.id == s }) { selected = nil }
    }

    /// The map moved (a pan, or a searched place): offer to search there.
    func mapMoved(to center: LatLon, name: String? = nil) {
        guard Geo.distance(center, area.center) > 1500 || name != nil else { return }
        moved = Area(center: center, name: name)
    }

    func searchHere() { if let moved { search(moved) } }

    func backHome() { search(home) }

    // MARK: Focus and selection

    func key(of id: Int64) -> Int { (results.firstIndex { $0.id == id } ?? 0) + 1 }

    var cards: [(key: Int, route: CycleRoute)] {
        order.compactMap { id in results.first { $0.id == id }.map { (key(of: id), $0) } }
    }

    /// A tap on a route's line: its card comes to the top, in focus.
    func tapped(_ id: Int64) {
        guard results.contains(where: { $0.id == id }) else { return }
        if selected != nil { selected = id; focus = id; return }
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
        focus = id
    }

    func select(_ id: Int64) { selected = id; focus = id }
    func deselect() { selected = nil }

    var selectedRoute: CycleRoute? { selected.flatMap { s in results.first { $0.id == s } } }
    var focusedRoute: CycleRoute? { focus.flatMap { f in results.first { $0.id == f } } }

    // MARK: What the sheet and the map show

    /// "Routes near Milan", "Routes in this area".
    var title: String { area.name.map { "Routes near \($0)" } ?? "Routes in this area" }

    /// "3 fit Gravel", "4 routes".
    var count: String {
        if case let .fits(t) = filter { return "\(results.count) fit \(t.name)" }
        return results.count == 1 ? "1 route" : "\(results.count) routes"
    }

    /// S7f: "No MTB routes in this area" / "There are 2 other routes here."
    var emptyText: (title: String, message: String)? {
        guard results.isEmpty, !outside else { return nil }
        let what = filterIndex == 0 ? "routes that fit \(rideType.name)" : "\(Self.filterNames[filterIndex - 1]) routes"
        let others = all.count
        return ("No \(what) in this area",
                others == 0 ? "Search another area." : others == 1 ? "There is 1 other route here." : "There are \(others) other routes here.")
    }

    func summary(_ key: Int, _ r: CycleRoute) -> RouteSummary {
        let climb = r.climb.map { "+\(Int($0.rounded()))" } ?? ""
        return RouteSummary(key: key, name: r.name, km: Format.km(r.meters), eurovelo: r.eurovelo, network: r.networkName, note: r.note,
                            mix: RouteSummary.mix(r.mix, paved: r.pavedShare), description: r.description, climb: climb,
                            time: RouteRide.duration(rideType.time(meters: r.meters, climb: r.climb ?? 0)), rideType: rideType)
    }

    var mapRoute: MapRouteModel {
        var m = MapRouteModel(best: [])
        m.listed = results.map { r in
            let state: MapRouteModel.Listed.State = selected == nil ? (r.id == focus ? .focus : .plain) : (r.id == selected ? .focus : .grey)
            return .init(id: r.id, key: key(of: r.id), line: r.line, pieces: r.pieces, state: state)
        }
        return m
    }

    /// The camera frames the route in focus (or the selected one), else the area.
    var fitPoints: [LatLon]? {
        if let r = selectedRoute ?? focusedRoute { return r.line }
        return nil
    }
}
