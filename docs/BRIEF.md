# Velix: concept brief (v1.0, 8 Oct 2026)

Status: discovery and UX prototyping done (prototype round 9). This file is the source of truth for the Claude Design kit (`claude-design/`) and the Claude Code instructions that come next. Section 8 holds the current decisions; section 9 keeps the history.

## 1. Vision

Velix is a bike navigation app for people who ride in cities (commuters first) and for sport riders. It chooses routes by **how a ride feels**: bike-lane share, surface, tram rails, traffic exposure and slopes. It explains every route choice and warns about hazards while you ride.

Promise: **ride smooth.**

## 2. Who it is for (iteration 1)

| Segment | Main need | Velix answer |
|---|---|---|
| Urban commuter (core) | Safe, calm, predictable daily trip in 2 taps | Best route per ride type, "why this route", hazard alerts |
| Long-distance urban / suburban rider | Cross a big city, reach a neighbouring town or a regional park | Bike + transit suggestion (train, metro) when it helps |
| Sport rider (road, gravel, MTB) | Right surface, scenery, trails | Ride types with their own "best", Outdoor map, Routes tab |
| E-bike rider | Flowing streets, range | E-bike ride type |
| Parent / cargo rider | Step-free, gentle, lanes only | Cargo / kids ride type with strict rules |

## 3. What makes it different

1. **Best route per ride type**, compared with the fastest by difference: "+5 min · avoids 420 m cobbles, 3 rail crossings".
2. **The map explains the choice**: hazards on your route as striped tubes and markers; avoided nearby roads tagged with the reason.
3. **Hazard alerts while riding**: tram rails, cobbles, lane ends / mixed traffic, dismount zones, steps and barriers, steep descents.
4. **Multimodal when it matters**: "Long ride? Hop on the train with your bike", only on trips where it helps.
5. **Simple**: commute = open → Work → Start. One place for each setting.
6. **Private and open**: no account, data on the phone, open data and open-source stack.

Competitors to study: Komoot, Bikemap, Geovelo, bbbike, Cyclers, Naviki, Google Maps (bike), Apple Maps (cycling), Cyclemate.

## 4. Scope

### Iteration 1 (phase 1, €0 showcase)
- iPhone only (free Apple ID install) + demo video. Pilot: **Milan** (Lombardy region pack).
- Six ride types; Best + Fastest; why-this-route; turn-by-turn with hazard alerts (EN voice, haptics, Live Activity); bike + transit (train + metro) as a suggestion; Routes tab (OSM cycle routes); ride history, GPX share, Strava + Apple Health auto-sync; map styles per ride type + overlays; severe-weather notice; lit-streets-only rule (manual, off at ride end).
- Routing **offline only** on the phone; the region pack (~220 MB) downloads at first launch.

### Phase 2 (store fees only)
- App Store, later Android. Online-first routing with offline fallback (same engine on a server). All of Italy, then Europe.

### Parked
- **Bike-share** (multi-provider GBFS map, closest bike, reserve → walk & unlock → ride & park → end in operator app). Flow designed; see history.
- Accounts, social, user-published routes, phone-as-sensor roughness, Apple Watch, e-MTB / e-cargo as separate types.

## 5. Architecture (iteration 1)

| Layer | Choice | Notes |
|---|---|---|
| App | Swift / SwiftUI, iOS 17+ | Android later (Kotlin/Compose) |
| Navigation core | Ferrostar (Rust core, BSD-3) | Route progress, off-route, rerouting |
| Map renderer | MapLibre Native iOS | Velix map styles (Standard, Outdoor, Satellite; day/night) |
| Map tiles | OpenFreeMap vector tiles (no key) | Offline tiles in phase 2 |
| Routing | Valhalla on device (valhalla-mobile), behind a `RoutingProvider` interface | Server provider added in phase 2 |
| Routing data | Valhalla tiles built monthly by GitHub Actions from a Geofabrik extract, published as GitHub Release | ~220 MB for Lombardy (to measure) |
| Hazard layer | Sidecar file in the region pack (tram rails, crossings, steps, barriers, cobbles, dismount zones) from OSM | Drives alerts, tubes and "why" |
| Comfort score | On device from Valhalla edge attributes + hazard layer | Used to rank and to write the difference line |
| Elevation | Copernicus GLO-30 | Contours/hillshade for Outdoor style too |
| Transit | GTFS (Trenord, ATM metro) + curated bikes-allowed rules | Platforms are "planned" only |
| Search | Photon (public instance) | Self-host later |
| Weather | MeteoAlarm / Open-Meteo warnings (to verify) | One notice on app open |
| Satellite | Source and licence to verify (Lombardy orthophoto WMS, Sentinel-2) | |
| Storage | SwiftData on device, iCloud backup | No account |
| Integrations | HealthKit, Strava API | Auto-sync after each ride |

## 6. Next steps

