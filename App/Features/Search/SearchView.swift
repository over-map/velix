import SwiftUI

/// Why Search opened: a destination, or picking Home / Work (S1c "Set Home").
enum SearchPurpose: String, Identifiable {
    case destination, setHome, setWork
    var id: String { rawValue }
}

/// S2 Search (P4 §03): Home, Work and recents; Photon results as you type; first use; no results; offline.
struct SearchView: View {
    let app: AppModel
    let purpose: SearchPurpose
    /// The picked place, or nil on Cancel.
    var onDone: (Place?) -> Void
    @State private var query: String
    @State private var results: [Place]
    @State private var searched: Bool
    @State private var offline: Bool
    @State private var setting: SearchPurpose?
    /// Snapshot tests: show these results without searching.
    private let preset: Bool

    init(app: AppModel, purpose: SearchPurpose, query: String = "", results: [Place]? = nil, offline: Bool = false,
         onDone: @escaping (Place?) -> Void) {
        self.app = app
        self.purpose = purpose
        self.onDone = onDone
        _query = State(initialValue: query)
        _results = State(initialValue: results ?? [])
        _searched = State(initialValue: results != nil)
        _offline = State(initialValue: offline)
        preset = results != nil || offline
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $query, onCancel: { onDone(nil) })
                .padding(.horizontal, CGFloat.velix.m).padding(.top, CGFloat.velix.xs).padding(.bottom, CGFloat.velix.s)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) { content }
                    .padding(.horizontal, CGFloat.velix.m)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.velix.canvas)
        .task(id: query) { await run() }
        .fullScreenCover(item: $setting) { p in
            SearchView(app: app, purpose: p) { place in
                setting = nil
                guard let place else { return }
                if p == .setHome { app.state.home = place } else { app.state.work = place }
            }
        }
    }

    // MARK: States

    @ViewBuilder private var content: some View {
        let typing = query.trimmingCharacters(in: .whitespaces).count >= 2
        if offline {
            offlineBox
            saved(recentSubtitle: "Recent")
        } else if typing, searched, results.isEmpty {
            noMatch
        } else if typing {
            ForEach(Array(results.enumerated()), id: \.element.id) { i, p in row(p, divider: i > 0) }
        } else if purpose == .destination, app.state.home == nil, app.state.work == nil, app.state.recents.isEmpty {
            firstUse
        } else {
            saved(recentSubtitle: nil)
        }
    }

    /// Home and Work first, then RECENT (up to 5).
    @ViewBuilder private func saved(recentSubtitle: String?) -> some View {
        if purpose == .destination {
            if let home = app.state.home { row(home, title: "Home", subtitle: home.name, icon: .tile(.house), divider: false) }
            if let work = app.state.work { row(work, title: "Work", subtitle: work.name, icon: .tile(.briefcase), divider: app.state.home != nil) }
        }
        let recents = Array(app.state.recents.prefix(AppState.recentsShown))
        if !recents.isEmpty {
            if recentSubtitle == nil { SectionLabel("Recent").padding(.top, CGFloat.velix.m).padding(.bottom, 4) }
            ForEach(Array(recents.enumerated()), id: \.element.id) { i, p in
                row(p, subtitle: recentSubtitle ?? p.subtitle, divider: recentSubtitle != nil || i > 0)
            }
        }
    }

    private var firstUse: some View {
        VStack(spacing: 0) {
            Button { setting = .setHome } label: { setRow("Set Home") }.buttonStyle(.plain)
            Button { setting = .setWork } label: { setRow("Set Work", divider: true) }.buttonStyle(.plain)
            Text("Search for an address, a place or a station.").velixType(.callout).foregroundStyle(Color.velix.ink2)
                .frame(maxWidth: .infinity).padding(.top, CGFloat.velix.l)
        }
    }

    private func setRow(_ title: String, divider: Bool = false) -> some View {
        ListRow(leading: .tile(.plus), title: title, divider: divider) {
            VelixIconView(.chevronRight, size: 18).foregroundStyle(Color.velix.ink)
        }
        .contentShape(Rectangle())
    }

    private var noMatch: some View {
        VStack(spacing: CGFloat.velix.xs) {
            VelixIconView(.searchX, size: 32).foregroundStyle(Color.velix.ink2)
            Text("No match for “\(query.trimmingCharacters(in: .whitespaces))”").velixType(.rowTitle).foregroundStyle(Color.velix.ink)
            Text("Check the spelling, or try a nearby street or landmark.").velixType(.callout).foregroundStyle(Color.velix.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, CGFloat.velix.xl)
    }

    private var offlineBox: some View {
        HStack(alignment: .top, spacing: CGFloat.velix.xs) {
            VelixIconView(.wifiOff, size: 20)
            (Text("You’re offline. ").bold() + Text("Search needs a connection. Home, Work and recent places still work, and routes are computed on the phone."))
                .velixType(VelixType.body.sized(14, lineHeight: 19))
        }
        .foregroundStyle(Color.velix.ink)
        .padding(CGFloat.velix.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.velix.surface2, in: RoundedRectangle(cornerRadius: 12))
        .padding(.bottom, CGFloat.velix.xs)
    }

    // MARK: Rows

    private func row(_ place: Place, title: String? = nil, subtitle: String? = nil, icon: ListRow<Text>.Leading? = nil,
                     divider: Bool) -> some View {
        Button { onDone(place) } label: {
            HStack(spacing: CGFloat.velix.s) {
                leading(place, icon)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title ?? place.name).velixType(.rowTitle).foregroundStyle(Color.velix.ink).lineLimit(1)
                    Text(subtitle ?? place.subtitle).velixType(.rowSubtitle).foregroundStyle(Color.velix.ink2).lineLimit(1)
                }
                Spacer(minLength: CGFloat.velix.xs)
                if let d = distance(to: place) {
                    Text(d).velixType(VelixType.bodyBold.sized(14, lineHeight: 18)).foregroundStyle(Color.velix.ink3)
                }
            }
            .padding(.vertical, CGFloat.velix.xs)
            .frame(minHeight: 56)
            .overlay(alignment: .top) { if divider { Rectangle().fill(Color.velix.line).frame(height: 1) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func leading(_ place: Place, _ icon: ListRow<Text>.Leading?) -> some View {
        let tile: (AnyView) -> AnyView = { v in
            AnyView(v.foregroundStyle(Color.velix.ink).frame(width: 40, height: 40)
                .background(Color.velix.surface2, in: RoundedRectangle(cornerRadius: 10)))
        }
        switch icon {
        case let .tile(i)?: tile(AnyView(VelixIconView(i, size: 22)))
        default:
            switch place.kind {
            case .station: tile(AnyView(VelixIconView(.train, size: 22)))
            case .metro where !place.lines.isEmpty:
                HStack(spacing: 2) {
                    ForEach(Array(place.lines.prefix(2).enumerated()), id: \.offset) { i, ref in
                        MetroBadge.family(place.lineFamilies.indices.contains(i) ? place.lineFamilies[i] : "grey", name: ref)
                    }
                }
            case .metro: tile(AnyView(VelixIconView(.metro, size: 22)))
            case .park: tile(AnyView(VelixIconView(.trees, size: 22)))
            default: tile(AnyView(VelixIconView(.mapPin, size: 22)))
            }
        }
    }

    private func distance(to place: Place) -> String? {
        app.location.coordinate.map { Format.km(Geo.distance($0, place.location)) }
    }

    // MARK: Photon, debounced

    private func run() async {
        guard !preset else { return }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { results = []; searched = false; return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        do {
            let found = try await app.search.search(q, near: app.location.coordinate)
            guard !Task.isCancelled else { return }
            results = found
            offline = false
        } catch PlaceSearchError.offline {
            offline = true
        } catch {
            results = []
        }
        searched = true
    }
}
