# Handoff: Velix, bike navigation (Milan pilot, iteration 1)

## Overview
Velix is an iOS bike navigation app: pick a destination, choose between a calm "Best" route and Fastest (with a bike + train option on long trips), then ride with turn-by-turn guidance, hazard alerts (tram rails, cobbles, door zone, steps…), Live Activity and Dynamic Island. Ride type (City, E-bike, Road, Gravel, MTB, Cargo / kids) drives the routing rules and the map style. Pilot area: Milan / Lombardy, offline pack.

Target stack: **SwiftUI, iOS 17+, MapLibre Native, Ferrostar** (routing + guidance), offline Lombardy pack (220 MB budget).

## About the design files
The files in this bundle are **design references created in HTML**: prototypes showing intended look and behaviour, not production code. Recreate them natively in SwiftUI with MapLibre (or the stack the team settles on). Do not ship or wrap the HTML. The generator scripts (`tools/`) and map data (`data/`) only exist to build the pages.

## Fidelity
**High-fidelity.** Final colours, type, spacing, states, copy and map cartography. Recreate pixel-accurately at 393 × 852 pt (iPhone 15/16). All times, distances, timetables and ride history are illustrative sample data; map geometry is real OSM (OpenFreeMap tiles) and real bike routing (OSRM).

## Start here
1. `Velix P9 Prototype.dc.html`: clickable, 57 light screens, five flows (commute, long trip with transit, routes, You, first launch). Dashed outlines show tap targets.
2. `HANDOFF.md` (included below in full): screens, states, components, every product/visual/accessibility decision with its reason, open engineering questions.
3. `velix-tokens.json`: single source for all values, with Swift names in `meta.swift`.
4. `Velix Handoff Assets.dc.html`: app icon (approved) and the exported glyphs.

## Screens / views
Full screen × state × component table is in HANDOFF.md §2. Per-screen layouts, measurements and both colour modes are in:
- S1 Ride, S2 Search, S3 Route options → `Velix P4 Ride Search Route Options.dc.html`
- S4 Riding, hazard cards, Live Activity, Dynamic Island → `Velix P5 Riding.dc.html`
- S5 Riding with transit, StageStrip → `Velix P6 Riding with Transit.dc.html`
- S7 Routes, S6 Ride summary, S8 You, S0 First launch → `Velix P7 Routes You Summary First Launch.dc.html`
- Component specs and states (light/dark) → `Velix P2 Design System v2.dc.html`
- Map styles and route rendering → `Velix P3 Map Cartography v3.html` (`p3v3/render.js` is the reference for draw order, line widths per zoom and label rules)
- Dynamic Type XL, colour-blind checks, VoiceOver label table → `Velix P8 Accessibility.dc.html`

## Interactions & behaviour
- **Commute = 2 taps:** open → Work (in the search bar) → Start. Best is preselected.
- **Route options:** Best + Fastest cards; single "Best and fastest" card when Fastest is < 5% quicker. Transit row only when it saves ≥ 20 min vs Best.
- **No route meets the rules:** name the blocking rule, link to You. No per-trip relaxing.
- **Riding:** hazard < 50 m → NextHazardCard fills coral, dark ring, 2 haptic taps, voice ≤ 6 words. Weak GPS replaces the card with a notice; alerts still fire. Route behind the rider is trimmed. Views: follow 2D, 3D (pitch 50°), North up, overview.
- **Transit:** late → reroute fastest, notice names the cost; missed → next train; if time allows, back to Best. Notices take the hazard-card slot and show in the Dynamic Island.
- **Lit streets only:** manual, not remembered, switches off when the ride ends.
- **Ride summary:** shares GPX only.
- **Motion:** press scale 0.96 / 120 ms ease-out; sheet snap spring(0.35, 0.86); route draw-in 600 ms, alt fades in 200 ms later; 2D↔3D 450 ms ease-in-out; hazard fill 250 ms; banner slide 250 ms. Reduce Motion fallbacks in tokens `motion`.
- **Accessibility:** riding hit targets ≥ 60 pt (else ≥ 44 pt); riding screens cap Dynamic Type at 115%, sizes ≥ 30 pt don't scale; other screens grow to XL (135%) and reflow.

