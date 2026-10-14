# Decisions log (build)

Product decisions live in `BRIEF.md` §8 and `../design/HANDOFF.md` §3. Log here every decision taken while building, and every deviation from the design, newest first.

| Date | Decision | Reason | Who |
|---|---|---|---|
| 2026-10-14 | M1 GO confirmed by a real ride (49 min, 28 reroutes ≤ 106 ms, no crash, battery 100 → 85 %); supersedes the 12 Oct "real-ride checks move to M7" entry | All M1 criteria now measured on the iPhone 11 | Filippo + Claude |
| 2026-10-14 | M7: own CoreLocation provider with `pausesLocationUpdatesAutomatically = false` during a ride | 2.5-min log gap while stationary on the real ride | Claude |
| 2026-10-14 | M7: reroute back-off when the rider keeps ignoring the route, several consecutive off-route fixes, and keep the old route when a reroute fails. Voice on a locked screen still to check in M7 | Real ride: 28 reroutes while Filippo rode his own way on purpose (every 7–10 s); one failed reroute; sound was off | Claude |
| 2026-10-12 | M1 closed as GO without the real ride; real-ride checks (20-min stability, battery unplugged, locked screen + Live Activity, real reroutes) move to M7 acceptance, which already requires 3 real rides in Milan | Routing criteria met on iPhone 11 with > 10× margin; Filippo can't ride this week and doesn't want to wait. Risk: a real-ride problem (battery, background) surfaces later, after UI is built on top | Filippo |
| 2026-10-12 | M1 recommendation: GO on on-device Valhalla; real 20-min ride (stability, battery, locked screen) still to do | iPhone 11 routes 2–25 km in ≤ 215 ms (first call) / ≤ 61 ms warm; reroute 8 ms; see docs/spikes/M1_REPORT.md | Claude (Filippo to confirm) |
| 2026-10-12 | Spike tiles side-loaded into the app's Documents, not bundled in the debug build (BUILD_PLAN M1 says bundle) | Keeps 70 MB out of every build and CI; matches how the downloaded pack will be read in M2 | Claude |
| 2026-10-12 | Valhalla tiles built with the official `ghcr.io/valhalla/valhalla:3.9.0` image | Same Valhalla version as valhalla-mobile 0.6.3, so the tile format matches | Claude |
| 2026-10-12 | Local Docker engine: Colima (MIT) instead of Docker Desktop | No account or licence terms; same `docker` CLI | Claude |
| 2026-10-12 | Bundle id `io.github.over-map.velix` (extension `.LiveActivity`) | Personal GitHub namespace; replaces placeholder `dev.velix.app` | Claude |
| 2026-10-12 | Free Personal Team: no App Groups; Live Activity fed by local ActivityKit updates only | App Groups entitlement refused by the team profile; HealthKit and Live Activity work | Claude |
| 2026-10-12 | Pack size is an M2 risk: Lombardy bbox tiles 370 MB raw / 145 MB gzip vs 220 MB budget | Measured in M1; options listed in M1_REPORT.md | Claude |
| 2026-10-12 | Debug spike screen uses Ferrostar's stock navigation UI (contains SF Symbols); not in release builds | Spike only; Velix riding components replace it in M7 | Claude |
| 2026-10-12 | M7 must end the ride on distance to destination (≈ 30–50 m), not only Ferrostar's arrival step | Simulator run stopped 50 m from the route end and never auto-ended | Claude |
| 2026-10-11 | Licence Apache-2.0 | Permissive with a patent grant; compatible with all dependencies | Filippo |
| 2026-10-11 | `.xcodeproj` not committed (XcodeGen), except `Package.resolved` | Generated file never hand-edited; resolved versions must stay reproducible | Claude |
| 2026-10-11 | All direct SPM deps pinned with `exactVersion`; valhalla-mobile 0.6.3, not 0.6.4 | 0.6.4 was 5 days old at M0; take it after the M1 spike if needed | Claude |
| 2026-10-11 | Familjen Grotesk bundled as static Medium/SemiBold/Bold cut from the OFL variable font (fontTools instancer) | google/fonts ships only the variable font; static files give stable PostScript names and reliable weights in SwiftUI. HANDOFF lists 500/600/700 though tokens use 700 only | Claude |
| 2026-10-11 | Local destination `iPhone 16, OS=18.0`; CI on `macos-26` picks iPhone 16 / iOS 18 when present, else newest iPhone; snapshots compared at 99% precision / 98% perceptual | Xcode 26 defaults to iOS 26.5 which has no iPhone 16; design reference is 393 × 852; small tolerance absorbs runtime anti-aliasing differences | Claude |
| 2026-10-11 | `-skipMacroValidation` on xcodebuild | MapLibre SwiftUI DSL (through Ferrostar) uses a Swift macro that Xcode otherwise refuses to run on the command line / CI | Claude |
| 2026-10-11 | Temporary `App/DesignSystem/Bootstrap.swift` with 4 token values | M0 launch view needs colours/fonts before TokenGen exists; delete in M4 | Claude |
| 2026-10-11 | Placeholder bundle id `dev.velix.app` | Final id after Filippo's personal GitHub/Apple ID is known (M1 / velix-ship) | Claude |
| 2026-10-11 | Lit streets only: follow the handoff (manual switch in You, off at ride end), not remembered | Confirmed by Filippo | Filippo |
| 2026-10-11 | Brief vs handoff conflicts resolved as in CLAUDE.md "Decision overrides" (no comfort score; multi-trigger transit) | Filippo's explicit answers in discovery take precedence over design-time choices | Filippo + Claude |
