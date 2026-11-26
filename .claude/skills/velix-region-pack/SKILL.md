---
name: velix-region-pack
description: Build, test and publish the Velix offline region pack (Valhalla routing tiles, hazard sidecar, OSM cycle routes, transit timetables) for Lombardy or a new region. Use for anything in pipeline/, the region-pack GitHub Actions workflow, routing profiles, or when routes look wrong because of data.
---

# Velix region pack

Contents (separate Release assets, each xz): `valhalla_tiles.tar` · `hazards.sqlite` (R*Tree) · `routes.sqlite` (OSM cycle relations) · `city.geojson` (city area) · `basemap.pmtiles` + `overlays.pmtiles` · `manifest.json` (version, bbox, sizes, sha256 packed + unpacked, sources, licences). Budget: **≤ 300 MB download per part**: routing (every file but the basemap) and the optional offline map (`basemap.pmtiles`) (Filippo, 24 Nov 2026; was 220, 300 and 320 MB for the whole pack). The region catalogue still forecasts ≤ 320 MB for the whole pack. No timetables since M11 PR 4b: bike + train comes from Transitous online, bike rules from `App/Resources/Transit/bike-rules.json`. Routing data (tiles, hazards, cycle routes) reaches 10 km past the region border so border-crossing trips plan in one pack; map tiles (basemap, overlays) stop at the border. If new content doesn't fit, bring options to Filippo before cutting anything. Regions published (Nov 2026): Lombardy, Piedmont, Veneto, Emilia-Romagna, Trentino-South Tyrol, plus a `pack-index` release the app reads. Full reference: `pipeline/README.md`.

## Build locally (Docker required)
`make -C pipeline pack` runs every stage in `pipeline/stages/` (extract → elevation → tiles → hazards → routes → basemap → overlays → package → validate → smoke). One stage: `make -C pipeline <stage>`. Config: `pipeline/config/<region>.yml`.
- Valhalla version must match valhalla-mobile (3.9.0 for 0.6.3); the image is pinned by digest in the config.
- Steep segments are not in the sidecar: they come from Valhalla edge grades on the phone.
- A new region needs: its Geofabrik extract, its admin relation, its country (see `stages/country_admin.py`).

## Test
- `make -C pipeline smoke` (smoke trips, hazard counts, EuroVelo, city area) runs in every build; from M3 also run the golden route tests (docs/TEST_TRIPS.md) before publishing.
- Spot-check 3 hazards per type on a debug map against OSM.

## Publish
- Workflow `.github/workflows/region-pack.yml` (monthly + manual + PRs touching pipeline/): build, smoke-test, artifact; on main publishes Release `pack-lombardy-YYYY.MM` (`.N` if taken). The app finds it with `RegionPackCatalog` and installs it with `RegionPackInstaller` (sha256 per file, atomic switch).
- Never commit pack binaries to git. Record source dates and licences (ODbL, GEDTM30) in the release notes.

## When routes look wrong
Check, in order: OSM data at that spot → hazard sidecar → profile costing JSON → post-processing. Fix the lowest layer that is wrong, add a golden test for it.