## State management (main)
- `rideType` (persisted default from onboarding; chip on Ride changes it)
- `rules[rideType]` (You only; defaults in HANDOFF.md / CLAUDE.md #10)
- `litStreetsOnly` (session, cleared at ride end)
- `mapStyle` + overlays (Map button), `voice`, `viewMode` (riding controls)
- `destination`, `routeOptions[]`, `selectedRoute`, `transitPlan` (stages, train times, delay)
- Riding: `position`, `distanceAlong`, `nextManeuver`, `nextHazard`, `gpsQuality`, `rerouting`, `stage`
- Offline region download state; location permission state; connections (Health, Strava…) for ride sync

## Design tokens (from velix-tokens.json 1.1.0 (P2 v2 / P3 v3 · Chart))
### Colour
| Token | Light | Dark | Use |
|---|---|---|---|
| `accent` | #DBF227 | #DBF227 | Your selected route, Start / primary button, current location |
| `accentInk` | #021624 | #021624 | Text and icons on accent |
| `ink` | #021624 | #EEEDD6 | Primary text |
| `ink2` | #2E4A5A | #BFC8C2 | Secondary text |
| `ink3` | #4F6570 | #93A3A6 | Tertiary text, labels |
| `surface` | #FFFFFF | #0A2E45 | Sheets, cards |
| `surface2` | #F1F1E6 | #123A54 | Inset fills, pressed, chips |
| `canvas` | #F7F7EF | #021624 | Screen background behind sheets |
| `line` | #DEDDCB | #1F4862 | Separators, unselected card borders |
| `casing` | #021624 | #021624 | Route casing, marker rings |
| `routeAlt` | #6A808B | #9AA6AA | Non-selected routes (dark raised in P3 v2 for 3:1 vs night roads) |
| `hazard` | #E0532A | #FF7A4F | Hazard tubes, markers, next-hazard card |
| `hazardInk` | #1A0A03 | #1A0A03 | Glyphs and text on hazard |
| `avoided` | #7A4FD6 | #B79CFF | Avoided-road lines |
| `avoidedInk` | #5B34B8 | #CDBBFF | Avoided-road tag text |
| `warningSurface` | #F3EFC2 | #33361A | Severe weather, late / missed notices |
| `warningInk` | #4B4300 | #E6E4A6 | Text on warning surface |
| `success` | #005C53 | #9FC131 | Synced ✓, ready |
| `danger` | #C82C45 | #FF7A88 | End button, failed |
| `dangerInk` | #FFFFFF | #1A0003 | Text on danger |
| `mixProtected` | #4E8A12 | #9FC131 | Protected lane / bike path (solid) |
| `mixPainted` | #0A7F73 | #7FD1C3 | Painted lane (solid + ticks), teal family |
| `mixPaintedTick` | #BFE3DC | #1E5A55 | Painted-lane tick pattern |
| `mixQuiet` | #A9C7A0 | #4E7A55 | Quiet street (solid, light) |
| `mixMixed` | #B0ADAD | #5B7380 | Mixed traffic (solid grey) |
| `mixCobbles` | #8A5A3C | #C4925E | Cobbles (hatched 45°) |
| `mixCobblesAlt` | #D8C4A8 | #4A3424 | Cobbles hatch, second stripe |
| `mixUnpaved` | #E7DFBF | #3A3A22 | Unpaved (dotted), base |
| `mixUnpavedDot` | #8F7A3A | #D6C27A | Unpaved dots |
| `transitTrain` | #415C70 | #B0ADAD | Train legs and lines |
| `transitMetroRed` | #C8102E | #C8102E | Metro colour family red. 2nd line of this family in a city uses alt |
| `transitMetroOrange` | #F08A00 | #F08A00 | Metro colour family orange. 2nd line of this family in a city uses alt |
| `transitMetroYellow` | #F5C400 | #F5C400 | Metro colour family yellow. 2nd line of this family in a city uses alt |
| `transitMetroOlive` | #9C9A2E | #9C9A2E | Metro colour family olive. 2nd line of this family in a city uses alt |
| `transitMetroGreen` | #0F9158 | #0F9158 | Metro colour family green. 2nd line of this family in a city uses alt |
| `transitMetroCyan` | #1AA6C4 | #1AA6C4 | Metro colour family cyan. 2nd line of this family in a city uses alt |
| `transitMetroLightblue` | #5AAEE6 | #5AAEE6 | Metro colour family lightblue. 2nd line of this family in a city uses alt |
| `transitMetroBlue` | #1F5FB5 | #1F5FB5 | Metro colour family blue. 2nd line of this family in a city uses alt |
| `transitMetroPurple` | #9A3A92 | #9A3A92 | Metro colour family purple. 2nd line of this family in a city uses alt |
| `transitMetroPink` | #E46FA8 | #E46FA8 | Metro colour family pink. 2nd line of this family in a city uses alt |
| `transitMetroBrown` | #8A5A2B | #8A5A2B | Metro colour family brown. 2nd line of this family in a city uses alt |
| `transitMetroGrey` | #8C9196 | #8C9196 | Metro colour family grey. 2nd line of this family in a city uses alt |

Metro families, mix-bar patterns, map palettes and map rules: see tokens `palette`, `pattern`, `mapStyle`, `mapRules`, `mapLine`.

### Type
| Token | Family | Weight | Size/LH (pt) | Tracking | Numbers | Dynamic Type |
|---|---|---|---|---|---|---|
| `display` | Familjen Grotesk | 700 | 34/40 | -0.01em |  | full range |
| `title1` | Familjen Grotesk | 700 | 28/34 | -0.01em |  | full range |
| `title2` | Familjen Grotesk | 700 | 22/28 | 0 |  | full range |
| `headline` | Familjen Grotesk | 700 | 17/22 | 0 |  | full range |
| `body` | Atkinson Hyperlegible | 400 | 17/24 | 0 |  | full range |
| `bodyBold` | Atkinson Hyperlegible | 700 | 17/24 | 0 |  | full range |
| `callout` | Atkinson Hyperlegible | 400 | 15/20 | 0 |  | full range |
| `footnote` | Atkinson Hyperlegible | 400 | 13/18 | 0 |  | full range |
| `caption` | Atkinson Hyperlegible | 700 | 12/16 | 0.04em |  | full range |
| `numberL` | Familjen Grotesk | 700 | 30/32 | -0.01em | tabular | full range |
| `numberM` | Familjen Grotesk | 700 | 24/28 | 0 | tabular | full range |
| `ridingBigNumber` | Familjen Grotesk | 700 | 56/56 | -0.02em | tabular | capped at xxLarge (+35%) |
| `ridingNumber` | Familjen Grotesk | 700 | 34/36 | -0.01em | tabular | capped at xxLarge (+35%) |
| `ridingStreet` | Familjen Grotesk | 700 | 24/28 | 0 |  | capped at xxLarge (+35%) |
| `ridingLabel` | Atkinson Hyperlegible | 700 | 17/22 | 0 |  | capped at xxLarge (+35%) |

### Spacing
`xxs` 4 · `xs` 8 · `s` 12 · `m` 16 · `l` 24 · `xl` 32 · `xxl` 48

### Radius
`chip` 8 · `card` 16 · `sheet` 24 · `capsule` 999

### Elevation
- e1 light: y 2, blur 6, #021624 15% · dark: 1 pt border #1F4862
- e2 light: y 8, blur 20, #021624 12% · dark: border #2C5870 + y 8 blur 20 #021624 50%
- e3 light: y −8, blur 24, #021624 8% (bottom sheets) · dark: border #1F4862

### Touch targets
min 44 pt · riding 60 pt

## Assets
- `assets/lucide/`: the 39 Lucide icons used (ISC licence), 24 px grid, 2 px stroke, `currentColor`.
- `assets/glyphs/`: custom glyphs on the same grid/stroke: 6 ride types, 10 hazards, train, EuroVelo badge (number set at runtime; not the registered ECF panel).
- `assets/app-icon/`: **approved 11 Oct (1a, header V).** SVG masters (default, dark, tinted) + PNG at 1024, 180, 167, 152, 120, 87, 80, 76, 60, 58, 40, 29, 20. Full-bleed squares; iOS applies the mask.
- Map markers (hazard marker, route key tile, start/end, station dot, heading puck): drawn in code, spec in `p3v3/render.js`.
- Fonts: Atkinson Hyperlegible 400/700, Familjen Grotesk 500/600/700 (both OFL, Google Fonts). Bundle in the app.
- No SF Symbols, no TomTom or third-party brand assets. Satellite imagery open data only (see HANDOFF.md).

## Files
- `Velix P2 Design System v2.dc.html` … `Velix P9 Prototype.dc.html`: design references (open in a browser; `support.js` is the runtime)
- `velix-tokens.json`: tokens
- `p3v3/`, `p4/maps.js`, `data/`: map renderer and data the pages load
- `tools/`: page generators (reference only)
- `assets/`: exported SVG/PNG

---

# Appendix: HANDOFF.md

Target: SwiftUI, iOS 17+, MapLibre Native, Ferrostar (routing + guidance), offline Lombardy pack.
Prototype: `Velix P9 Prototype.dc.html` (open it, use Flows or All screens; dashed outlines are the tap targets).
All times, distances, timetables and ride history are sample data from the brief, labelled illustrative. Map geometry is real OSM data (OpenFreeMap tiles) and real bike routing (OSRM bike profile).

## 1. Files

| File | What it is |
|---|---|
| `velix-tokens.json` (1.1.0) | Colours light/dark, metro families, type, spacing, radii, elevation, motion, map line widths, map palettes, map rules. Swift names in `meta.swift`. |
| `Velix P2 Design System v2.dc.html` | Tokens, type scale, icons + custom glyphs, every component in 03 with states, light and dark. |
| `Velix P3 Map Cartography v3.html` + `p3v3/palettes.js`, `p3v3/render.js` | Map styles (Standard, Outdoor, Satellite × day/night), overlays, all route/hazard rendering, layer-by-layer spec. `render.js` is the reference implementation of draw order, widths per zoom and label rules. |
| `Velix P4 Ride Search Route Options.dc.html` | S1 Ride (+ sheets), S2 Search, S3 Route options. |
| `Velix P5 Riding.dc.html` | S4 Riding, controls, all hazard cards, Live Activity, Dynamic Island. |
| `Velix P6 Riding with Transit.dc.html` | S5, StageStrip, transit Live Activity. |
| `Velix P7 Routes You Summary First Launch.dc.html` | S7 Routes, S6 Ride summary, S8 You, S0 First launch. |
| `Velix P8 Accessibility.dc.html` | Dynamic Type XL, colour-blind simulation, VoiceOver label table, fixes. |
| `tools/p*gen.js`, `p4/maps.js`, `data/*.json` | Generators and map data used to build the pages. Not production code. |

## 2. Screens and components

| Screen | States | Components (names from 03) |
|---|---|---|
| S0 First launch | location ask / system prompt / denied; ride type; download on cellular / done / failed | `OnboardingStep`, `RideTypePicker` (onboarding), `OfflineRegionRow` |
| S1 Ride | normal + severe weather; panned; Home/Work unset; downloading; outside region; no GPS | `SearchBar`, `RideTypeChip`, `MapButton`, `RecenterButton`, `NoticeBanner` (severe weather), `TabBar` |
| S1 sheets | ride type; map styles City / Gravel | `RideTypePicker`, `MapStyleSheet` |
| S2 Search | focused; typing; first use; no results; offline | `SearchBar` (focused), result rows |
| S3 Route options | Best + Fastest; Why this route; single card; bikes + transit row; Bike + train selected; no route meets rules; computing; lit streets only; Cargo / kids; Gravel | `RouteCard`, `ComfortMixBar`, `DifferenceLine`, `WhyThisRoute` (`HazardRow`, `AvoidedRow`), `TransitSuggestionRow`, `TransitCard` + `TripBar` + `TransitLegList` |
| S4 Riding | 2D, 3D, North up, overview; approaching hazard; avoided near rider; rerouting; weak GPS; arriving; panned | `ManeuverBanner`, `RoadTypePill`, `MapControlStack`, `NextHazardCard`, `EtaBar`, `LiveActivity` |
| S5 Riding with transit | stage 1; late → fastest; missed → next train; on the train; stage 3 | `ManeuverBanner` (StageStrip), `NoticeBanner` (late, missed), `OnTrainCard` |
| S6 Ride summary | synced; not connected; data issue | `RideSummary`, `ConnectionRow` |
| S7 Routes | list (Fits type / All); focus from map; selected; Ride this route; searched area; no routes for filter; outside region | `FilterChips`, `RouteListCard`, EuroVelo badge |
| S8 You | all sections, current ride type expanded | `RuleToggleRow`, `RideRow`, `ConnectionRow`, `OfflineRegionRow` |

All screens exist in light and dark (riding with transit and the Live Activity included), at 393 × 852.

## 3. Decisions and reasons

Product
- **Commute = 2 taps** (open → Work → Start). Best is preselected; ride type comes from the chip.
- **One place per setting.** Ride type: chip on Ride (onboarding sets the default). Rules and lit streets: You. Voice and view: riding controls. Map style: Map button. No setting appears twice.
- **No comfort score.** Route cards show time, km, mix bar and a difference line. Scores invite argument; differences explain.
- **Fastest is compared by difference, never ranked.** Single “Best and fastest” card when Fastest is under 5% quicker, with one line saying why.
- **Transit suggestion** only when it saves ≥ 20 min against Best; one outlined row below the bike cards, so it is visible but secondary.
- **No route meets the rules:** say which rule blocks and link to You. No “relax for this trip” (a hidden second place for rules).
- **Lit streets only** is manual, not remembered, and switches off when the ride ends. A night-time rule shouldn’t follow you into the morning.
- **Late / missed train** handled without a question (you’re riding). Each notice names its cost (“adds 120 m of cobbles”). After a missed train with time to spare, Velix goes back to Best.
- **Ride summary shares GPX only.** No image generator, no social layer.
- **Routes → Ride this route:** one card covering the approach and the route; no Fastest card.

Visual
- **Chart direction:** navy/khaki night chart, paper day chart, chartreuse `#DBF227` accent = your route, always with ink casing. Toggle “on” uses ink, never accent.
- **Hazards use `hazard` coral**, avoided roads use `avoided` lilac, never `danger`. Red is reserved for End.
- **Route lists:** numbered keys instead of a colour per route, so accent keeps one meaning. The focused route is wider with a white halo and its key fills accent.
- **Multi-leg trips:** the train leg is the route colour with dashed ink ties; stations are accent dots with an ink ring. The whole trip reads as one route.
- **Car roads are never coloured.** Cycling infra from z14 in base styles; the Bike lanes overlay from z11.
- **Metro = 12 colour families** for every European network (OSM `colour` snapped by OKLCH); no operator hex needed.
- **EuroVelo:** one Velix badge for all 17 routes (not the registered ECF panel). Route list re-checked yearly.
- **Satellite is open data only:** Sentinel-2 mosaic z0–13, national open orthophotos z14+, crossfade to Standard where there is no ortho. Never Esri/Google/Bing/Mapbox/Maxar/Apple.
- **Fonts:** Atkinson Hyperlegible (body, numbers) + Familjen Grotesk (headings, big numbers), both OFL. **Icons:** Lucide (ISC) + custom glyphs on the same 2 px stroke. No SF Symbols.

Accessibility
- Riding targets ≥ 60 pt, big numbers ≥ 34 pt (maneuver distance 56 pt).
- Riding screens cap Dynamic Type at 115%; sizes ≥ 30 pt never scale. Other screens grow to XL (135%) and reflow.
- Mix bar carries patterns (ticks, hatch, dots) and the difference line names the surface in words.
- Map lines are hidden from VoiceOver; every line has an accessible twin (card, hazard row, route key). Full label table in P8.
- Contrast: text WCAG AA; every map line ≥ 3:1 against land and street fill on all 6 styles.

## 4. Open questions for engineering

1. **Ferrostar + rules.** Can the rule set per ride type (no cobbles, tram rails, bike lanes only, max grade, steps) be expressed as Valhalla costing on-device, and how fast is a reroute on an iPhone 12?
2. **Tram-rail data.** Crossings come from OSM `railway=tram` geometry intersecting the route; “rails along the lane” needs a parallel-distance check. Confirm accuracy in Milan.
3. **Custom tile sources** (`velix_cycling`, `velix_transit`, `velix_pois`, `velix_landmarks`, `velix_shadows`) to fill OpenMapTiles gaps: build pipeline and pack size impact on the 220 MB Lombardy budget.
4. **Transit timetable.** Trenord GTFS (static) is enough for planning; real-time delays for “late / missed” need GTFS-RT or a scrape. Which feed, and the offline fallback?
5. **Haptics.** Is the two-tap hazard pattern distinct on a handlebar mount? Core Haptics test needed.
6. **Live Activity update rate.** 10 m updates while riding versus the ActivityKit budget; push vs local updates.
7. **Data-issue report** (S6): where does it go (OSM note, own backend)? No account exists, so sending must stay anonymous.
8. **Weather warnings:** source (MeteoAM / ARPA Lombardia CAP feed?) and polling cadence.
9. **Satellite z14+ licensing** per country (AGEA CC BY 4.0 confirmed for Italy; others to check) and the Sentinel-2 yearly mosaic build.

## 5. Assets to export

- **Icons:** Lucide set used (navigation, route, circle-user-round, search, house, briefcase, layers, locate, locate-fixed, locate-off, x, chevron-*, volume-*, rotate-3d, compass, flag, timer, train-front, lamp, cloud-lightning, map-pin-off, download, wifi-off, search-x, route-off, circle-check, share, message-square-warning, shield-check, activity, heart, map, vibrate, satellite-dish, loader, bike) as SVG, 24 px grid, 2 px stroke.
- **Custom glyphs** (same grid and stroke): 6 ride types (City, E-bike, Road, Gravel, MTB, Cargo / kids); 10 hazards (tram crossing, rails along lane, cobbles, lane ends, dismount, steps, narrow gap, steep descent, steep climb, door zone); train; EuroVelo badge. Source paths are in `tools/p4gen.js` (`GL`, `TRAIN`, `COB`) and `tools/p5gen.js` (`HZ`).
- **Map markers:** hazard marker (rounded tile + dark ring + pointer), route key tile, start/end, station dot, puck with heading: draw specs in `p3v3/render.js`.
- **Fonts:** Atkinson Hyperlegible 400/700 (OFL), Familjen Grotesk 500/600/700 (OFL). Bundle in the app; both are on Google Fonts.
- **App icon:** approved 11 Oct (1a, header V): chartreuse tile, abyss stroked V; dark and tinted variants. Files in `assets/app-icon/` (1024 master + iOS sizes).

## 6. Checklist (05) status

- Coverage: all S0–S8 screens and states, light and dark; four route-option cases; riding views, hazards, rerouting, arrival, Live Activity, Dynamic Island; transit stages, late, missed, on the train; six ride types with “best” names and map style per type; no bike-share. ✓
- Simplicity: commute 2 taps; ride type in one place; no duplicated settings. ✓
- Quality: AA text, map lines ≥ 3:1, patterns + legend, riding sizes, XL checked, VoiceOver table, open licences only. ✓
- Package: tokens ✓, map style specs ✓, glyph SVGs ✓ (assets/), fonts ✓, app icon ✓ (1a approved), this file ✓, prototype ✓.

