---
name: velix-region-pack
description: Build, test and publish the Velix offline region pack (Valhalla routing tiles, hazard sidecar, OSM cycle routes, transit timetables) for Lombardy or a new region. Use for anything in pipeline/, the region-pack GitHub Actions workflow, routing profiles, or when routes look wrong because of data.
---

# Velix region pack

Contents (separate Release assets, each xz): `valhalla_tiles.tar` · `hazards.sqlite` (R*Tree) · `routes.sqlite` (OSM cycle relations) · `transit.sqlite` (GTFS subset + bike_rules) · `manifest.json` (version, bbox, sizes, sha256 packed + unpacked, sources, licences). Budget for Lombardy: ≤ 220 MB **download** (first pack: 120 MB). Full reference: `pipeline/README.md`.

## Build locally (Docker required)
`make -C pipeline pack` runs every stage in `pipeline/stages/` (extract → elevation → tiles → hazards → routes → transit → package → validate → smoke). One stage: `make -C pipeline <stage>`. Config: `pipeline/config/<region>.yml`; curated bike rules: `pipeline/config/bikes_allowed_rules.yml`.
- Valhalla version must match valhalla-mobile (3.9.0 for 0.6.3); the image is pinned by digest in the config.
- Steep segments are not in the sidecar: they come from Valhalla edge grades on the phone.
- A new region needs: its Geofabrik extract, its admin relation, its country (see `stages/country_admin.py`), its feeds and bike rules.

## Test
- `make -C pipeline smoke` (6 routes, hazard counts, EuroVelo, transit) runs in every build; from M3 also run the golden route tests (docs/TEST_TRIPS.md) before publishing.
- Spot-check 3 hazards per type on a debug map against OSM.

## Publish
- Workflow `.github/workflows/region-pack.yml` (monthly + manual + PRs touching pipeline/): build, smoke-test, artifact; on main publishes Release `pack-lombardy-YYYY.MM` (`.N` if taken). The app finds it with `RegionPackCatalog` and installs it with `RegionPackInstaller` (sha256 per file, atomic switch).
- Never commit pack binaries to git. Record source dates and licences (ODbL, Copernicus, GTFS licences) in the release notes.

## When routes look wrong
Check, in order: OSM data at that spot → hazard sidecar → profile costing JSON → post-processing. Fix the lowest layer that is wrong, add a golden test for it.
