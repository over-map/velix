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

    static var entries: [Entry] { [
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
        e("RecenterButton", "riding", width: nil) { RecenterButton(riding: true) },
        e("NoticeBanner", "weather") { NoticeBanner.weather("Storm warning until 18:00", "Strong wind and hail in Milan. Consider the train.", onDismiss: {}) },
        e("NoticeBanner", "litStreets") { NoticeBanner.litStreets() },
        e("NoticeBanner", "late") { NoticeBanner.late("Running late, switched to fastest", "You still make the 08:12. Adds 2 rail crossings.") },
        e("NoticeBanner", "weakGPS") { NoticeBanner.weakGPS() },
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
        e("TransitSuggestionRow", "train") { TransitSuggestionRow(mode: .train, title: "Bike + train · 52 min", subtitle: "26 min faster than Best") },
        e("TransitSuggestionRow", "metro") { TransitSuggestionRow(mode: .metro(.m1), title: "Bike + M1 · 31 min", subtitle: "12 min faster than Best") },
        e("TransitSuggestionRow", "pressed") {
            TransitSuggestionRow(mode: .train, title: "Bike + train · 52 min", subtitle: "26 min faster than Best").buttonStyle(SurfaceRowStyle(pressed: true))
        },
        e("TransitCard", "selected") { TransitCard(model: .sample, selectedDeparture: .constant(0)) },
        e("PrimaryButton", "start") { PrimaryButton(title: "Start", icon: .navigation) },
        e("PrimaryButton", "disabled") { PrimaryButton(title: "Start", icon: .navigation, isEnabled: false, disabledNote: "Milan map downloading · 64%. First route after download.") },
        e("PrimaryButton", "secondary", width: nil) { PrimaryButton(title: "Share GPX", icon: .share, kind: .secondary, fullWidth: false) },
        e("PrimaryButton", "danger", width: nil) { PrimaryButton(title: "End", kind: .danger, fullWidth: false) },
        e("ManeuverBanner", "thenAndRoadType", width: 405) {
            ManeuverBanner(maneuver: .right, distance: "200 m", street: "Via Ampère", then: (.left, "Via Celoria"),
                           roadType: .mix(.protected), roadTypeDistance: "600 m")
        },
        e("ManeuverBanner", "arrival", width: 405) { ManeuverBanner(maneuver: .arrive, distance: "80 m", street: "Politecnico, on the right") },
        e("ManeuverBanner", "rerouting", width: 405) { RerouteBanner() },
        e("ManeuverBanner", "stageStrip", width: 405) {
            VStack(spacing: 6) {
                StageStrip(stages: [.ride, .train, .ride], current: 0)
                ManeuverBanner(maneuver: .left, distance: "350 m", street: "Via Vittor Pisani")
            }
        },
        e("ManeuverBanner", "turnTypes", width: 472) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 10), count: 6), alignment: .leading, spacing: 10) {
                ForEach([Maneuver.straight, .slightRight, .right, .sharpRight, .left, .slightLeft, .sharpLeft, .uTurn, .roundabout, .merge, .arrive], id: \.self) {
                    ManeuverTile(maneuver: $0)
                }
            }
        },
        e("RoadTypePill", "all") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) { ForEach([MixCategory.protected, .painted, .quiet], id: \.self) { RoadTypePill(kind: .mix($0)) } }
                HStack(spacing: 8) { ForEach([MixCategory.mixed, .cobbles, .unpaved], id: \.self) { RoadTypePill(kind: .mix($0)) } }
                RoadTypePill(kind: .walk, distance: "40 m")
            }
        },
        e("MapControlStack", "states", width: nil) {
            HStack(alignment: .top, spacing: 24) {
                MapControlStack()
                MapControlStack(voice: .alerts, view: .threeD)
                MapControlStack(voice: .mute, view: .north)
                MapControlStack(overview: true)
            }
        },
        e("NextHazardCard", "default", width: 405) { NextHazardCard(type: .tram, distance: "120 m") },
        e("NextHazardCard", "approaching", width: 405) { NextHazardCard(type: .tram, distance: "40 m", approaching: true) },
        e("NextHazardCard", "allTypes", width: 632) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                ForEach(p2HazardOrder, id: \.self) { NextHazardCard(type: $0, advice: sampleAdvice[$0], compact: true) }
            }
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
        e("HazardMarker", "tube", width: 160) { HazardTubeSwatch().frame(height: 10) },
        e("AvoidedTag", "default", width: nil) {
            HStack(spacing: 8) { AvoidedTag(reason: "Rails along lane"); AvoidedTag(reason: "Cobbles 300 m") }
        },
        e("EtaBar", "normal", width: 425) { EtaBar(state: .normal(arrival: "08:42", minutes: "11", km: "2.6")) },
        e("EtaBar", "rerouting", width: 425) { EtaBar(state: .rerouting(cannotFind: false)) },
        e("EtaBar", "cannotFind", width: 425) { EtaBar(state: .rerouting(cannotFind: true)) },
        e("EtaBar", "arriving", width: 425) { EtaBar(state: .arriving) },
        e("OnTrainCard", "onTheTrain", width: 405) {
            OnTrainCard(minutes: "6 min", station: "Monza", arrival: "08:28", nextStop: "Sesto S. Giovanni", thenStop: "Monza",
                        bikeCarriages: [true, true, false, false, false, false], note: "Bike space in the first 2 carriages · exit on the right")
        },
        // P5 L1–L2, D1–D5 (the lock-screen tint is the activity background: surface at 92 %, or hazard).
        e("LiveActivity", "L1-lockScreen") {
            LiveActivityLockScreen(state: .sample).background(RideActivityAttributes.ContentState.sample.lockScreenBackground,
                                                              in: RoundedRectangle(cornerRadius: 24))
                .velixElevation(VelixElevations.e1, in: RoundedRectangle(cornerRadius: 24))
        },
        e("LiveActivity", "L1-lockScreenClear") {
            LiveActivityLockScreen(state: .sampleClear).background(Color.velix.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 24))
                .velixElevation(VelixElevations.e1, in: RoundedRectangle(cornerRadius: 24))
        },
        e("LiveActivity", "L2-lockScreenHazard") {
            LiveActivityLockScreen(state: .sampleHazard).background(Color.velix.hazard, in: RoundedRectangle(cornerRadius: 24))
        },
        e("LiveActivity", "D1-D3-island", width: nil) {
            HStack(spacing: 12) {
                DynamicIslandFrame {
                    HStack { LiveActivityCompactLeading(state: .sample); Spacer(); LiveActivityCompactTrailing(state: .sample) }
                }
                DynamicIslandFrame {
                    HStack { LiveActivityCompactLeading(state: .sampleHazard); Spacer(); LiveActivityCompactTrailing(state: .sampleHazard) }
                }
                DynamicIslandFrame(width: 37, padding: EdgeInsets()) { LiveActivityMinimal(state: .sampleHazard) }
            }
        },
        e("LiveActivity", "D4-expanded") {
            DynamicIslandFrame(width: 371, height: nil, cornerRadius: 44, padding: EdgeInsets(top: 18, leading: 22, bottom: 16, trailing: 22)) {
                LiveActivityExpanded(state: .sample)
            }
        },
        e("LiveActivity", "D5-expandedHazard") {
            DynamicIslandFrame(width: 371, height: nil, cornerRadius: 44, padding: EdgeInsets(top: 18, leading: 22, bottom: 16, trailing: 22)) {
                LiveActivityExpanded(state: .sampleHazard)
            }
        },
        // P7 S6a–S6c sheet content.
        e("RideSummary", "S6a-synced") {
            RideSummary(arrived: "08:42", place: "Politecnico", option: "Calmest for city", km: "5.4", minutes: "21", climb: "8",
                        connections: .synced, gpx: URL(fileURLWithPath: "/tmp/ride.gpx"))
        },
        e("RideSummary", "S6b-notConnected") {
            RideSummary(arrived: "08:42", place: "Politecnico", option: "Calmest for city", km: "5.4", minutes: "21", climb: "8",
                        gpx: URL(fileURLWithPath: "/tmp/ride.gpx"))
        },
        e("RideSummary", "S6c-dataIssue") {
            RideSummary(arrived: "08:42", place: "Politecnico", option: "Calmest for city", km: "5.4", minutes: "21", climb: "8",
                        connections: .synced, issue: RideSummary.sampleIssue, gpx: URL(fileURLWithPath: "/tmp/ride.gpx"))
        },
        e("RouteListCard", "selected") { RouteListCard(model: .sample, selected: true) },
        e("RouteListCard", "unselected") { RouteListCard(model: .sample) },
        e("FilterChips", "fitsCity", width: 425) {
            FilterChips(options: ["Fits City", "All", "Paved", "Gravel", "MTB"], leadingGlyph: .rideTypeCity, selected: .constant(0))
        },
        e("RuleToggleRow", "cityRules") {
            VStack(spacing: 0) {
                RuleToggleRow(title: "No cobbles", isOn: .constant(true), divider: false)
                RuleToggleRow(title: "Never along tram rails", isOn: .constant(true))
                RuleToggleRow(title: "Bike lanes only", isOn: .constant(false))
                RuleToggleRow(title: "No steps or narrow gaps", isOn: .constant(true))
            }
        },
        e("RuleToggleRow", "litStreets") {
            RuleToggleRow(title: "Lit streets only", subtitle: "Switches off when the ride ends", icon: .lamp, isOn: .constant(false), divider: false)
        },
        e("RideRow", "ownBike") { RideRow(destination: "Politecnico di Milano", detail: "Today 08:19 · 5.4 km · 23 min", divider: false) },
        e("RideRow", "bikeTransit") { RideRow(destination: "Villa Reale, Monza", detail: "Sat 10:02 · bike + train · 1 h 04", transit: true, divider: false) },
        e("ConnectionRow", "connected") { ConnectionRow(icon: .activity, name: "Strava", detail: "Auto-sync after each ride", connected: true, divider: false) },
        e("ConnectionRow", "connect") { ConnectionRow(icon: .heart, name: "Apple Health", connected: false, divider: false) },
        e("OfflineRegionRow", "downloading") {
            OfflineRegionRow(region: "Lombardy", state: .downloading(received: "141", total: "220 MB", fraction: 0.64), divider: false)
        },
        e("OfflineRegionRow", "ready") { OfflineRegionRow(region: "Lombardy", state: .ready(size: "220 MB", updated: "2 Oct"), divider: false) },
        e("OfflineRegionRow", "update") { OfflineRegionRow(region: "Lombardy", state: .update(size: "18 MB"), divider: false) },
        e("OfflineRegionRow", "failed") { OfflineRegionRow(region: "Lombardy", state: .failed, divider: false) },
        e("OnboardingStep", "location", width: 282) {
            OnboardingStep(step: 0, title: "Use your location", message: "Velix routes from where you are. Location stays on this phone.",
                           button: PrimaryButton(title: "Allow location")) {
                VelixIconView(.locate, size: 48).foregroundStyle(Color.velix.ink)
            }
            .frame(height: 340)
        },
        e("OnboardingStep", "rideType", width: 282) {
            OnboardingStep(step: 1, title: "How do you usually ride?", message: "Switch any time on the map.",
                           button: PrimaryButton(title: "Continue")) {
                OnboardingRideTypeList(selected: .constant(.city))
            }
            .frame(height: 340)
        },
        e("OnboardingStep", "download", width: 282) {
            OnboardingStep(step: 2, title: "Download Milan", message: "220 MB, works offline. Explore the map while it loads.",
                           button: PrimaryButton(title: "Explore the map", kind: .secondary)) {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressBar(fraction: 0.64)
                    Text("141 of 220 MB").velixType(VelixType.body.sized(13, lineHeight: 16)).monospacedDigit().foregroundStyle(Color.velix.ink2)
                }
            }
            .frame(height: 340)
        },
        e("TabBar", "ride") { TabBar(selected: .ride) },
        e("TabBar", "you") { TabBar(selected: .you) },
    ] }

    /// P2 §08 HazardMarker row order.
    static let p2HazardOrder: [HazardType] = [.tram, .along, .cobbles, .lane, .dismount, .steps, .gap, .descent, .climb, .door]
    /// P2 NextHazardCard copy with lengths, grades and counts.
    static let sampleAdvice: [HazardType: String] = [
        .cobbles: "Rough surface for 300 m", .dismount: "Walk your bike for 40 m", .steps: "Carry your bike up 12 steps",
        .descent: "−9% for 200 m, brake early", .climb: "+8% for 300 m, shift down early",
    ]
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
