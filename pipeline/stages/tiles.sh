#!/usr/bin/env bash
# Stage 3 (Valhalla image): routing tiles with elevation grades and timezones → out/<region>/valhalla_tiles.tar
set -euo pipefail
OUT="/work/pipeline/out/${REGION:-lombardy}"
cd "$OUT"
rm -rf valhalla_tiles valhalla_tiles.tar
valhalla_build_config \
  --mjolnir-tile-dir "$OUT/valhalla_tiles" \
  --mjolnir-tile-extract "$OUT/valhalla_tiles.tar" \
  --mjolnir-admin "$OUT/admins.sqlite" \
  --mjolnir-timezone "$OUT/timezones.sqlite" \
  --additional-data-elevation "$OUT/elevation/" \
  --mjolnir-concurrency "$(nproc)" > valhalla.json
[ -f timezones.sqlite ] || valhalla_build_timezones > timezones.sqlite
valhalla_build_admins -c valhalla.json region.osm.pbf country.osm.pbf
valhalla_build_tiles -c valhalla.json region.osm.pbf
valhalla_build_extract -c valhalla.json --overwrite
ls -l valhalla_tiles.tar
