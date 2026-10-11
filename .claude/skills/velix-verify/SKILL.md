---
name: velix-verify
description: Verify Velix work before a commit or PR — build, unit/golden/snapshot tests, simulator screenshots, simulated rides, accessibility and licence checks. Use after any code change, before marking a BUILD_PLAN task done, or when asked to "check", "test" or "verify" Velix.
---

# Verify Velix changes

Run in this order; stop and fix at the first failure.

1. `xcodegen generate` (if project.yml or files changed).
2. Build: `xcodebuild -scheme Velix -destination 'platform=iOS Simulator,name=iPhone 16' build`. No new warnings in touched code.
3. Tests: `xcodebuild … test`. Includes unit tests, **golden route tests** (docs/TEST_TRIPS.md), and **snapshot tests** (light and dark). If a snapshot changes on purpose, re-record it and explain why in the PR.
4. **Simulated ride** for anything touching navigation: boot the simulator, install, run `xcrun simctl location booted start --speed=5 …` with a route from Tests/Fixtures/gpx, and check maneuvers, hazard alerts (< 50 m: coral card, haptics, voice), rerouting (drive off route) and auto-end on arrival. Capture `xcrun simctl io booted screenshot`.
5. **Design match:** compare screenshots with the design reference for the screens touched (see velix-screen step 9).
6. **Accessibility:** run the Accessibility Inspector audit on touched screens; check Dynamic Type at the caps from HANDOFF; VoiceOver labels present.
7. **Licences:** any new dependency or asset has an OSI/OFL/ISC/CC licence and is listed in THIRD_PARTY.md; no SF Symbols, no TomTom or closed assets; OSM attribution visible on maps.
8. **Simplicity:** count taps for the flow touched; commute must stay at 2.

Report: what passed, what failed, screenshots, and anything you couldn't verify (e.g. needs a real device or a real ride). Never claim a real-device check you didn't do.
