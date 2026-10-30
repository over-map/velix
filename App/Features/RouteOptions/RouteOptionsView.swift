import SwiftUI

/// S3 Route options (P4 §04–05): the routes on the map, Best (+ Fastest) cards, why this route, Start.
struct RouteOptionsView: View {
    @Bindable var app: AppModel
    @State var model: RouteOptionsModel
    var onClose: () -> Void
    var onStart: (RouteOption, RideChoice, [AvoidedRoad]) -> Void
    /// Start with bike + transit (S3e).
    var onStartTransit: (TransitPlan) -> Void = { _ in }
    /// Ride this route (S7d): the option, the route's far end and the vias reroutes go back through.
    var onStartFollow: (RouteOption, Place, [LatLon]) -> Void = { _, _, _ in }
    var onEditRules: () -> Void
    /// Plan when the screen appears (snapshot tests show a fixed state instead).
    var plansOnAppear = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.liveMap) private var liveMap
    @Environment(\.openURL) private var openURL
    @State private var sheetHeight: CGFloat = 480
    /// The sheet folded to the destination and Start (tap or drag the grabber): more map for the route.
    @State private var collapsed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                // The map fits the route above the sheet, whatever its height (open, folded, the transit card).
                sheet.onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { sheetHeight = VelixMap.covered(fromTop: $0) }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .task {
            if plansOnAppear, case .computing = model.state { await model.plan(app: app) }
            #if DEBUG
            // `-start-ride`: Start on the bike route as soon as it is planned (measurements, recordings).
            if ProcessInfo.processInfo.arguments.contains("-start-ride"), let option = model.chosen {
                onStart(option, .best, model.options?.avoided ?? [])
            }
            #endif
        }
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
            grabber
            header
            if !collapsed {
                ScrollView {
                    VStack(alignment: .leading, spacing: CGFloat.velix.s) { content }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 520)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
            }
            start
        }
        .padding(EdgeInsets(top: CGFloat.velix.xs, leading: CGFloat.velix.m, bottom: 34, trailing: CGFloat.velix.m))
        .background(Color.velix.surface, in: UnevenRoundedRectangle(topLeadingRadius: CGFloat.velix.radius.sheet,
                                                                   topTrailingRadius: CGFloat.velix.radius.sheet))
        .velixElevation(VelixElevations.e3, in: RoundedRectangle(cornerRadius: CGFloat.velix.radius.sheet))
    }

    /// Tap, or drag down / up, to fold or open the sheet; the map refits the route in the space left.
    private var grabber: some View {
        Capsule().fill(Color.velix.line).frame(width: 36, height: 5)
            .frame(maxWidth: .infinity, minHeight: 24)
            .contentShape(Rectangle())
            .onTapGesture { fold(!collapsed) }
            .gesture(DragGesture(minimumDistance: 12).onEnded { g in
                if g.translation.height > 30 { fold(true) } else if g.translation.height < -30 { fold(false) }
            })
            .accessibilityElement()
            .accessibilityLabel(collapsed ? "Show route details" : "Hide route details")
            .accessibilityAddTraits(.isButton)
            .padding(.vertical, -CGFloat.velix.xs)
    }

    private func fold(_ value: Bool) {
        withAnimation(VelixMotions.sheetSnap.animation(reduceMotion: reduceMotion)) { collapsed = value }
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
        case .options where model.transitSelected:
            // S3e: the bike routes fold into one row; the transit card takes the space.
            if let text = model.bikeOnlyText { BikeOnlyRow(text: text) { model.transitSelected = false } }
            if let card = model.transitCard, let p = model.transitPlan {
                TransitCard(model: card, selectedDeparture: $model.departureIndex) {
                    let ticket = TransitCopy.ticket(p)
                    // The app when it's installed, else its App Store page (or the operator's site).
                    if let app = ticket.app {
                        openURL(app) { opened in if !opened { openURL(ticket.fallback) } }
                    } else {
                        openURL(ticket.fallback)
                    }
                }
            }
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
            // S3d: one row under the bike routes when a trigger fires.
            if let row = model.transitRow, !model.whyExpanded {
                TransitSuggestionRow(mode: row.mode, title: row.title, subtitle: row.subtitle) {
                    model.departureIndex = 0
                    model.transitSelected = true
                }
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
            if model.transitSelected, let p = model.transitPlan { return onStartTransit(p) }
            if model.follow != nil, let option = model.chosen { return onStartFollow(option, model.destination, model.followVias) }
            if let option = model.chosen { onStart(option, model.fastestSelected ? .fastest : .best, model.options?.avoided ?? []) }
        }
        .accessibilityLabel(ready ? "Start riding to \(model.destination.name)"
                                  : app.pack.isReady ? "Start, dimmed" : "Start, dimmed, routes start when the download is done")
    }
}
