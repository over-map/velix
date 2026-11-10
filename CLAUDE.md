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
| Severe-weather notice | S1 NoticeBanner + pill | **None** (removed 8 Nov) | Filippo doesn't want it |

## Product rules that override convenience

- **Commute = 2 taps** (open → Work → Start). Count taps in every flow you build.
- **One place per setting**: ride type = chip on Ride (onboarding sets the default); rules + lit streets = You; voice/view = riding map controls; map style + overlays = Map button before riding.
- Iteration 1 = own bike + bike & transit. **No bike-share, no accounts, no social.**
- Bike routing is **offline only** (on-device Valhalla), behind a `RoutingProvider` protocol so an online provider can be added later with identical results. Bike + train moves to the Transitous API (online) in M11 PR 4.
- Velix is public, free, open source and non-commercial, for anyone in Europe (Filippo, 9 Nov 2026). Check every new data source or service against that.
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
- Riding with transit in the simulator (debug builds): add `-simulate-ride -time-scale 4` (and `-simulate-speed 3` for a slow rider, late / missed); e.g. late from Duomo: `-fake-location 45.4642,9.1900 -fake-time 2026-11-05T08:26 -time-scale 4 -simulate-ride -simulate-speed 3.0 -ride-to 45.5885,9.2740,Villa Reale`. Decisions land in the ride log as `"e":"transit"`
- Bike + transit at a fixed time (debug builds): add `-fake-time 08:05` (today, Rome time) or `-fake-time 2026-11-05T08:05`; e.g. Monza: `-fake-location 45.4746,9.2050 -fake-time 2026-11-05T08:05 -ride-to 45.5885,9.2740,Villa Reale`
- Try a ride away from Lombardy (debug builds): `-- -fake-location <lat>,<lon> -simulate-ride -ride-to <lat>,<lon>,<name>`; the ride log lands in `Documents/rides/`
- Fixed position on a phone (debug builds): launch with `-- -fake-location <lat>,<lon>` (e.g. south Milan: `45.448,9.196`) to plan from Lombardy while away
- Map performance on a phone (debug builds): `-start-ride` starts the planned bike route by itself; `-map-perf` prints once a second (console: `xcrun devicectl device process launch --console …`) the map frames drawn and their time, a 60 Hz main-thread heartbeat (`main`: under 60 means the main thread was busy), and time in map updates, fades, fixes and the riding state; `-map-lite <prefix,…>` hides style layers by id prefix to bisect a slowdown. Profile with `xcrun xctrace record --template 'Time Profiler' --device iFil --attach Velix --time-limit 6s`
- Performance (every build, M10): each ride log's health line has `fps`, `slow` and `cpu` (% of one core) per minute; each cold launch appends to `Documents/diagnostics/launch.jsonl`. Summarise with `python3 tools/ride-report/ride_report.py --include-simulated <ride.jsonl>` and `--launch <launch.jsonl>`. Compare builds on CPU, not battery (iOS's 5 % steps); xctrace's Power Profiler crashes on save in Xcode 27.0
- Golden route tests (docs/TEST_TRIPS.md): add `TEST_RUNNER_VELIX_PACK_DIR=$PWD/pipeline/out/lombardy TEST_RUNNER_VELIX_GOLDEN_OUT=$PWD/build/golden` before the Test command; `-only-testing:VelixGoldenTests` to run only them. Without the env var they are skipped
- Region pack: `make -C pipeline pack` (Docker; see `pipeline/README.md`). Published monthly by `.github/workflows/region-pack.yml`. Single stages: `make -C pipeline basemap` (planetiler, ≈ 6 min), `overlays`, `package validate smoke`; pipeline unit tests: `make -C pipeline test`
- Map glyphs: `tools/glyphs/build.sh` (fontnik in Docker) → `App/Resources/MapStyle/glyphs/`
- Map styles: `node tools/stylegen/stylegen.mjs` (from `design/p3v3`; `--check` to verify, CI also runs `gl-style-validate`) → `App/Resources/MapStyle/*.json` + `Generated/MapPalette+Velix.swift`
- Map preview (debug): side-load `basemap.pmtiles`, `overlays.pmtiles`, `valhalla_tiles.tar`, `hazards.sqlite` into the app's Documents (`xcrun simctl get_app_container booted io.github.over-map.velix data`), launch with `-map-preview -use-sideloaded` (`-map-style`, `-map-mode`, `-map-zoom`, `-map-pitch`, `-map-center lat,lon`, `-map-sweep` (zoom 15 → 18 in 6 s), `-map-frame route|loreto|monza`, `-map-overlays`, `-map-planned`, `-map-transit` (the sample bike + train plan to Monza), `-map-bare`). P3 side-by-sides: `tools/p3-frames/shoot.sh`
- Map golden snapshots: part of the golden tests when `VELIX_PACK_DIR` has `basemap.pmtiles` (PNGs in `$VELIX_GOLDEN_OUT/map`)
- M1 spike tiles: `./pipeline/spike/build_milan_tiles.sh`, then side-load as in `pipeline/spike/README.md`. Unattended device runs: `xcrun devicectl device process launch --device <id> io.github.over-map.velix -- -spike -m1-benchmark` (or `-m1-simride`); log at `Documents/m1-metrics.jsonl`
- App flows (M6): the app opens on first launch (S0) until done, then Ride. Debug: `-spike` (M1 spike), `-design-gallery`, `-map-preview`; reset first launch by deleting `Application Support/state.json` in the app container. Screen snapshots: `Tests/Snapshot/Screens` (flat map backdrop); design frames for comparison: `node tools/design-frames/shoot.mjs "<page>.dc.html" <out> <label prefixes>` (repo served on 127.0.0.1:8766)
- Regenerate tokens: `swift run --package-path tools TokenGen design/velix-tokens.json App/DesignSystem/Generated App/Resources/Assets.xcassets` (add `--check` to only verify; CI does). Deviations from the token file go in `tools/TokenGen/overrides.json` with a reason, never in `design/`
- Licence texts in the app: `python3 tools/licenses/licenses.py` (add `--check` to only verify; CI does) → `App/Resources/Licenses.json`. Add a package's licence file to `tools/licenses/texts/` and a row to `SHIPPED`
- Regenerate icons: `python3 tools/icongen.py` (Lucide + `tools/icons-extra` + glyphs + `tools/glyphs-extra` → `Assets.xcassets/VelixIcons` and `Icon+Velix.swift`)
- Component gallery (debug): launch with `-design-gallery` (simulator: `xcrun simctl launch booted io.github.over-map.velix -design-gallery`). States live in `App/Features/Gallery/ComponentCatalog.swift`; the snapshot tests read the same list
- Re-record snapshots: delete the PNGs under `Tests/Snapshot/**/__Snapshots__/` and run the Test command twice (the first run records and fails)
- Simulate a ride: `xcrun simctl location booted start --speed=5 <lat,lon> <lat,lon> …` (or the GPX files in `Tests/Fixtures/gpx/`)

