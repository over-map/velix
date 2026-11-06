import SwiftUI

/// S8 You (P7 §03): rules per ride type, tonight's lit streets, rides, offline map, privacy, about.
struct YouView: View {
    @Bindable var app: AppModel
    /// Today for "Today" / "Yesterday" (snapshots pin it).
    var now: Date?
    @State private var expanded: RideType?
    @State private var showAbout = false
    /// The downloaded region asked to be removed (confirmation).
    @State private var removing: String?
    @State private var showHistory = false
    @State private var past: RideSummaryModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("You").velixType(.display).foregroundStyle(Color.velix.ink).accessibilityAddTraits(.isHeader)
                rules
                tonight
                routing
                rides
                offlineMap
                footer
            }
            .padding(EdgeInsets(top: 12, leading: CGFloat.velix.m, bottom: 110, trailing: CGFloat.velix.m))
        }
        .background(Color.velix.canvas)
        .sheet(isPresented: $showAbout) { AboutView(app: app) }
        .sheet(isPresented: $showHistory) {
            RideHistoryView(history: app.history) { ride in showHistory = false; open(ride, afterSheet: true) }
        }
        .fullScreenCover(isPresented: Binding(get: { past != nil }, set: { if !$0 { past = nil } })) {
            if let past {
                RideSummaryView(model: past, mapStyle: MapStyleKind(app.mapStyle), onDone: { self.past = nil })
            }
        }
    }

    // MARK: Ride types and rules

    private var rules: some View {
        group("Ride types and rules", footnote: "Rules change which route is Best. They apply to every ride of that type.") {
            let types = [app.state.rideType] + RideType.allCases.filter { $0 != app.state.rideType }
            ForEach(Array(types.enumerated()), id: \.element) { i, type in
                typeRow(type, divider: i > 0)
                if isExpanded(type) {
                    ForEach(Array(type.ruleDefaults.map(\.0).enumerated()), id: \.element) { j, rule in
                        RuleToggleRow(title: rule.title, isOn: binding(rule, type), divider: j > 0)
                            .padding(.leading, 52)
                            .accessibilityHint("Changes which route is Best for \(type.name).")
                    }
                }
            }
        }
    }

    private func isExpanded(_ type: RideType) -> Bool { (expanded ?? app.state.rideType) == type }

    private func typeRow(_ type: RideType, divider: Bool) -> some View {
        let current = type == app.state.rideType
        let set = app.state.ruleSet(for: type)
        let total = type.ruleDefaults.count
        return Button {
            withAnimation(.easeOut(duration: 0.2)) { expanded = isExpanded(type) && type != app.state.rideType ? app.state.rideType : type }
        } label: {
            HStack(spacing: CGFloat.velix.s) {
                VelixIconView(type.glyph, size: 24)
                    .foregroundStyle(current ? Color.velix.accentInk : Color.velix.ink)
                    .frame(width: 40, height: 40)
                    .background(current ? Color.velix.accent : Color.velix.surface2, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 0) {
                    Text(type.name).velixType(.rowTitle)
                    Text(current ? "Your ride type now" : "\(set.enabled.count) of \(total) rules on").velixType(.rowSubtitle)
                        .foregroundStyle(Color.velix.ink2)
                }
                Spacer()
                VelixIconView(isExpanded(type) ? .chevronUp : .chevronDown, size: 20)
            }
            .foregroundStyle(Color.velix.ink)
            .padding(.vertical, CGFloat.velix.xs)
            .frame(minHeight: 56)
            .overlay(alignment: .top) { if divider { Rectangle().fill(Color.velix.line).frame(height: 1) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(type.name)\(current ? ", your ride type now" : ""), \(isExpanded(type) ? "expanded" : "collapsed")")
    }

    private func binding(_ rule: Rule, _ type: RideType) -> Binding<Bool> {
        Binding(get: { app.state.ruleSet(for: type).enabled.contains(rule) },
                set: { on in
                    var enabled = app.state.ruleSet(for: type).enabled
                    if on { enabled.insert(rule) } else { enabled.remove(rule) }
                    app.state.rules[type] = enabled
                })
    }

    // MARK: Tonight

    private var tonight: some View {
        group("Tonight", footnote: "For the next ride only. It switches off when the ride ends.") {
            RuleToggleRow(title: "Lit streets only", subtitle: "Avoids dark park paths and unlit roads", icon: .lamp,
                          isOn: $app.litStreetsOnly, divider: false)
                .accessibilityLabel("Lit streets only, for the next ride")
        }
    }

    // MARK: Routing (not in P7: Filippo, 18 Oct)

    private var routing: some View {
        group("Routing", footnote: "These apply to every ride type. Follow the signs on the street.") {
            RuleToggleRow(title: "Respect one-way streets", subtitle: "Off: one-way streets may be used both ways",
                          icon: .route, isOn: $app.state.respectOneways, divider: false)
        }
    }

    // MARK: Rides (M9)

    /// The latest three (P7 S8), then See all rides.
    static let ridesShown = 3

    private var rides: some View {
        group("Your rides") {
            if app.history.rides.isEmpty {
                ListRow(leading: .tile(.route), title: "No rides yet", subtitle: "Your rides show up here when they end.", divider: false)
            } else {
                ForEach(Array(app.history.rides.prefix(Self.ridesShown).enumerated()), id: \.element.id) { i, ride in
                    RideRow(destination: ride.destination, detail: ride.detail(now: now ?? AppClock.now), glyph: ride.type.glyph, transit: ride.transit != nil,
                            value: Format.km(ride.meters), divider: i > 0) { open(ride) }
                }
                ChevronRow(title: "See all rides") { showHistory = true }
                    .overlay(alignment: .top) { Rectangle().fill(Color.velix.line).frame(height: 1) }
            }
        }
    }

    private func open(_ ride: RideRecord, afterSheet: Bool = false) {
        let model = RideSummaryModel(ride)
        guard afterSheet else { past = model; return }
        // After the history sheet has gone (one presentation at a time).
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            past = model
        }
    }

    // MARK: Offline map

    private var offlineMap: some View {
        group("Offline map", footnote: app.pack.installed.count == 1
              ? "Keep one region on the phone to plan routes. Browse or search a place elsewhere to add its region."
              : "Browse or search a place elsewhere to add its region.") {
            let regions = offlineRegions
            ForEach(Array(regions.enumerated()), id: \.element) { i, id in
                OfflineRegionRow(region: app.pack.name(of: id), state: packState(id), divider: i > 0,
                                 onAction: {
                                     if app.pack.downloading == id { app.pack.cancel(id) } else { app.pack.install(id) }
                                 },
                                 onRemove: app.pack.canRemove(id) ? { removing = id } : nil)
            }
            Toggle(isOn: $app.state.packAutoUpdate) {
                ListRow(title: "Update automatically", subtitle: "On Wi-Fi only", divider: false)
            }
            .toggleStyle(VelixToggleStyle())
            .overlay(alignment: .top) { Rectangle().fill(Color.velix.line).frame(height: 1) }
        }
        .confirmationDialog(removing.map { "Remove \(app.pack.name(of: $0))?" } ?? "",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { id in
            Button("Remove", role: .destructive) { app.pack.delete(id) }
            Button("Cancel", role: .cancel) {}
        } message: { id in
            Text("Frees \(Self.megabytes(onPhone: id, app.pack)). You can download it again anytime.")
        }
    }

    /// The region's size on the phone (its unpacked files).
    static func megabytes(onPhone id: String, _ pack: PackService) -> String {
        guard case let .ready(m) = pack.state(of: id) else { return "its space" }
        let bytes = m.files.reduce(Int64(0)) { $0 + $1.unpackedBytes }
        return bytes > 0 ? "\(bytes / 1_000_000) MB" : "its space"
    }

    /// The regions on the phone, then one downloading or stopped (Filippo, 6 Nov: the others are offered where the rider
    /// browses or searches, not listed here).
    private var offlineRegions: [String] {
        let installed = app.pack.installed.map(\.pack)
        let others = app.pack.states.compactMap { id, state -> String? in
            switch state {
            case .downloading, .failed, .checking: installed.contains(id) ? nil : id
            default: nil
            }
        }
        let all = installed + others.sorted { app.pack.name(of: $0) < app.pack.name(of: $1) }
        return all.isEmpty ? [RegionPack.active] : all
    }

    private func packState(_ id: String) -> OfflineRegionRow.State {
        let state = app.pack.state(of: id)
        switch state {
        case let .downloading(r, t):
            return .downloading(received: "\(r / 1_000_000)", total: "\(t / 1_000_000) MB", fraction: t > 0 ? Double(r) / Double(t) : 0)
        case .failed: return .failed
        case let .ready(m):
            return .ready(size: m.downloadBytes > 0 ? "\(m.downloadBytes / 1_000_000) MB" : "Side-loaded", updated: Self.date(m.built))
        case .none, .checking:
            if let r = app.pack.catalog.region(id) { return .available(size: "\(r.downloadBytes / 1_000_000) MB") }
            return .available(size: "")
        }
    }

    static func date(_ iso: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_GB")
        guard let d = f.date(from: String(iso.prefix(10))) else { return iso.isEmpty ? "—" : iso }
        f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: CGFloat.velix.s) {
            HStack(spacing: CGFloat.velix.xs) {
                VelixIconView(.shieldCheck, size: 20)
                Text("Everything stays on this phone. No account.").velixType(.label)
            }
            .foregroundStyle(Color.velix.ink)
            ChevronRow(title: "About and data") { showAbout = true }
        }
    }

    // MARK: Group

    private func group(_ label: String, footnote: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(label)
            VStack(spacing: 0) { content() }
                .padding(.horizontal, CGFloat.velix.m)
                .background(Color.velix.surface, in: RoundedRectangle(cornerRadius: CGFloat.velix.radius.card))
            if let footnote { Text(footnote).velixType(.footnote).foregroundStyle(Color.velix.ink3).padding(.horizontal, 4) }
        }
    }
}

