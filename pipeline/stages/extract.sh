#!/usr/bin/env bash
# Stage 1: download the Geofabrik extract (md5-checked) and clip it to the region polygon plus its border buffer.
# Outputs: out/<region>/region.osm.pbf (coverage: routing, hazards, routes, timetable), map.osm.pbf (the exact border: basemap and
# overlays, the map tiles of neighbouring packs join at the border), region.geojson, coverage.geojson, city.geojson, sources/osm.json
set -euo pipefail
cd /work/pipeline
REGION="${REGION:-lombardy}"
cfg() { python stages/cfg.py "$1"; }
URL=$(cfg osm.url); NAME=$(cfg osm.name); REL=$(cfg region.osm_relation); CITY=$(cfg region.city_area_relation)
OUT="out/$REGION"; mkdir -p "$OUT/sources" cache
SRC="cache/$(basename "$URL")"

curl -fsSL -o "$SRC.md5.new" "$URL.md5"
if [ ! -f "$SRC" ] || [ ! -f "$SRC.md5" ] || ! cmp -s "$SRC.md5" "$SRC.md5.new"; then
  echo "[extract] downloading $URL"
  curl -fsSL -o "$SRC.part" "$URL" && mv "$SRC.part" "$SRC"
fi
mv "$SRC.md5.new" "$SRC.md5"
(cd cache && md5sum -c "$(basename "$SRC").md5")

for pair in "region:$REL" "city:$CITY"; do
  name=${pair%%:*}; id=${pair#*:}
  osmium getid -r -t "$SRC" "r$id" -o "$OUT/$name-rel.osm.pbf" --overwrite
  osmium export "$OUT/$name-rel.osm.pbf" --geometry-types=polygon -o "$OUT/$name.geojson" --overwrite
done
python stages/coverage.py
osmium extract -p "$OUT/coverage.geojson" --strategy smart "$SRC" -o "$OUT/region.osm.pbf" --overwrite
osmium extract -p "$OUT/region.geojson" --strategy smart "$OUT/region.osm.pbf" -o "$OUT/map.osm.pbf" --overwrite

python stages/country_admin.py

TS=$(osmium fileinfo -g header.option.osmosis_replication_timestamp "$SRC")
python - "$OUT/sources/osm.json" "$URL" "$TS" "$NAME" <<'PY'
import json, sys
out, url, ts, name = sys.argv[1:]
json.dump({"id": "osm", "name": name, "url": url, "date": ts,
           "licence": "ODbL-1.0", "attribution": "© OpenStreetMap contributors"}, open(out, "w"), indent=2, sort_keys=True)
PY
osmium fileinfo -e "$OUT/region.osm.pbf" | grep -E "Number of (nodes|ways|relations)"