Keep this section accurate when commands change.

## How to work

- Work milestone by milestone from `docs/BUILD_PLAN.md`. Start each milestone in **plan mode**, show the plan, wait for approval, then implement.
- Small commits with clear messages; one milestone = one branch + PR to `main`.
- Write tests first for logic (routing profiles, difference line, transit triggers, hazard proximity, late/missed). Snapshot-test every component and screen, light and dark, against the design references.
- To build a screen, use the **`velix-screen`** skill. To check work, use **`velix-verify`**. For the region pack, **`velix-region-pack`**. For a demo build or a release, **`velix-ship`**. To build, install, launch on and copy logs from Filippo's iPhone, **`velix-phone`**. For commits, PRs, merging and DECISIONS rows, **`velix-pr`**.
- **Where the project stands, and what's next:** `docs/HANDOVER.md` (last updated 8 Nov 2026). Machine and device details: `CLAUDE.local.md` (local, not committed).

## Working agreements with Filippo

- **Plan mode first** for every milestone part; one PR per part.
- **Merge only on his explicit "check CI and merge #N"** (or "go ahead" right after a PR), only with CI green, with `gh pr merge N --merge --delete-branch`. If CI is pending, say so and stop: never poll or schedule CI checks. Stacked PRs merge in stack order; retarget the child to `main` before its parent's branch is deleted.
- **Ask before** any map-style or visual change, new copy, or anything that grows a pack past 320 MB. Otherwise, when he says "you decide", make the call and say why: he wants a recommendation, not a list of open questions.
- **Services must be free, keyless and work globally.** No API keys, no accounts, no paid tiers.
- **Performance beats features:** if something isn't smooth on the iPhone 11, drop it or simplify it.
- **Minimal UI while riding:** icons without labels, little camera motion, no hazard visuals or warnings while riding (set aside 29 Oct).
- **The dark map style is the reference**; light mirrors its rules exactly.
- Install on the phone only after a successful build, and check the .app first. He checks visual work on the iPhone 11 after each feedback round.
- "Do this task here: <title>" means do that suggested task in the current session.
- Reports to him: short plain sentences, bold lead words, numbers in tables, and an explicit "what I need from you" when he has to act.
- Accessibility is part of done: riding targets ≥ 60 pt (else 44), Dynamic Type caps as in HANDOFF, VoiceOver labels from `design/Velix P8 Accessibility.dc.html`.
- Log every product or technical decision (and any deviation from the design) in `docs/DECISIONS.md` with the reason.

## Definition of done (every task)

1. Builds with no warnings in new code; all tests pass.
2. Matches the design reference (snapshot or side-by-side screenshot attached to the PR), light and dark.
3. Tap count checked for the flow touched.
4. No hard-coded values that exist in tokens; no new licence issues.
5. `docs/DECISIONS.md` and this file updated if anything changed.

## Data licences

OSM data (ODbL): show "© OpenStreetMap contributors" on every map; packs are ODbL derived databases, published with the pipeline. OpenFreeMap, Mapterhorn, GEDTM30, Photon and each pack's sources: attribution in You → About. Every licence text of what ships in the app: You → About → Open-source licences (`tools/licenses/licenses.py`, CI-checked against THIRD_PARTY.md). Satellite (online only, never in packs): EOX Sentinel-2 cloudless, CC BY-NC-SA 4.0 (Velix is non-commercial); **Esri dropped 9 Nov 2026** (keyless use in a public app isn't clearly allowed). Transit timetables: Italy's National Access Point in the packs until M11 PR 4, then Transitous (attribution: a visible link to its sources page). Never Google/Bing/Mapbox/Apple/Esri imagery.
