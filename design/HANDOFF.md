# Velix: handoff (iteration 1, Milan pilot)

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
- **App icon:** approved 11 Oct (1a, header V; 8 alternatives explored in `Velix App Icon Exploration.dc.html`), exported to `design_handoff_velix/assets/app-icon/`: the “V” tile (chartreuse, 2 px ink casing) from the page headers, at 1024 px master + iOS sizes (180, 167, 152, 120, 87, 80, 76, 60, 58, 40, 29, 20) and dark/tinted variants.

## 6. Checklist (05) status

- Coverage: all S0–S8 screens and states, light and dark; four route-option cases; riding views, hazards, rerouting, arrival, Live Activity, Dynamic Island; transit stages, late, missed, on the train; six ride types with “best” names and map style per type; no bike-share. ✓
- Simplicity: commute 2 taps; ride type in one place; no duplicated settings. ✓
- Quality: AA text, map lines ≥ 3:1, patterns + legend, riding sizes, XL checked, VoiceOver table, open licences only. ✓
- Package: tokens ✓, map style specs ✓, glyph SVGs ✓ (design_handoff_velix/assets/), fonts ✓, app icon ✓ (1a approved, assets/app-icon), this file ✓, prototype ✓.
