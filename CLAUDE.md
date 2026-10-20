# Velix: instructions for Claude Code

Velix is an iPhone bike navigation app (Milan pilot, iteration 1). It picks the best route for how you ride, compares it with the fastest by difference, explains its choice on the map, and warns about hazards while riding. Long trips get a bike + train/metro suggestion. No account; everything stays on the phone. Personal open-source project of Filippo (not a TomTom project).

## Sources of truth (in this order)

1. **`docs/BRIEF.md` §8 "Current decisions"** plus the **Decision overrides** table below.
2. **`design/HANDOFF.md`** and **`design/README.md`**: screens, states, components, product/visual/accessibility decisions.
3. **`design/velix-tokens.json`**: every colour, font, spacing, radius, elevation, motion and map value. Never hard-code a value that exists here.
4. **Design references** (HTML, open in a browser; never ship or wrap them):
   - `design/Velix P9 Prototype.dc.html`: clickable flows
   - `design/Velix P2 Design System v2.dc.html`: components and states
   - `design/Velix P3 Map Cartography v3.html` + `design/p3v3/render.js`: map draw order, widths per zoom, label rules
   - `design/Velix P4`–`P8`: per-screen layouts, light/dark, accessibility
5. `docs/BUILD_PLAN.md`: milestones, acceptance criteria and order of work.

If two sources disagree, follow the higher one and log the conflict in `docs/DECISIONS.md`. When unsure, ask Filippo rather than guessing.

### Decision overrides (brief vs design handoff)

| Topic | Handoff says | Build this | Why |
|---|---|---|---|
| Comfort score | No 0–100 score on cards | **No score** (follow handoff) | Simpler. The difference line explains |
| Transit suggestion trigger | Only when it saves ≥ 20 min vs Best | **Any trigger** from brief §8: saves ≥ 20 min or ≥ 30%; bike-only > 45 min or > 12 km and saves ≥ 10 min; avoids ≥ 200 m climbing; destination outside the city area. Never < 5 km | Filippo asked for multimodality not limited to time saved |
| Lit streets only | Manual, session only, off at ride end | Follow handoff: switch in You, **turns off when the ride ends** | Confirmed by Filippo 11 Oct: a night-time rule shouldn't follow you into the morning |
| No route meets the rules | Name the blocking rule, link to You | Follow handoff | One place for rules |
| Ride summary share | GPX only | Follow handoff | |

## Product rules that override convenience

- **Commute = 2 taps** (open → Work → Start). Count taps in every flow you build.
- **One place per setting**: ride type = chip on Ride (onboarding sets the default); rules + lit streets = You; voice/view = riding map controls; map style + overlays = Map button before riding.
- Iteration 1 = own bike + bike & transit. **No bike-share, no accounts, no social.**
- Routing is **offline only** in iteration 1 (on-device Valhalla), behind a `RoutingProvider` protocol so an online provider can be added later with identical results.
- English only. Copy comes from the design files; don't invent new copy without flagging it.

## Stack

| Layer | Choice |
|---|---|
| App | Swift 5.10+/6, SwiftUI, iOS 17+, iPhone only, portrait |
| Project | XcodeGen (`project.yml`), so the `.xcodeproj` is generated and never hand-edited |
| Map | MapLibre Native iOS (SPM), Velix style JSONs in `App/Resources/MapStyles/` |
| Tiles | OpenFreeMap vector tiles (OpenMapTiles schema), no key |
| Navigation | Ferrostar (SPM: FerrostarCore, FerrostarMapLibreUI, FerrostarSwiftUI). Use the custom route-provider hook to plug in on-device Valhalla |
| Routing | Valhalla on device (Rallista valhalla-mobile, SPM). Costing per ride type in `RoutingProfiles/*.json` |
| Region pack | Valhalla tiles + hazard sidecar + transit + OSM routes, built by GitHub Actions (`pipeline/`), published as a GitHub Release |
| Search | Photon (`https://photon.komoot.io/api`), biased to the user's location, fair use, debounced |
| Storage | SwiftData on device |
| Voice / haptics | AVSpeechSynthesizer (en), Core Haptics |
| Live Activity | ActivityKit widget extension, local updates |
| Tests | XCTest + Swift Testing; swift-snapshot-testing for components and screens |
| Fonts / icons | Atkinson Hyperlegible, Familjen Grotesk (OFL, bundled); Lucide (ISC) + custom glyphs from `design/assets/` |

