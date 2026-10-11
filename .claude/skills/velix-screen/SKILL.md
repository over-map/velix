---
name: velix-screen
description: Build or change a Velix SwiftUI screen or component so it matches the Claude Design handoff. Use whenever implementing S0–S8 screens, any component from design/HANDOFF.md §2, map layers that show routes or hazards, or when fixing a visual mismatch with the design references.
---

# Build a Velix screen from the design handoff

1. **Find the reference.** Map the screen to its design file (design/README.md "Screens / views"): S1–S3 → P4, S4 → P5, S5 → P6, S0/S6/S7/S8 → P7, components → P2, map → P3 + p3v3/render.js, accessibility → P8. Open the HTML in a browser (or read its source) and list every state shown for the screen.
2. **List states and components** from design/HANDOFF.md §2 before writing code. Use the exact component names; reuse existing components in App/DesignSystem before creating new ones.
3. **Tokens only.** Colours, fonts, spacing, radii, elevation, motion come from the generated `Color.velix.*`, `Font.velix.*`, `CGFloat.velix.*`. If a value is missing, add it to the generator from velix-tokens.json; never hard-code it.
4. **Copy** comes verbatim from the design file. If you need new copy, flag it in the PR.
5. **Layout at 393 × 852 pt**, light and dark. Riding screens: targets ≥ 60 pt, Dynamic Type capped at 115%, sizes ≥ 30 pt don't scale. Other screens: grow to XL (135%) and reflow.
6. **Accessibility:** VoiceOver labels from the P8 table; map lines hidden from VoiceOver, with an accessible twin (card, hazard row, route key).
7. **State lives outside views** (observable models per feature); views are thin and previewable with sample data from design/HANDOFF (illustrative Milan data).
8. **Previews + snapshots:** one SwiftUI preview per state, and a snapshot test per state in light and dark (Tests/Snapshots).
9. **Compare:** render the screen in the simulator, take a screenshot, and compare it side by side with the design reference. Fix differences in spacing, type, colour and copy before opening the PR. Attach both images to the PR.
10. **Check the rules:** tap count for the flow, one place per setting, no bike-share, no SF Symbols.