/// About and data: version and the attributions the open data requires (ODbL, CC BY). Not in P7 (DECISIONS).
struct AboutView: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss

    private var sources: [(String, String)] {
        var out: [(String, String)] = [("OpenStreetMap", "© OpenStreetMap contributors (ODbL)"),
                                       ("OpenMapTiles", "© OpenMapTiles (CC BY 4.0)"),
                                       ("Search", "Search by Photon (komoot) · © OpenStreetMap contributors"),
                                       ("Map outside your regions", "OpenFreeMap · © OpenMapTiles · © OpenStreetMap contributors"),
                                       ("Hillshade", "Mapterhorn: Copernicus GLO-30 (© DLR e.V. 2010–2014 and © Airbus 2014–2018, provided under "
                                        + "COPERNICUS by the EU and ESA), swisstopo, Regione Lombardia and other national elevation data")]
        if case let .ready(m) = app.pack.state {
            for s in m.sources where !out.contains(where: { $0.1 == s.attribution }) { out.append((s.name, s.attribution)) }
        }
        return out
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Velix") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                    ForEach(app.pack.installed, id: \.pack) { m in LabeledContent("Region pack", value: "\(m.name) \(m.version)") }
                    Text("Open source under Apache 2.0. github.com/over-map/velix").velixType(.footnote)
                }
                Section("Data") {
                    ForEach(sources, id: \.1) { name, attribution in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).velixType(.rowTitle)
                            Text(attribution).velixType(.rowSubtitle).foregroundStyle(Color.velix.ink2)
                        }
                    }
                }
            }
            .navigationTitle("About and data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
