import SwiftUI

/// S3 Route options (P4 §04–05): the routes on the map, Best (+ Fastest) cards, why this route, Start.
struct RouteOptionsView: View {
    @Bindable var app: AppModel
    @State var model: RouteOptionsModel
    var onClose: () -> Void
    var onStart: (RouteOption, RideChoice) -> Void
    var onEditRules: () -> Void
    /// Plan when the screen appears (snapshot tests show a fixed state instead).
    var plansOnAppear = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.liveMap) private var liveMap
    @State private var sheetHeight: CGFloat = 480

    var body: some View {
        ZStack(alignment: .top) {
            map.ignoresSafeArea()
            HStack {
                Button(action: onClose) {
                    VelixIconView(.chevronLeft, size: 22).foregroundStyle(Color.velix.ink)
                        .frame(width: 44, height: 44)
                        .background(Color.velix.surface, in: Circle())
                        .velixElevation(VelixElevations.e1, in: Circle())
                }
                .buttonStyle(VelixPressStyle())
                .accessibilityLabel("Back")
                Spacer()
            }
            .padding(.horizontal, CGFloat.velix.m)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                sheet
                    .background(GeometryReader { g in Color.clear.preference(key: SheetHeightKey.self, value: g.size.height) })
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .onPreferenceChange(SheetHeightKey.self) { sheetHeight = $0 }
        .task { if plansOnAppear, case .computing = model.state { await model.plan(app: app) } }
    }

    // MARK: Map

    @ViewBuilder private var map: some View {
        if liveMap {
            VelixMap(style: MapStyleKind(app.mapStyle), mode: scheme == .dark ? .night : .day,
                     bikeLanes: app.bikeLanes, transitLines: app.transitLines, route: model.mapRoute,
                     camera: MapCamera(center: model.destination.location, zoom: 14),
                     insets: UIEdgeInsets(top: 100, left: 0, bottom: sheetHeight, right: 0),
                     fit: model.fitPoints.isEmpty ? nil : model.fitPoints)
        } else {
            Color.velix.surface2
        }
    }

    // MARK: Sheet

    private var sheet: some View {
        VStack(alignment: .leading, spacing: CGFloat.velix.s) {
            Capsule().fill(Color.velix.line).frame(width: 36, height: 5).frame(maxWidth: .infinity)
            header
            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat.velix.s) { content }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 520)
            .fixedSize(horizontal: false, vertical: true)
            start
        }
        .padding(EdgeInsets(top: CGFloat.velix.xs, leading: CGFloat.velix.m, bottom: 34, trailing: CGFloat.velix.m))
        .background(Color.velix.surface, in: UnevenRoundedRectangle(topLeadingRadius: CGFloat.velix.radius.sheet,
                                                                   topTrailingRadius: CGFloat.velix.radius.sheet))
        .velixElevation(VelixElevations.e3, in: RoundedRectangle(cornerRadius: CGFloat.velix.radius.sheet))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.destination.name).velixType(VelixType.title2.sized(24, lineHeight: 28)).foregroundStyle(Color.velix.ink)
                    .lineLimit(1).accessibilityAddTraits(.isHeader)
                HStack(spacing: 6) {
                    VelixIconView(app.state.rideType.glyph, size: 18)
                    Text(app.state.rideType.name + (app.litStreetsOnly ? " · lit streets only" : "")).velixType(.label)
                }
                .foregroundStyle(Color.velix.ink2)
            }
            Spacer()
            SheetCloseButton(action: onClose)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .computing:
            RouteCardSkeleton()
            RouteCardSkeleton()
        case let .options(o):
            let cards = model.cards
            if let best = cards.first {
                RouteCard(model: best) { model.fastestSelected = false }
            }
            if let lit = o.litLine, !model.whyExpanded {
                HStack(spacing: CGFloat.velix.xs) {
                    VelixIconView(.lamp, size: 18)
                    Text(lit).velixType(.detail)
                }
                .foregroundStyle(Color.velix.ink)
                .padding(CGFloat.velix.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.velix.surface2, in: RoundedRectangle(cornerRadius: 12))
            }
            if cards.count > 1, !model.whyExpanded {
                RouteCard(model: cards[1]) { model.fastestSelected = true }
            }
            if !model.hazardRows.isEmpty || !model.avoidedRows.isEmpty {
                WhyThisRoute(expanded: $model.whyExpanded, hazards: model.hazardRows, avoided: model.avoidedRows)
            }
        case let .blocked(rule, type, _):
            blocked(rule: rule, type: type)
        case .noRoute:
            message(icon: .routeOff, title: "No route to \(model.destination.name)",
                    text: "Velix couldn’t find a way by bike. Try a nearby street or landmark.")
        case .needsLocation:
            message(icon: .locateOff, title: "Can’t find your location",
                    text: "Routes start from where you are. Turn on Location in Settings.")
        case let .failed(text):
            message(icon: .routeOff, title: "No routes yet", text: text)
        }
    }

    private func blocked(rule: Rule, type: RideType) -> some View {
        let (why, ruleLine) = RouteOptionsModel.blockedMessage(rule: rule, rideType: type, destination: model.destination.name)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: CGFloat.velix.s) {
                VelixIconView(.routeOff, size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No route meets your \(type.name) rules").velixType(.rowTitle)
                    Text(why).velixType(.rowSubtitle).foregroundStyle(Color.velix.ink2)
                    Text((try? AttributedString(markdown: ruleLine)) ?? AttributedString(ruleLine))
                        .velixType(.rowSubtitle).foregroundStyle(Color.velix.ink2)
                }
            }
            .padding(.bottom, CGFloat.velix.xs)
            Rectangle().fill(Color.velix.line).frame(height: 1)
            ChevronRow(title: "Change rules in You", action: onEditRules)
        }
        .foregroundStyle(Color.velix.ink)
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 0, trailing: 12))
        .overlay(RoundedRectangle(cornerRadius: CGFloat.velix.radius.card).strokeBorder(Color.velix.line, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func message(icon: VelixIcon, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: CGFloat.velix.s) {
            VelixIconView(icon, size: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).velixType(.rowTitle)
                Text(text).velixType(.rowSubtitle).foregroundStyle(Color.velix.ink2)
            }
        }
        .foregroundStyle(Color.velix.ink)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: CGFloat.velix.radius.card).strokeBorder(Color.velix.line, lineWidth: 1))
    }

    // MARK: Start (tap 2 of the commute)

    private var start: some View {
        let ready = app.pack.isReady && model.chosen != nil
        return PrimaryButton(title: "Start", icon: .navigation, isEnabled: ready, casing: true) {
            if let option = model.chosen { onStart(option, model.fastestSelected ? .fastest : .best) }
        }
        .accessibilityLabel(ready ? "Start riding to \(model.destination.name)"
                                  : app.pack.isReady ? "Start, dimmed" : "Start, dimmed, routes start when the download is done")
    }
}

private struct SheetHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 480
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
