# Decisions log (build)

Product decisions live in `BRIEF.md` §8 and `../design/HANDOFF.md` §3. Log here every decision taken while building, and every deviation from the design, newest first.

| Date | Decision | Reason | Who |
|---|---|---|---|
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
