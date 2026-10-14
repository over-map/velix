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
  --mjolnir-concurrency "${TILE_THREADS:-$(nproc)}" > valhalla.json
[ -f timezones.sqlite ] || valhalla_build_timezones > timezones.sqlite
valhalla_build_admins -c valhalla.json region.osm.pbf country.osm.pbf
valhalla_build_tiles -c valhalla.json region.osm.pbf
# Reproducible tar: the extract records file mtimes, so pin them to the OSM extract date.
STAMP=$(python3 -c "import json;print(json.load(open('sources/osm.json'))['date'])")
find valhalla_tiles -exec touch -h -d "$STAMP" {} +
valhalla_build_extract -c valhalla.json --overwrite
ls -l valhalla_tiles.tar
