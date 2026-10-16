#if DEBUG
import SwiftUI

/// Every component state in P2 §08 order. The design-system gallery and the snapshot tests both read this list, so a
/// state shown in the gallery is a state under test.
@MainActor
enum ComponentCatalog {
    struct Entry: Identifiable {
        let component: String
        let state: String
        /// Frame width the state is drawn at (P2 frame): 393 for full-width items, nil to hug the content.
        var width: CGFloat? = 393
        let view: @MainActor () -> AnyView
        var id: String { "\(component).\(state)" }
    }

    static var components: [String] {
        var seen = Set<String>()
        return entries.map(\.component).filter { seen.insert($0).inserted }
    }

    static let entries: [Entry] = [
        e("SearchBar", "default") { SearchBar() },
        e("SearchBar", "homeUnset") { SearchBar(homeSet: false) },
        e("SearchBar", "typing") { SearchField(text: .constant("Via Pascoli")) },
        e("SearchBar", "focusedEmpty") { SearchField(text: .constant("")) },
        e("RideTypeChip", "city", width: nil) { RideTypeChip(rideType: .city) },
        e("RideTypeChip", "cargo", width: nil) { RideTypeChip(rideType: .cargo) },
        e("RideTypePicker", "sheet") { RideTypePicker(selected: .constant(.city)) },
        e("RideTypePicker", "onboarding") { RideTypePicker(variant: .onboarding, selected: .constant(.road)) },
        e("MapStyleSheet", "city") {
            MapStyleSheet(rideType: .city, style: .constant(.standard), bikeLanes: .constant(true), transitLines: .constant(false))
        },
        e("MapStyleSheet", "gravel") {
            MapStyleSheet(rideType: .gravel, style: .constant(.outdoor), bikeLanes: .constant(false), transitLines: .constant(true))
        },
        e("MapButton", "default", width: nil) { MapButton() },
        e("MapButton", "active", width: nil) { MapButton(active: true) },
        e("RecenterButton", "free", width: nil) { RecenterButton() },
        e("RecenterButton", "following", width: nil) { RecenterButton(following: true) },
        e("NoticeBanner", "weather") { NoticeBanner.weather("Storm warning until 18:00", "Strong wind and hail in Milan. Consider the train.", onDismiss: {}) },
        e("NoticeBanner", "litStreets") { NoticeBanner.litStreets() },
        e("NoticeBanner", "late") { NoticeBanner.late("Running late, switched to fastest", "You still make the 08:12. Adds 2 rail crossings.") },
        e("NoticeBanner", "missed") { NoticeBanner.missed("Missed the 08:12, now on the 08:27", "Arrival 09:41, 15 min later.") },
        e("NoticeBanner", "pill", width: nil) { NoticePill(text: "Storm until 18:00") },
        e("RouteCard", "best") { RouteCard(model: .sampleBest) },
        e("RouteCard", "fastest") { RouteCard(model: .sampleFastest) },
        e("RouteCard", "bestAndFastest") { RouteCard(model: .sampleSingle) },
        e("RouteCard", "computing") { RouteCardSkeleton() },
        e("ComfortMixBar", "large") { ComfortMixBar(mix: sampleMix) },
        e("ComfortMixBar", "compact") { ComfortMixBar(mix: sampleMix, size: .compact) },
        e("ComfortMixBar", "legend") { ComfortMixLegend(meters: sampleMix) },
        e("DifferenceLine", "slower") { DifferenceLine(text: "**+5 min** · avoids 420 m cobbles, 3 rail crossings", standalone: true) },
        e("DifferenceLine", "nearlyEqual") { DifferenceLine(text: "Fastest is **only 40 s quicker**, with 2 rail crossings", standalone: true) },
        e("WhyThisRoute", "collapsed") { WhyThisRoute(expanded: .constant(false)) },
        e("WhyThisRoute", "expanded") {
            WhyThisRoute(expanded: .constant(true), hazards: sampleHazards, avoided: sampleAvoided)
        },
        e("HazardMarker", "tiles", width: nil) {
            HStack(spacing: 8) { ForEach(p2HazardOrder, id: \.self) { HazardMarker(type: $0) } }
        },
        e("HazardMarker", "map", width: nil) {
            HStack(spacing: 12) {
                HazardMarker(type: .cobbles, style: .map)
                HazardMarker(type: .tram, style: .map)
                HazardMarker(style: .cluster(5))
            }
        },
        e("HazardMarker", "tube", width: 160) { VStack { HazardTubeSwatch().frame(height: 10) } },
        e("AvoidedTag", "default", width: nil) {
            HStack(spacing: 8) { AvoidedTag(reason: "Rails along lane"); AvoidedTag(reason: "Cobbles 300 m") }
        },
        e("PrimaryButton", "start") { PrimaryButton(title: "Start", icon: .navigation) },
        e("PrimaryButton", "disabled") { PrimaryButton(title: "Start", icon: .navigation, isEnabled: false, disabledNote: "Milan map downloading · 64%. First route after download.") },
        e("PrimaryButton", "secondary", width: nil) { PrimaryButton(title: "Share GPX", icon: .share, kind: .secondary, fullWidth: false) },
        e("PrimaryButton", "danger", width: nil) { PrimaryButton(title: "End", kind: .danger, fullWidth: false) },
        e("TabBar", "ride") { TabBar(selected: .ride) },
        e("TabBar", "you") { TabBar(selected: .you) },
    ]

    /// P2 §08 HazardMarker row order.
    static let p2HazardOrder: [HazardType] = [.tram, .along, .cobbles, .lane, .dismount, .steps, .gap, .descent, .climb, .door]
    static let sampleMix: [MixCategory: Double] = [.protected: 1600, .painted: 1100, .quiet: 1100, .mixed: 600, .cobbles: 500, .unpaved: 400]
    static let sampleHazards: [WhyThisRoute.Hazard] = [
        .init(type: .tram, subtitle: "Viale Romagna", count: 1),
        .init(type: .door, subtitle: "Via Pascoli, 150 m", count: nil),
        .init(type: .cobbles, subtitle: "Piazza Ascoli, 70 m", count: nil),
    ]
    static let sampleAvoided: [WhyThisRoute.Avoided] = [
        .init(name: "Corso Buenos Aires", reason: "Rails along lane"),
        .init(name: "Via Plinio", reason: "Cobbles 300 m"),
    ]

    private static func e<V: View>(_ component: String, _ state: String, width: CGFloat? = 393,
                                   @ViewBuilder _ make: @escaping @MainActor () -> V) -> Entry {
        Entry(component: component, state: state, width: width, view: { AnyView(make()) })
    }
}
#endif
