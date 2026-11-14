# Velix build plan (iteration 1)

Each milestone: plan mode → approval → implement on a branch → PR with screenshots and test results → merge. **M1 is a go/no-go gate**: if on-device routing fails its criteria, stop and report options before building UI on top of it.

## M0 · Repository and toolchain
- `git init`, public GitHub repo `velix` (MIT or Apache-2.0, ask Filippo which), `.gitignore` for Xcode/SwiftPM, `THIRD_PARTY.md`.
- XcodeGen `project.yml`: app target `Velix` (iOS 17, iPhone, portrait), `LiveActivity` extension, test targets.
- SPM deps pinned: MapLibre Native, Ferrostar, valhalla-mobile, swift-snapshot-testing.
- GitHub Actions `ci.yml` on `macos-latest`: generate, build, test (public repos have free macOS minutes).
- **Accept when:** CI is green on an empty app showing "Velix" with the bundled fonts.

## M1 · Tech spike (go/no-go)
- MapLibre map with an OpenFreeMap style centred on Milan.
- Build Valhalla tiles locally (Docker) for a Milan bbox; bundle them in a debug build; route Porta Venezia → Politecnico on device with the City profile.
- Hand the route to Ferrostar via its custom route provider; drive it in the simulator with `simctl location`; show the maneuver banner.
- Check the free Apple ID (Personal Team) works for: install on Filippo's iPhone, background location, Live Activity, HealthKit, App Groups. Record what's missing.
- **Measure:** route time on device (target < 1.5 s for 5 km), reroute time, tile size for Milan, memory, battery over a 20-min ride.
- **Go if:** route < 2 s, reroute < 2 s, app stable on a real ride. Otherwise propose options (other engine, server provider sooner) in `docs/DECISIONS.md`.

## M2 · Region pack pipeline
- `pipeline/`: download Geofabrik `italy/nord-ovest-latest.osm.pbf`, clip to Lombardy (osmium), build Valhalla tiles (official Docker image), elevation from Copernicus GLO-30.
- Hazard sidecar (GeoJSON or FlatGeobuf): tram rails (`railway=tram`), crossing points and "rails along the lane" (parallel distance), cobbles (`surface=sett|cobblestone|unhewn_cobblestone`), steps, barriers and narrow gaps (`barrier=*`, `maxwidth`), dismount zones (`bicycle=dismount`, pedestrian areas), steep segments (from DEM), door-zone lanes (painted lanes beside `parking:lane`).
- OSM cycle route relations (local/regional/national/EuroVelo, MTB) for the Routes tab.
- Transit: Trenord GTFS + ATM metro GTFS (static), stops near the network, curated `bikes_allowed_rules.yml` (by line, day, time window).
- Pack = tiles + sidecars + manifest (version, bbox, size, checksums). Workflow `region-pack.yml`: monthly schedule + manual trigger, publishes a GitHub Release asset.
- **Accept when:** pack ≤ 220 MB, rebuild reproducible, manifest validated, release downloadable.

## M3 · Routing quality
- Ride-type profiles (`RoutingProfiles/{city,ebike,road,gravel,mtb,cargo}.json`) mapping rules to Valhalla costing options; Best = profile costing; Fastest = permissive costing.
- Post-processing on the route's edges + hazard sidecar: comfort mix (protected, painted, quiet, mixed, cobbles, unpaved), hazards on route, avoided-roads candidates, difference line, "best and fastest" rule (< 5%).
- Rules that Valhalla can't enforce strictly (bike lanes only, no steps) → prefer, check the result and, if violated, say which rule blocks (HANDOFF "no route meets the rules").
- `docs/TEST_TRIPS.md`: 10 Milan trips × 6 ride types, golden expectations (e.g. City avoids Via Morgagni cobbles). Golden tests in CI.
- **Accept when:** golden tests pass; Filippo reviews the 10 trips on a debug map and approves.

## M4 · Design system in code
- `tools/TokenGen`: `design/velix-tokens.json` → `Color.velix.*` (Asset Catalog with Any/Dark), `Font.velix.*` (with Dynamic Type caps), spacing, radius, elevation, motion.
- Icons: Lucide + custom glyphs from `design/assets/` → Asset Catalog (vector, template rendering). App icon from `design/assets/app-icon/`.
- Components from HANDOFF §2 with SwiftUI previews and light/dark snapshot tests, matched against `Velix P2 Design System v2.dc.html`.
- **Accept when:** component gallery screen matches P2; snapshots committed.

## M5 · Map styles
- MapLibre style JSONs: Standard and Outdoor, day and night, from `Velix P3 Map Cartography v3.html` and `p3v3/render.js`. Satellite after the licence check (Sentinel-2 z0–13 + AGEA ortho z14+, crossfade).
- Style per ride type (City/Road/Cargo → Standard | Satellite; Gravel/MTB/E-bike → Outdoor | Satellite), remembered per type.
- Overlays: bike lanes (z11+), train & metro (metro colour families per `mapRules`).
- Route rendering layers: selected route + casing, alternatives, transit leg, hazard tubes + markers, avoided roads + tags, start/end, station dots, heading puck; draw order and widths from `render.js`.
- **Accept when:** side-by-side screenshots at z13/15/17 match P3 for each style, day and night.

