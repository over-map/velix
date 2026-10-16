#if DEBUG
import SwiftUI

/// Debug: the P3 map frames on the device, to compare with design/Velix P3 Map Cartography v3.html.
/// Launch with `-map-preview` (and `-use-sideloaded` for pack files in Documents). Optional:
/// `-map-style standard|outdoor|satellite -map-mode day|night -map-zoom 15 -map-frame route|loreto|monza -map-overlays`.
struct MapPreviewView: View {
    @State private var style: MapStyleKind
    @State private var mode: MapMode
    @State private var zoom: Double
    @State private var frame: Frame
    @State private var bikeLanes: Bool
    @State private var transitLines: Bool
    @State private var route: MapRouteModel?
    @State private var status = "Planning the P3 sample trip…"
    private let chrome: Bool

    /// P3 frame centres (design/p3v3/page.js).
    enum Frame: String, CaseIterable {
        case route, loreto, monza
        var center: LatLon {
            switch self {
            case .route: LatLon(lat: 45.473220, lon: 9.216726)   // midpoint of the P3 Best route (harness), Porta Venezia → Politecnico
            case .loreto: LatLon(lat: 45.4840, lon: 9.2160)
            case .monza: LatLon(lat: 45.6010, lon: 9.2760)
            }
        }
    }

    init() {
        let a = ProcessInfo.processInfo.arguments
        func arg(_ k: String) -> String? { a.firstIndex(of: k).flatMap { a.indices.contains($0 + 1) ? a[$0 + 1] : nil } }
        _style = State(initialValue: arg("-map-style").flatMap(MapStyleKind.init(rawValue:)) ?? .standard)
        _mode = State(initialValue: arg("-map-mode").flatMap(MapMode.init(rawValue:)) ?? .day)
        _zoom = State(initialValue: arg("-map-zoom").flatMap(Double.init) ?? 15)
        _frame = State(initialValue: arg("-map-frame").flatMap(Frame.init(rawValue:)) ?? .route)
        _bikeLanes = State(initialValue: a.contains("-map-overlays"))
        _transitLines = State(initialValue: a.contains("-map-overlays"))
        chrome = !a.contains("-map-bare")
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VelixMap(style: style, mode: mode, bikeLanes: bikeLanes, transitLines: transitLines,
                     route: frame == .route ? route : nil, camera: MapCamera(center: frame.center, zoom: zoom))
                .ignoresSafeArea()
            if chrome { controls }
        }
        .task {
            if ProcessInfo.processInfo.arguments.contains("-map-planned") { await planSample() } else { loadP3Sample() }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(status).velixType(.caption).foregroundStyle(Color.velix.ink2)
            HStack {
                picker(MapStyleKind.allCases, $style)
                picker(MapMode.allCases, $mode)
                picker(Frame.allCases, $frame)
            }
            HStack {
                ForEach([13.0, 15, 17], id: \.self) { z in
                    Button("z\(Int(z))") { zoom = z }.buttonStyle(.bordered)
                }
                Toggle("Lanes", isOn: $bikeLanes).toggleStyle(.button)
                Toggle("Transit", isOn: $transitLines).toggleStyle(.button)
            }
        }
        .padding(12)
        .background(Color.velix.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }

    private func picker<T: Hashable & RawRepresentable>(_ all: [T], _ value: Binding<T>) -> some View where T.RawValue == String {
        Picker("", selection: value) { ForEach(all, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu)
    }

    /// P3's own sample (best, alternative, avoided, tubes, hazards, puck) exported from its renderer, so the frames
    /// compare like for like.
    private func loadP3Sample() {
        struct Sample: Decodable {
            struct Avoided: Decodable { let line: [[Double]]; let tag: [Double]; let text: String }
            struct Hazard: Decodable { let type: String; let at: [Double] }
            let best: [[Double]]; let alt: [[Double]]?; let avoided: Avoided?; let tubes: [[[Double]]]; let hazards: [Hazard]
            let start: [Double]; let end: [Double]?; let endName: String?; let loc: [Double]?; let heading: Double?
        }
        guard let url = Bundle.main.url(forResource: "p3-sample-route", withExtension: "json"),
              let s = try? JSONDecoder().decode(Sample.self, from: Data(contentsOf: url)) else { status = "No P3 sample"; return }
        let ll = { (c: [Double]) in LatLon(lat: c[1], lon: c[0]) }
        route = MapRouteModel(best: s.best.map(ll), alternatives: s.alt.map { [$0.map(ll)] } ?? [],
                              avoided: s.avoided.map { [.init(id: "p3", shape: $0.line.map(ll), reason: $0.text)] } ?? [],
                              tubes: s.tubes.map { $0.map(ll) },
                              hazards: s.hazards.compactMap { h in HazardType(rawValue: h.type).map { .init(type: $0, at: ll(h.at)) } },
                              start: ll(s.start), end: s.end.map(ll), endName: s.endName, puck: s.loc.map(ll),
                              // P3 heading: radians in local x-east / y-south; the map wants degrees clockwise from north.
                              heading: 90 + (s.heading ?? 0) * 180 / .pi)
        status = "P3 sample route · \(s.hazards.count) hazards"
    }

    /// The P3 sample trip (routes-raw.json poli: Porta Venezia → Politecnico) planned for real with City rules.
    private func planSample() async {
        guard let tiles = RegionPack.tileExtract, let hz = RegionPack.hazardStore, let store = try? HazardStore(path: hz) else {
            status = "No routing tiles / hazards: side-load the pack into Documents"
            return
        }
        do {
            let profile = try RideProfile.load(.city).best
            let engine = try await Task.detached { try ValhallaOnDeviceProvider(tileExtract: tiles, profile: profile) }.value
            let plan = try await RoutePlanner(engine: engine, hazards: store)
                .plan(from: LatLon(lat: 45.474588, lon: 9.205224), to: LatLon(lat: 45.478304, lon: 9.226869), rules: .defaults(for: .city))
            if case let .options(o) = plan {
                route = MapRouteModel(options: o, endName: "Politecnico")
                status = "\(o.bestName) · \(o.best.analysis.hazards.count) hazards · \(o.avoided.count) avoided"
            } else {
                status = "No route"
            }
        } catch {
            status = "Planner: \(error)"
        }
    }
}
#endif