Never add SF Symbols, TomTom assets or any closed-licence dependency. Every dependency needs an OSI licence; record it in `THIRD_PARTY.md`.

## Repository layout (target)

```
project.yml              XcodeGen spec
App/                     SwiftUI app target
  Features/              Ride, Search, RouteOptions, Riding, Transit, Routes, You, Onboarding, Summary
  DesignSystem/          Generated tokens (Color/Font/Spacing), components named as in HANDOFF §2
  Map/                   MapLibre wrappers, style loading, route/hazard layers
  Routing/               RoutingProvider protocol, ValhallaOnDeviceProvider, ride-type profiles, comfort + difference line
  Navigation/            Ferrostar integration, hazard proximity, voice, haptics
  Transit/               GTFS loader, direct-connection planner, bikes-allowed rules, late/missed logic
  Data/                  SwiftData models, region-pack manager
  Resources/             Fonts, Assets.xcassets, MapStyles, RoutingProfiles
LiveActivity/            Widget extension
Tests/                   Unit, snapshot, golden-route tests
pipeline/                Region-pack build scripts (Python + Docker), GitHub Actions workflow
tools/                   tokens → Swift generator, SVG → asset catalog
design/                  Claude Design handoff (read-only reference)
docs/                    BRIEF, BUILD_PLAN, DECISIONS, TEST_TRIPS
```

## Commands

