import SwiftUI

/// S8 You (P7 §03): rules per ride type, tonight's lit streets, rides, connections, offline map, privacy, about.
struct YouView: View {
    @Bindable var app: AppModel
    @State private var expanded: RideType?
    @State private var showAbout = false
    @State private var notice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("You").velixType(.display).foregroundStyle(Color.velix.ink).accessibilityAddTraits(.isHeader)
                rules
                tonight
                routing
                rides
                connections
                offlineMap
                footer
            }
            .padding(EdgeInsets(top: 12, leading: CGFloat.velix.m, bottom: 110, trailing: CGFloat.velix.m))
        }
        .background(Color.velix.canvas)
        .sheet(isPresented: $showAbout) { AboutView(app: app) }
        .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) {}
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
            RuleToggleRow(title: "Allow walking stretches", subtitle: "Short passages where you push the bike",
                          icon: .footprints, isOn: $app.state.allowWalking)
        }
    }

    // MARK: Rides (M9) and connections (M9)

    private var rides: some View {
        group("Your rides") {
            ListRow(leading: .tile(.route), title: "No rides yet", subtitle: "Your rides show up here when they end.", divider: false)
        }
    }

    private var connections: some View {
        group("Connections") {
            ConnectionRow(icon: .activity, name: "Strava", detail: "Rides upload when they end", connected: false, divider: false) {
                notice = "Strava sync comes with ride history in a later version."
            }
            ConnectionRow(icon: .heart, name: "Apple Health", detail: "Save rides as workouts", connected: false) {
                notice = "Apple Health comes with ride history in a later version."
            }
        }
    }

    // MARK: Offline map

    private var offlineMap: some View {
        group("Offline map") {
            OfflineRegionRow(region: app.pack.regionName, state: packState, divider: false) {
                app.pack.install()
            }
            Toggle(isOn: $app.state.packAutoUpdate) {
                ListRow(title: "Update automatically", subtitle: "On Wi-Fi only", divider: false)
            }
            .toggleStyle(VelixToggleStyle())
            .overlay(alignment: .top) { Rectangle().fill(Color.velix.line).frame(height: 1) }
        }
    }

    private var packState: OfflineRegionRow.State {
        switch app.pack.state {
        case let .downloading(r, t): .downloading(received: "\(r / 1_000_000)", total: "\(t / 1_000_000) MB", fraction: app.pack.fraction)
        case .failed: .failed
        case let .ready(m):
            .ready(size: m.downloadBytes > 0 ? "\(m.downloadBytes / 1_000_000) MB" : "Side-loaded",
                   updated: Self.date(m.built))
        case .none, .checking: .update(size: "")
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
                                       ("Search", "Search by Photon (komoot) · © OpenStreetMap contributors")]
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
                    if case let .ready(m) = app.pack.state { LabeledContent("Region pack", value: "\(m.name) \(m.version)") }
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
