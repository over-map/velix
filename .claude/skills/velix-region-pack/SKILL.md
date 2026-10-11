---
name: velix-region-pack
description: Build, test and publish the Velix offline region pack (Valhalla routing tiles, hazard sidecar, OSM cycle routes, transit timetables) for Lombardy or a new region. Use for anything in pipeline/, the region-pack GitHub Actions workflow, routing profiles, or when routes look wrong because of data.
---

# Velix region pack

Contents: Valhalla tiles · `hazards` sidecar · `routes` (OSM cycle relations) · `transit` (GTFS subset + bikes_allowed_rules.yml) · `manifest.json` (version, bbox, sizes, sha256, source dates). Budget for Lombardy: ≤ 220 MB.

## Build locally (Docker required)
1. Download `https://download.geofabrik.de/europe/italy/nord-ovest-latest.osm.pbf`; clip to the Lombardy polygon with osmium.
2. Valhalla tiles with the official Valhalla Docker image; include elevation (Copernicus GLO-30) for grades.
3. Hazard sidecar from OSM tags (see BUILD_PLAN M2 list). Compute tram crossings and "rails along the lane" (rail within ~3 m and < 20° of a cycle edge for > 30 m).
4. Cycle routes from `route=bicycle|mtb` relations with `network=lcn|rcn|ncn|icn`.
5. Transit: Trenord + ATM GTFS, trimmed to stops in the bbox and the next 60 days; apply curated bikes-allowed rules.
6. Write the manifest; validate sizes and checksums.

## Test
- Run golden route tests (docs/TEST_TRIPS.md) against the new tiles before publishing.
- Spot-check 3 hazards per type on a debug map against OSM.

## Publish
- Workflow `.github/workflows/region-pack.yml` (monthly + manual): build, test, upload as a GitHub Release `pack-lombardy-YYYY.MM`. The app downloads the latest release asset and verifies the checksum.
- Never commit pack binaries to git. Record source dates and licences (ODbL, Copernicus, GTFS licences) in the release notes.

## When routes look wrong
Check, in order: OSM data at that spot → hazard sidecar → profile costing JSON → post-processing. Fix the lowest layer that is wrong, add a golden test for it.