1. **Claude Design**: design system, map styles and all iteration-1 screens, using `claude-design/`.
2. **Routing spike** (can run in parallel): Lombardy Valhalla tiles, six ride types on 10 Milan trips, hazard layer, pack size, transit triggers.
3. **iPhone tech spike**: SwiftUI + Ferrostar + MapLibre + valhalla-mobile, one real ride.
4. **Claude Code**: build, test and deploy from the Claude Design handoff.

## 7. Open risks

- Quality of OSM surface and lane data in Milan.
- Size and battery cost of on-device Valhalla.
- Bikes-allowed rules for trains and metro must be curated; platforms not confirmed.
- Licences for satellite imagery and weather warnings.
- iOS free-provisioning limits (7-day re-sign).
- "Velix" needs a trademark and domain check.

## 8. Current decisions (iteration 1)

| Topic | Decision |
|---|---|
| Simplicity rule | Commute = open → Work → Start (2 taps). Every screen is judged by taps and decisions removed. One place per setting |
| First launch | Location → usual ride type → download region (map explorable meanwhile; first route after download) |
| Tabs | Ride, Routes, You |
| Ride (home) | Map first. Search bar "Where to?" with Home and Work buttons inside it; recents after tapping the bar. Ride-type chip bottom-left (the only place to pick the ride type). Map button (styles + overlays). Severe-weather notice when relevant |
| Ride types | City, E-bike, Road, Gravel, MTB, Cargo / kids. Each has its own "best" ("Calmest for city", "Best for e-bike", "Smoothest asphalt", "Most scenic", "Most off-road", "Step-free and smooth") and rules editable in You. No garage of owned bikes |
| Route options | Best (named by ride type) + Fastest, compared by difference. One "Best and fastest" card when fastest is <5% quicker. "Why this route" on the map always, as a list on tap |
| Explain the route | Hazards on route: striped tubes + markers. Avoided roads: dashed red + reason tag |
| Bike + transit | No switch. Computed in the background; ONE highlighted suggestion row under the bike routes when a trigger fires: saves ≥20 min or ≥30%; or bike-only >45 min / >12 km and saves ≥10 min; or avoids ≥200 m climbing; or destination outside the city area. Never under 5 km. Trains + metro only, bikes-allowed connections only. Copy: "Long ride? Hop on the train/metro with your bike". Tapping expands: timeline, legs, train, planned platform ("check the board"), bikes allowed, next trains, one ticket link. No memory per destination |
| Riding (own bike) | Apple Maps-like. Maneuver banner + "Then…" + road-type pill. Map controls: Voice (All / Alerts only / Mute), View (2D follow / 3D follow / North up), Route overview. Next hazard card floats above the bottom bar. Bottom: arrival, minutes, km, End. Auto-end on arrival. No comfort number while riding. Avoided roads shown only near the rider |
| Riding with transit | Stages: Ride to station → On the train → Ride. Late → switch to fastest automatically with a notice of the cost. Still missing → next train automatically with a notice. On the train: get off in X min, stops, carriage position, buzz before the stop |
| Ride summary | Shown once after a ride: km, moving time, climb, synced to Strava and Health, report a data issue, Share (GPX), Done |
| Routes tab | OSM cycle routes near you; filters: Fits {ride type}, All, Paved, Gravel, MTB; "Search routes in this area"; Ride this route = plan to nearest point, then follow |
| You | Ride types and rules; Lit streets only (switch; turns off when the ride ends); your rides; connections (Strava, Apple Health); offline map (region, size, auto-update); privacy line |
| Map styles | Follow the ride type, everywhere: City/Road/Cargo → Standard or Satellite; Gravel/MTB/E-bike → Outdoor or Satellite. First is default; choice remembered per type. Overlays: bike lanes, train & metro lines. Set only before riding. No traffic overlay |
| Weather | No overlay. One severe-weather notice on app open |
| Data | Local only, no account. Voice English only |
| Name / repo | Velix, "ride smooth". Public GitHub, permissive licence |

## 9. History (superseded, kept for context)

- Round 1: three alternatives, sliders, loop generator, hazard simulation → simplified.
- Round 2: trip-type start screen (My bike / Bike-share / Bike + train) → replaced by map-first home (round 4).
- Rounds 2–3.4: bike-share flow (GBFS multi-provider map, closest bike, reserve before walking with free-hold warning, Walk & unlock → Ride & park → End ride in operator app, trip ends) → parked for a later iteration.
- Round 4: Bike + train as automatic third card; rules per bike; Rides tab → refined in rounds 5–8.
- Round 5: greyed-out transit card → rejected. Round 6: transit switch in the bike chip → rejected. Round 7: suggestion row (current).
- Rounds 4–7: "My bikes" garage (owned bikes) → replaced by six ride types (round 8).
- Round 7: Routes default Outdoor → replaced by style per ride type (round 9).
