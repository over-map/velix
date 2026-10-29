import SwiftUI

/// S7 Routes (P7 §01): the routes on the map in the ride type's style, a search bar, Map, and the sheet above the
/// tab bar: the list (S7a/b), the selected route (S7c), the map moved (S7e), nothing for this filter (S7f), outside
/// the region (S7g). Ride this route opens S7d (one card) through ``AppModel/follow``.
struct RoutesView: View {
    @Bindable var app: AppModel
    @State var model: RoutesModel
    @Binding var sheet: RideSheet?
    /// Load from the pack when the tab appears (snapshot tests show fixture routes instead).
    var loadsOnAppear = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.liveMap) private var liveMap
    @State private var sheetHeight: CGFloat = 400
    @State private var searching = false
    @State private var camera: MapCamera
    @State private var top: Int64?

    init(app: AppModel, model: RoutesModel, sheet: Binding<RideSheet?>, loadsOnAppear: Bool = true) {
        self.app = app
        _model = State(initialValue: model)
        _sheet = sheet
        self.loadsOnAppear = loadsOnAppear
        _camera = State(initialValue: MapCamera(center: model.area.center, zoom: 11))
    }

    var body: some View {
        ZStack(alignment: .top) {
            map.ignoresSafeArea()
            VStack(spacing: CGFloat.velix.s) {
                searchBar
                HStack(alignment: .top) {
                    Spacer()
                    if model.moved != nil { areaPill }
                    Spacer()
                }
                .overlay(alignment: .topTrailing) { MapButton(active: sheet == .mapStyle) { sheet = .mapStyle } }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, CGFloat.velix.m)
            .padding(.top, CGFloat.velix.xs)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                tabSheet.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sheetHeight = $0 }
            }
        }
        .fullScreenCover(isPresented: $searching) {
            SearchView(app: app, purpose: .area) { place in
                searching = false
                guard let place else { return }
                camera = MapCamera(center: place.location, zoom: 11)
                model.mapMoved(to: place.location, name: place.name)
            }
        }
        .task {
            guard loadsOnAppear else { return }
            model.load(store: app.routeStore, inside: { app.packContains($0) })
        }
    }

    // MARK: Map

    @ViewBuilder private var map: some View {
        if liveMap {
            VelixMap(style: MapStyleKind(app.mapStyle), mode: scheme == .dark ? .night : .day,
                     bikeLanes: app.bikeLanes, transitLines: app.transitLines, route: model.mapRoute, camera: camera,
                     userLocation: app.location.coordinate, userHeading: app.location.heading,
                     insets: UIEdgeInsets(top: 120, left: 0, bottom: sheetHeight + 44, right: 0),
                     fit: model.moved == nil ? model.fitPoints : nil,
                     onTapRoute: { id in withAnimation(.easeOut(duration: 0.2)) { model.tapped(id); top = id } },
                     onRegionChange: { model.mapMoved(to: $0) })
        } else {
            Color.velix.surface2
        }
    }

    // MARK: Top

    private var searchBar: some View {
        Button {
            if model.selected != nil { model.deselect() } else { searching = true }
        } label: {
            HStack(spacing: 10) {
                VelixIconView(model.selected != nil ? .chevronLeft : .search, size: 20)
                let place = model.moved?.name ?? (model.outside ? model.area.name : nil)
                Text(model.selected != nil ? model.title : place ?? "Search a place").velixType(.body)
                    .foregroundStyle(model.selected != nil || place != nil ? Color.velix.ink : Color.velix.ink2)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.velix.ink)
            .padding(.horizontal, 14).frame(height: 52)
            .background(Color.velix.surface, in: RoundedRectangle(cornerRadius: CGFloat.velix.radius.card))
            .velixElevation(VelixElevations.e1)
            .contentShape(Rectangle())
        }
        .buttonStyle(VelixPressStyle())
        .accessibilityLabel(model.selected != nil ? "Back to \(model.title)" : "Search a place")
    }

    private var areaPill: some View {
        Button { withAnimation(.easeOut(duration: 0.2)) { model.searchHere() } } label: {
            HStack(spacing: 8) {
                VelixIconView(.rotateCw, size: 18)
                Text("Search routes in this area").velixType(VelixType.label.sized(16, lineHeight: 20))
            }
            .foregroundStyle(Color.velix.surface)
            .padding(.horizontal, 16).frame(height: 44)
            .background(Color.velix.ink, in: Capsule())
            .velixElevation(VelixElevations.e2, in: Capsule())
        }
        .buttonStyle(VelixPressStyle())
    }

    // MARK: Sheet

    private var tabSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            Capsule().fill(Color.velix.line).frame(width: 36, height: 5).frame(maxWidth: .infinity)
            content
        }
        .padding(EdgeInsets(top: 8, leading: CGFloat.velix.m, bottom: 14, trailing: CGFloat.velix.m))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.velix.surface, in: UnevenRoundedRectangle(topLeadingRadius: CGFloat.velix.radius.sheet,
                                                                   topTrailingRadius: CGFloat.velix.radius.sheet))
        .velixElevation(VelixElevations.e3, in: RoundedRectangle(cornerRadius: CGFloat.velix.radius.sheet))
    }

    @ViewBuilder private var content: some View {
        if model.outside {
            outside
        } else if let route = model.selectedRoute {
            RouteDetail(route: model.summary(model.key(of: route.id), route), onClose: { model.deselect() },
                        onRide: { app.follow = route })
        } else if model.moved != nil {
            sheetTitle
            Text("The map moved. Tap “Search routes in this area” to see routes here.").velixType(VelixType.body.sized(15, lineHeight: 21))
                .foregroundStyle(Color.velix.ink2).fixedSize(horizontal: false, vertical: true)
        } else {
            sheetTitle
            FilterChips(options: model.chips, leadingGlyph: model.rideType.glyph, selected: $model.filterIndex)
            if let empty = model.emptyText {
                emptyState(empty)
            } else {
                list
            }
        }
    }

    private var sheetTitle: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(model.title).velixType(VelixType.title2.sized(22, lineHeight: 25)).lineLimit(1).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Text(model.count).velixType(VelixType.body.sized(14, lineHeight: 18)).foregroundStyle(Color.velix.ink2)
        }
        .foregroundStyle(Color.velix.ink)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(model.cards, id: \.route.id) { key, route in
                    RouteListCard(route: model.summary(key, route), focused: route.id == model.focus) { model.select(route.id) }
                        .id(route.id)
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 2)
        }
        .scrollPosition(id: $top, anchor: .top)
        .onChange(of: top) { _, id in if let id, id != model.focus { model.focus = id } }
        .frame(height: 300)
    }

    private func emptyState(_ t: (title: String, message: String)) -> some View {
        VStack(spacing: 8) {
            VelixIconView(.routeOff, size: 30).foregroundStyle(Color.velix.ink3)
            Text(t.title).velixType(VelixType.label.sized(17, lineHeight: 22)).foregroundStyle(Color.velix.ink)
            Text(t.message).velixType(VelixType.body.sized(15, lineHeight: 21)).foregroundStyle(Color.velix.ink2)
            if !model.all.isEmpty {
                PrimaryButton(title: "Show all routes", kind: .secondary) { model.filterIndex = 1 }.padding(.top, 14)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 22)
    }

    private var outside: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VelixIconView(.mapPinOff, size: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Routes cover \(app.pack.regionName) for now").velixType(VelixType.title2.sized(18, lineHeight: 22))
                    Text("\(model.area.name ?? "This place") is outside the downloaded map. More regions come in phase 2.")
                        .velixType(VelixType.body.sized(15, lineHeight: 21)).foregroundStyle(Color.velix.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(Color.velix.ink)
            .padding(.top, 4)
            PrimaryButton(title: "Back to \(model.home.name ?? "Milan")", kind: .secondary) {
                camera = MapCamera(center: model.home.center, zoom: 11)
                model.backHome()
            }
        }
    }
}
