---
name: velix-ship
description: Put Velix on Filippo's iPhone (free Apple ID / Personal Team), prepare a demo build, tag a release, or later prepare TestFlight/App Store. Use when asked to deploy, install on device, ship, release, re-sign, or make a demo build of Velix.
---

# Ship Velix

## Iteration 1: Filippo's iPhone (free Apple ID)
1. Run velix-verify first; everything green.
2. Filippo connects the iPhone (Developer Mode on) and selects his Personal Team in Xcode → Signing. Claude can't sign in to Apple accounts; ask Filippo to do this step.
3. Build and install: `xcodebuild -scheme Velix -destination 'platform=iOS,name=<iPhone name>' -allowProvisioningUpdates build` then install, or Run from Xcode.
4. Remind Filippo: free provisioning expires after **7 days** (re-install), max 3 apps, some capabilities may be unavailable (see M1 findings in docs/DECISIONS.md).
5. First launch on device downloads the region pack; check it on Wi-Fi.
6. Real-ride checklist: commute ride, one hazard-heavy route, screen locked with Live Activity, battery % before/after.

## Release (GitHub)
- Update CHANGELOG.md, bump `MARKETING_VERSION` / build number in project.yml, tag `vX.Y.Z`, create a GitHub Release with notes and screenshots. No secrets in the repo.

## Demo video
- Simulator or device recording (`xcrun simctl io booted recordVideo`), 60–90 s: commute in 2 taps → riding with a hazard alert → long trip with the train suggestion → gravel route in Routes. Show OSM attribution.

## Phase 2 (not now)
Apple Developer Program (€99/yr) → TestFlight → App Store; fastlane for signing and upload; privacy nutrition label ("data not collected").
