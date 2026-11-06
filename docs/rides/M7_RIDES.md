# M7 real rides: what to ride

M7 is accepted after **3 real rides in Milan** (docs/BUILD_PLAN.md M7), checked from the ride logs by
`tools/ride-report/ride_report.py`.

**Checks**
- no crash;
- no reroute bursts;
- no location gap, stopped or not;
- a failed reroute keeps the old route;
- voice heard with the phone locked;
- the Live Activity updating on the lock screen;
- battery per hour.

**Hazards:** alerts while riding are off since 29 Oct (`HazardType.onRoute` is empty). The report shows that check as not measured, unless alerts come back.

## Before each ride
- **Phone:** Velix installed from the Mac within the last 7 days (the free signing profile), and unplugged.
- **Start:** search the destination, then Start from route options. Voice on **All**.
- **Leave alone:** Low Power Mode and Focus, as you normally have them. The log records both.

## The rides
1. **Commute, 4–6 km** (e.g. Porta Venezia → Politecnico).
   - Lock the phone early and keep it locked, in a pocket or on the bars, for most of the ride.
   - Checks: voice with the phone locked, the Live Activity, the lock-screen wake before a turn.
2. **The same area, with two deliberate wrong turns.**
   - Take a street the route doesn't, ride on for a block, and let it reroute.
   - Also make one stop of 2 minutes or more (a light, a café), without ending the ride.
   - Switch to 3D for part of it.
   - Checks: reroutes (no bursts, the back-off), no location gap while stopped.
3. **A longer ride, 8–12 km, across the centre** (cobbles, tram rails).
   - Voice on Alerts for a stretch, then back to All.
   - Checks: battery per hour, memory, heat, a long ride without a crash.

Each ride ends at the door: arrive, or tap End.

## After each ride
Plug the phone into the Mac and tell Claude. It pulls the logs and crash reports:

```bash
xcrun devicectl device copy from --device <id> --domain-type appDataContainer --domain-identifier io.github.over-map.velix --source Documents/rides --destination build/rides
```

```bash
xcrun devicectl device copy from --device <id> --domain-type appDataContainer --domain-identifier io.github.over-map.velix --source Documents/diagnostics --destination build/diagnostics
```

```bash
python3 tools/ride-report/ride_report.py build/rides --diagnostics build/diagnostics -o build/ride-report.md
```

- **Crash reports:** iOS delivers them on a later launch, up to a day after the crash, so opening Velix the next day collects them. The folder appears only once there is a report.
- **Privacy:** raw logs and GPX stay on the phone and in `build/`; they are never committed. The report prints no coordinates.
- **After all 3 rides:** the results go into `docs/spikes/M7_REPORT.md`.
