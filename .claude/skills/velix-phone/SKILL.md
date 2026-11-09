---
name: velix-phone
description: Build Velix for Filippo's iPhone, install it, launch it with debug arguments, copy ride logs and launch logs off the phone, and fix device connection problems. Use whenever the work needs the real phone (visual checks, simulated rides on device, performance or battery measurements), when Filippo says "install it", "put it on the phone", "the phone is connected" or "I re-plugged it", or before the free signing profile expires.
---

# Velix on the phone

Machine-specific values (device name, UDID, team id, profile expiry) live in `CLAUDE.local.md` (not committed). Read it first. Below, `$UDID` is the phone's hardware UDID from there; devicectl accepts it.

## Rules
- **Install only after a successful build, and look inside the .app first** (`ls` it, check `CFBundleIdentifier` is `io.github.over-map.velix`, size about 60 MB). Never install a half-built or stale app.
- Filippo does the physical part: cable, unlock, Trust, unplug for battery runs. Claude never signs in to Apple accounts.
- **Free Personal Team signing: profiles last 7 days, and a rebuild or reinstall does NOT renew them.** Xcode keeps reusing the cached profile until it expires. Check the expiry with
  `security cms -D -i build/DerivedData/Build/Products/Debug-iphoneos/Velix.app/embedded.mobileprovision | plutil -extract ExpirationDate raw -o - -`.
  To renew:
  1. Xcode must have Filippo's Apple ID in Xcode → Settings → Accounts. Without it, the build fails with "No Accounts", and only Filippo can sign in.
  2. Move the two cached Velix profiles (`io.github.over-map.velix` and `…velix.LiveActivity`) from `~/Library/Developer/Xcode/UserData/Provisioning Profiles/` to `~/.Trash`. Find them by decoding each with `security cms -D -i <file>` and reading `Name`. Leave the `com.overmap.crate*` profiles alone; they belong to another app.
  3. Rebuild with `-allowProvisioningUpdates` and install.
  4. If the phone then refuses to open the app, Filippo trusts the developer in Settings → General → VPN & Device Management.
  5. If the build fails, move the old profiles back out of the Trash so builds keep working until they expire.

## Build, check, install, launch
```bash
cd /Users/imbe/Developer/personal/velix
xcodebuild -scheme Velix -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData -skipMacroValidation -onlyUsePackageVersionsFromResolvedFile \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=<team id from CLAUDE.local.md> build 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
A=build/DerivedData/Build/Products/Debug-iphoneos/Velix.app; ls $A; du -sh $A
xcrun devicectl list devices | grep -i ifil          # must say "connected"
xcrun devicectl device install app --device $UDID $A
xcrun devicectl device process launch --terminate-existing --device $UDID io.github.over-map.velix -- <debug args>
```
Run the xcodebuild in the background when it might take more than 2 minutes. A clean build takes 5–10 min; an incremental one about 1 min.

Useful launch arguments (Debug builds; the full list is in CLAUDE.md "Commands"):
- `-simulate-ride -ride-to 45.5845,9.2744,Monza -start-ride`: a simulated 2D City ride from the phone's real position to Monza (add `-fake-location 45.448,9.196` if the phone isn't in a downloaded region). 18.8 km at 5 m/s, so about **63 minutes**. Shorter runs: pick a nearer `-ride-to`, or add `-simulate-speed 10`.
- `-fake-location 45.448,9.196` plans from south Milan when the phone is elsewhere.
- `-map-perf` prints fps to the console (add `--console` to the launch).

## Copy files off the phone
```bash
xcrun devicectl device info files --device $UDID --domain-type appDataContainer \
  --domain-identifier io.github.over-map.velix --subdirectory Documents/rides
xcrun devicectl device copy from --device $UDID --domain-type appDataContainer \
  --domain-identifier io.github.over-map.velix --source Documents/rides/<file>.jsonl --destination <scratch dir>/<file>.jsonl
```
Ride logs are `Documents/rides/<UTC timestamp>.jsonl` (+ `.gpx`). Launch times are `Documents/diagnostics/launch.jsonl`, and MetricKit payloads are in `Documents/diagnostics/`.
Report: `python3 tools/ride-report/ride_report.py --include-simulated <ride.jsonl>`. Simulated rides are skipped without the flag. For launches: `--launch <launch.jsonl>`.

## When the phone misbehaves
- **`connecting` in `devicectl list devices`, or copies that hang or fail with "failed to get a list of files" / "no mount information":** this happens after a replug. Ask Filippo to unlock the phone and keep it unlocked, and to tap Trust if asked. Wait until the state is `connected` or `available (paired)`, then retry. Wrap copies in `timeout 90`, because a stuck copy otherwise blocks for minutes.
- **The phone is often locked.** A launch on a locked phone fails, so ask Filippo to unlock it first.
- **"Failed to allocate RSD device" or the phone "unavailable":** ask Filippo to replug, unlock and tap Trust. For unplugged runs (battery), launch while it's on the cable, then he unplugs. devicectl can also reach it over Wi-Fi once paired.
- **A locked or dark screen throttles the display link** to a few Hz. Measure fps with the screen on.
- **`-use-sideloaded`** makes the app read side-loaded pack files from Documents. To test the installed pack, launch from the home screen or without that flag.
- **Battery readings:** `UIDevice.batteryLevel` moves in 5 % steps, and it holds 100 % for a long time after a full charge. One hour unplugged gives one or two steps. Compare builds on the health line's `cpu` (% of one core) instead. On Xcode 27.0, xctrace's Power Profiler crashes on save and Activity Monitor hangs.
- **The home map keeps rendering under the riding screen** (`RidingView` is a fullScreenCover). The fps counter counts every map, so a jump in fps can be the hidden map. That's why the app location moves only every 100 m while riding.
