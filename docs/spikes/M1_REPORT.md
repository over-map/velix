# M1 tech spike: report (12 Oct 2026)

Go/no-go gate from `docs/BUILD_PLAN.md` M1: **route < 2 s, reroute < 2 s, app stable on a real ride.**

## Decision: GO (14 Oct), all criteria met

Filippo rode it in Milan on 14 Oct (below), so every M1 criterion is now measured on the iPhone 11.

## Recommendation: GO

On-device Valhalla is 10–100× faster than the target on an iPhone 11 (2019, A13), the oldest phone we care about. Ferrostar takes the on-device route through its custom route provider, rerouting works, and a Live Activity runs on the free Personal Team. A 49-minute real ride in Milan ran without a crash, with 28 reroutes all under 110 ms. Nothing suggests a different engine or an earlier server provider.

The new risk is **pack size** (see below): it belongs to M2, not this gate.

## What was built

- `pipeline/spike/build_milan_tiles.sh`: Geofabrik `nord-ovest` → osmium bbox (8.95,45.35 → 9.35,45.62, ≈ 31 × 30 km) → Valhalla **3.9.0** tiles (the version inside valhalla-mobile 0.6.3) → `valhalla_tiles.tar`. 30 s on an M1 Pro.
- `App/Routing/`: `RoutingProvider` protocol (a Ferrostar `CustomRouteProvider`), `ValhallaOnDeviceProvider` (valhalla-mobile, OSRM output with banner + voice instructions, parsed by Ferrostar's `createOsrmResponseParser(polylinePrecision: 6)`), `RoutingProfile` + `RoutingProfiles/city.json` (spike values; real profiles in M3).
- `App/Features/Spike/` (debug builds only): MapLibre map with OpenFreeMap Liberty, Ferrostar's stock navigation UI, benchmark, simulated or device-GPS ride, Live Activity start, metrics to `Documents/m1-metrics.jsonl`.
- Launch arguments `-m1-benchmark` and `-m1-simride` so the spike runs unattended on a device.

## Measurements

### Route computation (engine time, Valhalla `route` + Ferrostar parse)

| Trip | Length | iPhone 11 first call | iPhone 11 median (4 warm) | Simulator (M1 Pro) median |
|---|---|---|---|---|
| Porta Venezia → Politecnico | 2.3 km | 215 ms | 21 ms | 8 ms |
| Duomo → Bicocca | 6.6 km | 208 ms | 53 ms | 29 ms |
| Darsena → Politecnico | 6.2 km | 46 ms | 22 ms | 28 ms |
| Porta Venezia → San Siro | 8.2 km | 53 ms | 28 ms | 24 ms |
| Rho Fiera → San Donato | 25.2 km | 138 ms | 61 ms | 63 ms |
| Reroute (120 m off route → Politecnico) | 1.7 km | 8 ms | 8 ms | 7 ms |

Target "< 1.5 s for 5 km": **met with > 20× margin**. First calls are slower (tile pages mapped in), still ≤ 215 ms.

### Reroute during navigation
Simulator, GPS driven off the route with `simctl location` (GPX fixture `Tests/Fixtures/gpx/porta-venezia-politecnico-detour.gpx`): 5 automatic reroutes, **8–55 ms** each. On the phone the equivalent benchmark call is 8 ms. Real-ride reroutes pending.

### Engine start
227 ms first launch, 99–164 ms after (iPhone 11). Creates one Valhalla instance per session.

### Memory (phys_footprint)
| State | iPhone 11 | Simulator |
|---|---|---|
| Engine loaded, idle | 58–71 MB | 43 MB |
| After benchmark | 89 MB | 116 MB |
| Navigating (map 3D follow + Ferrostar + Live Activity) | 173–248 MB | 270–290 MB |

Comfortable for a 4 GB phone. Most of the navigating number is MapLibre (3D buildings, labels). Watch it in M5 when our styles land.

### Tile size
| Area | Tar | gzip |
|---|---|---|
| Milan bbox (≈ 930 km²) | 70 MB | — |
| Lombardy bbox from nord-ovest (8.49,44.67 → 11.43,46.64; includes eastern Piedmont, no Switzerland/Emilia) | 370 MB | 145 MB |

**Risk for M2:** the 220 MB budget fits the compressed download, not the unpacked tiles, and the pack also needs the hazard sidecar, cycle routes, GTFS and elevation. Options to try in M2: clip to the Lombardy polygon (not bbox), drop data cyclists never use (motorways via `mjolnir` include options / pre-filter `highway=motorway*`, `trunk` without bicycle access), ship tiles compressed and decompress on the phone, or split city / region packs. Decide in M2 with numbers.

### Battery
Desk runs were on the cable (100 %). Real ride: 100 → 85 % in 49 min (see Real ride).

### Free Apple ID (Personal Team `F2ZGNLP242`)
| Capability | Result | How checked |
|---|---|---|
| Install + run on iPhone | ✅ after trusting the developer once in Settings | `devicectl device install`, launch |
| Background location (`UIBackgroundModes: location`) | ✅ signs; ⏳ behaviour with screen locked needs the real ride | build + install |
| Live Activity | ✅ `Activity.request` succeeds, `areActivitiesEnabled = true`, extension process runs | on-device log |
| HealthKit | ✅ entitlement granted in the team provisioning profile | probe build, profile inspected |
| App Groups | ❌ "Provisioning profile doesn't match the entitlements file's value for application-groups" | probe build |
| Re-sign | Every 7 days (free provisioning), max 3 apps | Apple limits |

Impact of no App Groups: the Live Activity must be fed by ActivityKit content updates from the app (fine: HANDOFF asks for local updates), and the widget extension can't read SwiftData directly. No design change needed.

## Real ride, Milan, 14 Oct (iPhone 11, unplugged, device GPS)

| What | Result |
|---|---|
| Duration | 49 min, start 10:09 → arrival 10:59, including a ~20 min stop with the app open |
| Route | 5.0 km to Politecnico, first route 212 ms |
| Reroutes | **28**, median 19 ms, max **106 ms** (target < 2 s ✅); 1 reroute returned no route (31 ms, during the stop) and the next one recovered |
| Stability | No crash; ended by itself on arrival ✅ |
| Memory | 95–233 MB, no upward trend over 49 min |
| Battery | 100 → 85 % (iOS reports in 5 % steps), ≈ 18 %/h with the screen kept on |
| Live Activity | Started (`enabled: true`) |
| Locked screen | Live Activity seen on the lock screen (Filippo). Voice not checked (sound was off). Log ticks kept coming every minute; one 2.5-min gap at 10:46–10:48 (see finding below) |

Findings to act on in M7 (logged in DECISIONS.md):
1. **Reroute bursts**: 9–10 reroutes 7–10 s apart at 10:17–10:21 and 10:48–10:50. Filippo confirmed he was riding his own way on purpose, so rerouting worked as designed. Still, a rider who ignores the route gets a new one every 7–10 s (and a voice prompt each time). M7: back off when a new route is immediately left again, and require several consecutive off-route fixes.
2. **Background gap**: no log for 2.5 min while stationary. Most likely iOS pausing location updates when the rider stands still (`pausesLocationUpdatesAutomatically` is on by default; Ferrostar's `CoreLocationProvider` doesn't expose it). M7: own location provider with pausing off during a ride.
3. **No-route reroute**: one reroute failed silently. M7 must keep the old route and retry, and say so only if it keeps failing.
4. **Battery** ≈ 18 %/h on a 2019 phone with the screen on all the time. M10 target to set; try dimming / screen-off riding with Live Activity.

## Found along the way
- **Auto-end on arrival** fired on the phone (simulated location ends on the route) but not in the simulator, where the GPS path stopped 50 m from the route's end. M7 should end the ride on distance to the destination (≈ 30–50 m) as well as Ferrostar's arrival step.
- Xcode command line needs `-skipMacroValidation` (MapLibre SwiftUI DSL macro) and, for this machine, `OS=18.0` with iPhone 16 (M0).
- Ferrostar's stock UI uses SF Symbols; it is used only in the debug spike screen and is replaced by Velix components in M7.

## Real-ride checklist (done 14 Oct; reuse for M7 rides)

Needs Milan, ~20 min, phone **unplugged**, mounted, Wi-Fi off is fine (routing is offline; map tiles still stream from OpenFreeMap).

1. Note the battery % in Control Center.
2. Open Velix, keep **Device GPS** selected, tap **Ride → Politecnico** (or tell Claude another destination to add).
3. Ride normally; take one wrong turn on purpose to trigger a reroute.
4. Lock the screen for at least 5 minutes mid-ride: check the Live Activity on the lock screen and that the voice keeps talking.
5. At arrival, check the ride ends by itself. Note the battery %.
6. Plug the phone into the Mac and tell Claude: it pulls `m1-metrics.jsonl` and fills in the battery, stability and real reroute numbers here.

Raw log from the device runs: `docs/spikes/m1-iphone11-metrics.jsonl`.
