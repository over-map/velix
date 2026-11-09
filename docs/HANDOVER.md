# Velix handover (8 Nov 2026)

This is for a new Claude Code session that knows nothing about the work so far. Read it after `CLAUDE.md`, and keep it current: when an item here is done, strike it or delete it in the same PR.

## 1. Where the project stands
- **`main` is at `042d2c3`** (merge of #56, this handover). All PRs up to #56 are merged except #35, which was closed and replaced by #38. The working tree is clean, and no PRs or issues are open.
- **M0–M9 are done.** M10 "Polish and showcase" has had two of its four parts merged:

| Milestone | State | Notes |
|---|---|---|
| M0 Repo and toolchain | ✅ | XcodeGen, CI on `macos-26` |
| M1 Tech spike | ✅ go | `docs/spikes/M1_REPORT.md` |
| M2 Region pack | ✅ | 5 Italian regions published, ≤ 320 MB each, `pack-index` release |
| M3 Routing quality | ✅ | Golden tests in `docs/TEST_TRIPS.md` |
| M4 Design system | ✅ | |
| M5 Map styles | ✅ | Standard, Outdoor, Satellite (light only); day/night |
| M6 Core flows | ✅ | |
| M7 Riding | ✅ | Accepted on simulated rides (6 Nov). Hazard alerts while riding set aside (29 Oct) |
| M8 Bike + transit | ✅ | Italy only (offline timetables in packs) |
| M9 Routes, history | ✅ | Apple Health and Strava dropped (6 Nov). GPX share only |
| M10 PR 1 Accessibility | ✅ #49 | |
| M10 PR 2 Performance | ✅ #54, #55 | Numbers in §4 |
| M10 PR 3 Weather notice | ❌ removed | Built (#57), then removed on 8 Nov: Filippo doesn't want it |
| **Bike + train station fix** | **next** | §2.2 |
| M11 Europe | after the fix | §2.3. Not yet in BUILD_PLAN |
| Backlog | after M11 | §2.4 |
| M10 PR 4 Demo build + script | last | §2.5. Moved after M11 and the backlog (8 Nov). M10 closes when Filippo signs off the demo |

- **On the phone:** `main` at b56be08 (with the weather notice, removed since).

## 2. What to do next, in order

### 2.1 Signing: renew before Sun 15 Nov 21:56 (Italy)
The free Personal Team profiles were renewed on 8 Nov (Filippo signed in to Xcode again) and now expire at **2026-11-15 20:56 UTC**. After that the app won't open on the iPhone.
- Rebuilding doesn't renew them. The steps are in the `velix-phone` skill, "Rules". Xcode needs Filippo's Apple ID in Xcode → Settings → Accounts.

### 2.2 Bike + train from south Milan: no suggestion (found 8 Nov)
Via Soave → Monza (Villa Reale) gets no bike + train option at any time, while Porta Venezia → Monza does (RE8, 35 min). The data is fine; the station choice isn't. `DirectPlanner.nearby` keeps the **6 nearest stops per operator within 4 km**, and around Via Soave those are small stations (Scalo Romana, Tibaldi, Romolo, Porta Vittoria, Dateo, Cadorna) with almost no Monza trains. Rogoredo (3.7 km, 11th), Centrale and Garibaldi (4.3 km) are left out. With every rail station within 5 km (metro still capped), Thursday 08:05 gives Garibaldi 08:31 → Monza, door to door 51 min vs 81 by bike, so the trigger fires. Fix it first, then M11.

### 2.3 M11 "Europe" (after the bike + train fix; plan mode; several PRs)
Filippo's choices on 8 Nov aren't in the repo yet. **At the start of M11, add M11 to `docs/BUILD_PLAN.md` and these four choices to DECISIONS:**
1. **Coverage:** packs for the EU, EFTA and the UK, about 250–300 of them.
   - Region configs are generated automatically.
   - Dense areas are split to fit **320 MB per pack**.
   - The whole world comes later.
   - His words (7 Nov): "make sure users can download every pack in the world (or at least in EU)".
2. **Hosting:** stays on GitHub Releases. That means:
   - fixing the index job's 200-release limit;
   - slimming `packs.json`;
   - pruning releases older than about 2 months.
3. **Trains outside Italy:** Transitous online (`api.transitous.org`; free, no key, non-commercial). Italy keeps its offline timetables in the packs. The alternative he allowed was hiding bike + train outside Italy.
4. **Order:** the pipeline comes first. Europe-wide builds sliced per region, which also fixes routing across region borders.

Gaps found on 8 Nov:
- regions sized by data;
- trips that cross regions;
- Italy-only inputs: the extract, UTM 32N, the single synthetic country;
- the index past 200 releases;
- Lombardy/Milan defaults;
- the hard-coded northern-Italy Photon bbox;
- train times always in Rome time;
- tickets that always open Trenitalia;
- the M1–M5 metro colours;
- no Greek or Cyrillic glyphs;
- attribution for each pack;
- smoke trips that each region needs.

### 2.4 Backlog: raised and never decided (ask Filippo when relevant; don't build unasked)
1. **Picking a start point other than the current location.** Asked 19 Oct and 29 Oct: "I can't set an origin and destination in the app, only the destination". DECISIONS (18 Oct) deferred it. `RouteOptionsModel` plans only from `app.location`. This is the most-requested missing feature.
2. **Hazards on the browse map.** 29 Oct: "Perhaps they are more useful in browsing mode and free driving modes… only show cobbles, steps, and steep climbs". There's no free-ride mode, and steep climbs aren't in the pack sidecar.
3. **A cap on long Best detours.** Noted "still to do" on 19 Oct; the Road golden trip 6 tolerance was raised instead.
4. **Unanswered questions from 29 Oct:**
   - keep or remove the "Why this route → On your route" hazard text rows;
   - whether tram *crossings* should count in route scoring (today only rails running along the street do).
5. **The `trenitalia://` URL scheme has never been verified on a device.** It's in `App/Transit/TransitCopy.swift` and falls back to the App Store page.
6. **Unanswered questions from 7 Nov:**
   - the next-turn street tag can sit under the map controls;
   - country and region borders are hidden under satellite imagery.
7. **Riding in landscape.** The app is portrait-only, Filippo asked on 7 Nov and didn't follow up.
8. **An exact battery %/h.** Optional: Filippo said "no more rides". Today's figure is "under 10 %/h".
9. **Outside-region check:** DECISIONS (18 Oct) says it uses the pack bbox ("polygon later"). `coverage.geojson` may already cover this, so check before doing anything.
10. **Local branches:** about 49 are already merged and can be deleted. Ask first. Two have commits not in `main`:
    - `destination-preview` (0617f8f), replaced by #37 "Search first";
    - `phone-test`, scratch commits for phone tests.
    Both can go once Filippo agrees.

**Dropped, don't bring back:**
- Apple Health and Strava;
- the M7 real-ride criterion;
- hazard visuals or voice while riding;
- bevelled building corners;
- wall transparency;
- the cold-start fixes (start is already ≈ 0.15 s);
- dark satellite;
- a map style remembered per ride type (it's per session now);
- more M10 test rides.

### 2.5 M10 PR 4: demo, last (moved after M11 and the backlog on 8 Nov) (plan agreed on 6 Nov: "Script + recorded clips (Recommended)")
- Install a Release build on the phone and run a smoke pass.
- Write `docs/demo/DEMO_SCRIPT.md` for a 60–90 s video in 5 scenes, with **no hazard-alert scene** (alerts while riding were set aside):
  1. commute in 2 taps;
  2. riding;
  3. a long trip with the train suggestion;
  4. a gravel route from Routes;
  5. the ride summary and GPX share.
  Show the OSM attribution.
- Record simulator clips with `xcrun simctl io booted recordVideo` into `build/demo/`. Filippo films or assembles the phone parts himself.
- **M10 closes only when Filippo signs off the demo build.**

## 3. How Filippo works (beyond CLAUDE.md "Working agreements")
- He is the only user and reviewer. He tests on an iPhone 11 after each round and sends feedback as numbered lists, sometimes with screen recordings in `~/Downloads`.
- He often says "you decide" or "disregard my suggestion if you have a better recommendation". Make a recommendation and act on it, then report.
- **"check CI and merge #N"** is the only merge trigger. If CI is still running, say so in a sentence. He'll ask again.
- **"merge when green and continue with the next PR"** lets you carry on by yourself.
- **"install it" / "phone connected, unlocked, launch it"** means build, check the .app, install, launch (velix-phone).
- He reads replies on screen, so keep them short:
  - lead with the outcome;
  - put numbers in a table;
  - end with what he needs to do, if anything.
  - Avoid internal IDs and jargon.
- **Personal project:** use only his personal accounts and tools (see `CLAUDE.local.md`). No company plugins or MCP servers.

## 4. Numbers worth knowing (iPhone 11, 8 Nov, see DECISIONS)
| | |
|---|---|
| Cold start | ≈ 150 ms to the first screen, ≈ 390 ms to the first full map frame. ≈ 1 s on the first launch after an install |
| Riding map | capped at 30 fps (32 measured), 0–3 slow frames per ride. Other maps run at 60 |
| App CPU while riding | 46 % → 41 % of a core over 15 min. 36 % over the 63-min ride |
| Battery while riding | **under 10 %/h** (likely 6–9), down from 18 %/h on the M1 real ride |
| Memory over a ride | 350 → 600–790 MB. It's MapLibre's cache: it drops to ≈ 400 MB in the background |
| Pack size budget | ≤ 320 MB download per region |

## 5. Gotchas that cost hours before
- **Two Xcodes, one Package.resolved.** CI uses Xcode 26.x and the Mac uses Xcode 27, and `swift-custom-dump` 1.7.3 has two manifests. `Package.resolved` must pin both `xctest-dynamic-overlay` 1.13.1 and `swift-issue-reporting` 2.1.2. Don't let Xcode "clean up" either pin.
- **CI's package cache is keyed on Package.resolved.** Changing that file forces fresh downloads, and GitHub sometimes fails them with 504 or "could not connect". Rerun the job; it isn't a code problem.
- **Simulator destination:** `name=iPhone 16,OS=18.0`. Snapshot references come from that device, and re-recording needs two test runs.
- **Profiling:** xctrace's Power Profiler crashes on save in Xcode 27.0, and Activity Monitor hangs. Use the ride log's health line (`cpu`, `fps`, `slow` per minute) and `tools/ride-report`.
- **Battery %:** reported in 5 % steps, held at 100 % for a while after charging. Compare builds on CPU.
- **Phone connection:** "connecting" or "unavailable", or copies that hang, mean it needs replugging, unlocking and Trust. See velix-phone.
- **A hidden map still renders:** the home map sits under the riding screen (fullScreenCover) and keeps drawing. That's why the app location moves only every 100 m while riding.
- **Stacked PRs:** retarget the child to `main` before deleting the parent's branch. #35 was auto-closed that way. Resolve DECISIONS.md conflicts by keeping both sides, newest first.
- **Pipeline:**
  - Docker runs through Colima (12 GB); run `colima stop` when done.
  - Overpass needs a User-Agent (406/504 otherwise).
  - Use the system `/usr/bin/curl`, because another curl's CA bundle lacks GlobalSign R46.
  - The region-pack workflow takes 1–1.5 h per matrix.
- **Testing the installed pack:** `-use-sideloaded` forces the side-loaded copies, so test installed packs without it.

## 6. Files that matter most
- **Rules and context:**
  - `CLAUDE.md`
  - `CLAUDE.local.md` (local only)
  - `docs/BRIEF.md` §8
  - `docs/BUILD_PLAN.md`
  - `docs/DECISIONS.md` (227 rows; read the top 30)
- **Design (read-only):** `design/HANDOFF.md`, `design/README.md`, `design/*.dc.html`
- **Skills:** `.claude/skills/velix-{screen,verify,region-pack,ship,phone,pr}/SKILL.md`
- **App entry points:**
  - `App/VelixApp.swift`
  - `App/AppState/AppModel.swift` (app state)
  - `App/Features/Root/RootView.swift`
  - `App/Features/Ride/RideView.swift` (S1, where the notice shows)
  - `App/Features/Riding/RideSession.swift`
- **Tools:** `tools/ride-report/ride_report.py`, `pipeline/README.md`