- Generate project: `xcodegen generate`
- Build: `xcodebuild -scheme Velix -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.0' -derivedDataPath build/DerivedData -skipMacroValidation -onlyUsePackageVersionsFromResolvedFile build`
- Test: same with `test` instead of `build`. `OS=18.0` is needed because Xcode 26 defaults to the newest runtime, which has no iPhone 16 (snapshot reference device, 393 × 852). `-skipMacroValidation` trusts the MapLibre SwiftUI DSL macro (via Ferrostar). `-onlyUsePackageVersionsFromResolvedFile` keeps the committed `Package.resolved` pins (Xcode otherwise re-resolves transitive packages).
- Device build (free Personal Team): same Build command with `-destination 'platform=iOS,id=<udid>' -allowProvisioningUpdates DEVELOPMENT_TEAM=<team id> CODE_SIGN_STYLE=Automatic`, then `xcrun devicectl device install app --device <device id> build/DerivedData/Build/Products/Debug-iphoneos/Velix.app`
- Try a ride away from Lombardy (debug builds): `-- -fake-location <lat>,<lon> -simulate-ride -ride-to <lat>,<lon>,<name>`; the ride log lands in `Documents/rides/`
- Fixed position on a phone (debug builds): launch with `-- -fake-location <lat>,<lon>` (e.g. Via Soave 20: `45.447767,9.1963936`) to plan from Lombardy while away
- Golden route tests (docs/TEST_TRIPS.md): add `TEST_RUNNER_VELIX_PACK_DIR=$PWD/pipeline/out/lombardy TEST_RUNNER_VELIX_GOLDEN_OUT=$PWD/build/golden` before the Test command; `-only-testing:VelixGoldenTests` to run only them. Without the env var they are skipped
- Region pack: `make -C pipeline pack` (Docker; see `pipeline/README.md`). Published monthly by `.github/workflows/region-pack.yml`. Single stages: `make -C pipeline basemap` (planetiler, ≈ 6 min), `overlays`, `package validate smoke`; pipeline unit tests: `make -C pipeline test`
- Map glyphs: `tools/glyphs/build.sh` (fontnik in Docker) → `App/Resources/MapStyle/glyphs/`
- Map styles: `node tools/stylegen/stylegen.mjs` (from `design/p3v3`; `--check` to verify, CI also runs `gl-style-validate`) → `App/Resources/MapStyle/*.json` + `Generated/MapPalette+Velix.swift`
- Map preview (debug): side-load `basemap.pmtiles`, `overlays.pmtiles`, `valhalla_tiles.tar`, `hazards.sqlite` into the app's Documents (`xcrun simctl get_app_container booted io.github.over-map.velix data`), launch with `-map-preview -use-sideloaded` (`-map-style`, `-map-mode`, `-map-zoom`, `-map-frame route|loreto|monza`, `-map-overlays`, `-map-planned`, `-map-bare`). P3 side-by-sides: `tools/p3-frames/shoot.sh`
- Map golden snapshots: part of the golden tests when `VELIX_PACK_DIR` has `basemap.pmtiles` (PNGs in `$VELIX_GOLDEN_OUT/map`)
- M1 spike tiles: `./pipeline/spike/build_milan_tiles.sh`, then side-load as in `pipeline/spike/README.md`. Unattended device runs: `xcrun devicectl device process launch --device <id> io.github.over-map.velix -- -spike -m1-benchmark` (or `-m1-simride`); log at `Documents/m1-metrics.jsonl`
- App flows (M6): the app opens on first launch (S0) until done, then Ride. Debug: `-spike` (M1 spike), `-design-gallery`, `-map-preview`; reset first launch by deleting `Application Support/state.json` in the app container. Screen snapshots: `Tests/Snapshot/Screens` (flat map backdrop); design frames for comparison: `node tools/design-frames/shoot.mjs "<page>.dc.html" <out> <label prefixes>` (repo served on 127.0.0.1:8766)
- Regenerate tokens: `swift run --package-path tools TokenGen design/velix-tokens.json App/DesignSystem/Generated App/Resources/Assets.xcassets` (add `--check` to only verify; CI does). Deviations from the token file go in `tools/TokenGen/overrides.json` with a reason, never in `design/`
- Regenerate icons: `python3 tools/icongen.py` (Lucide + `tools/icons-extra` + glyphs + `tools/glyphs-extra` → `Assets.xcassets/VelixIcons` and `Icon+Velix.swift`)
- Component gallery (debug): launch with `-design-gallery` (simulator: `xcrun simctl launch booted io.github.over-map.velix -design-gallery`). States live in `App/Features/Gallery/ComponentCatalog.swift`; the snapshot tests read the same list
- Re-record snapshots: delete the PNGs under `Tests/Snapshot/**/__Snapshots__/` and run the Test command twice (the first run records and fails)
- Simulate a ride: `xcrun simctl location booted start --speed=5 <lat,lon> <lat,lon> …` (or the GPX files in `Tests/Fixtures/gpx/`)

Keep this section accurate when commands change.

## How to work

- Work milestone by milestone from `docs/BUILD_PLAN.md`. Start each milestone in **plan mode**, show the plan, wait for approval, then implement.
- Small commits with clear messages; one milestone = one branch + PR to `main`.
- Write tests first for logic (routing profiles, difference line, transit triggers, hazard proximity, late/missed). Snapshot-test every component and screen, light and dark, against the design references.
- To build a screen, use the **`velix-screen`** skill. To check work, use **`velix-verify`**. For the region pack, **`velix-region-pack`**. To put the app on Filippo's iPhone or cut a release, **`velix-ship`**.
- Accessibility is part of done: riding targets ≥ 60 pt (else 44), Dynamic Type caps as in HANDOFF, VoiceOver labels from `design/Velix P8 Accessibility.dc.html`.
- Log every product or technical decision (and any deviation from the design) in `docs/DECISIONS.md` with the reason.

## Definition of done (every task)

1. Builds with no warnings in new code; all tests pass.
2. Matches the design reference (snapshot or side-by-side screenshot attached to the PR), light and dark.
3. Tap count checked for the flow touched.
4. No hard-coded values that exist in tokens; no new licence issues.
5. `docs/DECISIONS.md` and this file updated if anything changed.

## Data licences

OSM data (ODbL): show "© OpenStreetMap contributors" on every map. OpenFreeMap, Copernicus DEM, Trenord/ATM GTFS: attribution in You → About. Satellite: open data only (Sentinel-2, AGEA orthophoto CC BY 4.0), never Esri/Google/Bing/Mapbox/Maxar/Apple.
