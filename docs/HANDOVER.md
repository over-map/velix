# Velix handover (14 Nov 2026)

This is for a new Claude Code session that knows nothing about the work so far. Read it after `CLAUDE.md`, and keep it current: when an item here is done, strike it or delete it in the same PR.

## 1. Where the project stands
- **`main` is at `927ed9e`** (merge of #62). M11 PR 3 is on the branch `m11-scale`.
- **M0–M9 are done; M10 has two of its four parts merged; M11 "Europe, public release" is half-way:**

| Milestone | State | Notes |
|---|---|---|
| M0–M9 | ✅ | Spike report `docs/spikes/M1_REPORT.md`; golden tests `docs/TEST_TRIPS.md`. Apple Health and Strava dropped (6 Nov) |
| M10 PR 1 Accessibility, PR 2 Performance | ✅ #49, #54, #55 | Numbers in §4 |
| M10 PR 3 Weather notice | ❌ removed | Filippo doesn't want it (8 Nov) |
| M11 PR 1 Public-release hygiene | ✅ #61 | Esri out, licences screen, ODbL on releases |
| M11 PR 2 Regions | ✅ #62 | 219 regions in `pipeline/regions/europe.json`; country-agnostic pipeline; Luxembourg, Lombardy, Paris built under budget |
| **M11 PR 3 Build at scale + signing** | **in review** | §2.2 |
| M11 PR 4 Transitous, PR 5 App for Europe, PR 6 Publish and check | next | `docs/BUILD_PLAN.md` M11 |
| Backlog | after M11 | §2.4 |
| M10 PR 4 Demo build + script | last | §2.5. M10 closes when Filippo signs off the demo |

## 2. What to do next, in order

### 2.1 Phone signing: renew before Mon 16 Nov, 15:32 (Italy)
The free Personal Team profile expires then and the app stops opening on the iPhone. Rebuilding doesn't renew it; the steps are in the `velix-phone` skill, "Rules".

### 2.2 M11 PR 3: after review
- **Before merge (Filippo):** create the `pack-publish` environment (Settings → Environments, required reviewer: himself), run `tools/packkey/new-key.sh`, and commit `pipeline/keys/pack-signing.pub`; copy the same key into `PackSignature.publicKeyBase64`. Without it every install fails "not signed".
- **After merge:** dispatch *Region pack* with `regions: all`, `publish: on`; approve the `sign` job. ≈ 14 h with 20 parallel jobs. Check the index (≈ 330 KB), the pruning log, then update Lombardy on the phone from the signed index. That run is PR 3's acceptance.
- **Order on the phone:** app builds from before PR 3 still read the new index (schema 2 keeps `manifest`) and ignore the `.sig` files. Builds with PR 3 refuse the old unsigned packs, so install a PR 3 build only after the first signed run has published.

### 2.3 M11 PR 4–6
In `docs/BUILD_PLAN.md`. Gaps still open for PR 5: Lombardy/Milan defaults; the northern-Italy Photon bbox; train times in Rome time; tickets that always open Trenitalia; the M1–M5 metro colours; Greek and Cyrillic glyphs; per-pack attribution. For PR 4: the NeTEx out-and-back Trenord runs that restart at 00:00 go away with the NAP timetables.

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
- **Signing on the Mac:** macOS's `/usr/bin/openssl` is LibreSSL and has no `pkeyutl -rawin`; use Homebrew's OpenSSL 3 (`tools/packkey/new-key.sh` picks it).
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
