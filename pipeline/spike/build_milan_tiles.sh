#!/usr/bin/env bash
# M1 spike: build Valhalla 3.9.0 tiles (same version as valhalla-mobile) for a Milan bbox.
# Output: pipeline/cache/spike/valhalla_tiles.tar (bundled into debug builds only).
# Elevation, timezones, hazard sidecar and transit come in M2 (pipeline proper).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CACHE="$ROOT/pipeline/cache"
OUT="$CACHE/spike"
IMAGE="ghcr.io/valhalla/valhalla:3.9.0"
BBOX="8.95,45.35,9.35,45.62"   # Milan + first ring (west, south, east, north)

mkdir -p "$OUT"
if [ ! -f "$CACHE/nord-ovest-latest.osm.pbf" ]; then
  curl -fsSL -o "$CACHE/nord-ovest-latest.osm.pbf" https://download.geofabrik.de/europe/italy/nord-ovest-latest.osm.pbf
fi
osmium extract -b "$BBOX" "$CACHE/nord-ovest-latest.osm.pbf" -o "$OUT/milan.osm.pbf" --overwrite

docker run --rm -v "$OUT:/data" "$IMAGE" bash -euo pipefail -c '
  cd /data
  rm -rf valhalla_tiles valhalla_tiles.tar
  valhalla_build_config \
    --mjolnir-tile-dir /data/valhalla_tiles \
    --mjolnir-tile-extract /data/valhalla_tiles.tar \
    --mjolnir-admin /data/admins.sqlite \
    --mjolnir-concurrency 6 > valhalla.json
  valhalla_build_admins -c valhalla.json milan.osm.pbf
  valhalla_build_tiles -c valhalla.json milan.osm.pbf
  valhalla_build_extract -c valhalla.json -v --overwrite
'
ls -lh "$OUT/valhalla_tiles.tar"
du -sh "$OUT/valhalla_tiles"