## M6 · Core flows
- S0 First launch (location → ride type → pack download with progress; map explorable meanwhile).
- S1 Ride (search bar with Home/Work, ride-type chip, Map button, recenter, all states; the severe-weather notice was removed on 8 Nov).
- S2 Search (Photon, recents, offline state).
- S3 Route options (Best + Fastest, single card, why this route, transit suggestion row, no route, computing).
- S8 You (rules per type, lit streets, rides, connections, offline map, about/attributions).
- **Accept when:** commute = 2 taps on device; all S0–S3, S8 states match P4/P7 snapshots.

## M7 · Riding
- Ferrostar session: ManeuverBanner (+ Then, RoadTypePill), MapControlStack (voice All/Alerts/Mute, view 2D/3D/North, overview), NextHazardCard (approaching < 50 m: coral fill, 2 haptic taps, ≤ 6-word voice), EtaBar, rerouting, weak GPS, auto-end on arrival → S6 summary.
- Route behind the rider trimmed; avoided-road tags only near the rider.
- Live Activity + Dynamic Island (compact, minimal, expanded), local updates within the ActivityKit budget.
- Background location and screen-locked riding.
- **Accept when:** ~~3 real rides in Milan without a crash~~ (skipped 6 Nov: accepted on simulated rides, see DECISIONS); ~~hazards fire on time (log review)~~ (set aside 6 Nov: no hazard alerts while riding since 29 Oct, see DECISIONS); P5 snapshots match. Includes the M1 real-ride findings (docs/spikes/M1_REPORT.md): no reroute bursts, no location gap while stopped, failed reroutes keep the old route.

## M8 · Bike + transit
- Planner (iteration 1): direct connections only (no train changes): ride to a station → train/metro with bikes allowed at that time → ride. Uses the static timetable from the pack.
- Suggestion triggers per CLAUDE.md overrides; TransitSuggestionRow → TransitCard (TripBar, legs, planned platform "check the board", next trains, ticket link to the operator).
- Riding with transit (S5): StageStrip, late → reroute fastest with a cost notice, missed → next train with a notice, back to Best when time allows, OnTrainCard with get-off alert. "Late" uses the rider's ETA vs the scheduled departure (no real-time feed needed).
- **Accept when:** Monza scenario passes in the simulator, including late and missed; P6 snapshots match.

## M9 · Routes, history, sync
- S7 Routes from the pack's OSM relations (filters Fits {type}/All/Paved/Gravel/MTB, search area, Ride this route = approach + route in one card).
- Ride history (SwiftData), S6 Ride summary, GPX export via share sheet.
- ~~Apple Health workouts~~ and ~~Strava~~: dropped 6 Nov (see DECISIONS). Share GPX is the way out of Velix.
- **Accept when:** P7 snapshots match.

## M10 · Polish and showcase
- Accessibility pass against P8 (Dynamic Type, VoiceOver table, colour-blind check).
- Performance: cold start, map FPS, battery per hour of riding. ~~Weather notice~~ (built with MeteoAlarm in #57, then removed 8 Nov at Filippo's request; see DECISIONS).
- Demo build on Filippo's iPhone; 60–90 s demo video script (commute, long trip with train, gravel route). **Moved after M11 and the backlog** (Filippo, 8 Nov): M10 closes last.
- **Accept when:** Filippo signs off the demo build.

## M11 · Europe, public release
Velix goes public: free, open source, non-commercial, for anyone in Europe (EU, EFTA, UK; the rest of the world later). Filippo, 8 and 9 Nov 2026; plan in DECISIONS.
1. ✅ #61 **Public-release hygiene:** Esri imagery out (EOX Sentinel-2 cloudless only); an in-app open-source licences screen; THIRD_PARTY.md corrected; ODbL on every pack release; personal locations out of tracked files.
2. ✅ #62 **Regions:** the Europe region catalogue, generated (`pipeline/stages/regions.py`, run on GitHub); a country-agnostic pipeline (UTM from the centroid, real country boundaries, time zone per region); sources merged across national borders. Italian timetable stages removed in PR 4 (they stay until Transitous replaces them). *Accept when:* every region forecast ≤ 320 MB; Lombardy, a Ticino group, Luxembourg and Île-de-France – Paris build under budget; Milan → Lugano routes.
3. 🔨 **Build at scale + signing:** monthly workflow for all regions (each Geofabrik extract downloaded once and sliced; ≤ 256-job runs); paginated index; slimmer `packs.json` with a mirror list; releases pruned after 2 months; Ed25519-signed index and manifests, published from a protected environment that needs Filippo's approval; the app rejects unsigned packs. *Accept when:* a full Europe run publishes, signed.
4. **Transitous:** bike + train from the Transitous API everywhere, Italy included (direct trains, bike legs re-routed on the phone, Velix's own per-operator bike rules, live delays where present, online only). Within Transitous's published usage policy; contact them only if use nears 720 plans a day. *Accept when:* Monza, Munich and Amsterdam trips plan with a train; late / missed tests pass.
5. **App for Europe:** hundreds of regions; time zone per region; Photon bbox from the catalogue; per-pack attribution; Greek and Cyrillic labels; metro colours from the data; new copy for the region notice (shown to Filippo first). *Accept when:* plan and ride in Munich, Paris and Lugano on the phone.
6. **Publish and check:** first Europe publish, golden and smoke results, phone checks, HANDOVER update.

## Later (phase 2, not now)
Online routing provider, App Store/TestFlight, the rest of the world, Android, bike-share (designed flow in BRIEF §9), user-published routes.
