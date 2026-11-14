#!/usr/bin/env bash
# Stage 1: take the Geofabrik extracts the region needs (the run's slices, else downloaded, md5-checked) and clip them to the region plus its border
# buffer. Sources: the catalogue's leaves (regions/europe.json: every leaf the border + buffer touches, across national
# borders, merged here), else the config's `osm.url`.
# Outputs: out/<region>/region.osm.pbf (coverage: routing, hazards, routes, timetable), map.osm.pbf (the exact border:
# basemap and overlays, the map tiles of neighbouring packs join at the border), region.geojson, coverage.geojson,
# city.geojson, country.osm.pbf, sources/osm.json
set -euo pipefail
cd /work/pipeline
REGION="${REGION:-lombardy}"
cfg() { python stages/cfg.py "$1"; }
SOURCES=$(cfg osm.sources); [ -z "$SOURCES" ] && SOURCES=$(cfg osm.url)
NAME=$(cfg osm.name); REL=$(cfg region.osm_relation); CITY=$(cfg region.city_area_relation)
OUT="out/$REGION"; mkdir -p "$OUT/sources" cache

FILES=()
SLICED="slices/$REGION"
if compgen -G "$SLICED/*.osm.pbf" >/dev/null; then
  # The Region pack workflow's slice jobs already cut every leaf for this region (stages/slice.py).
  for F in "$SLICED"/*.osm.pbf; do FILES+=("$F"); done
  SOURCES=$(python -c "import json,sys;print(' '.join(json.load(open(f[:-8]+'.json'))['url'] for f in sys.argv[1:]))" "${FILES[@]}")
  TS=$(python -c "import json,sys;print(min(json.load(open(f[:-8]+'.json'))['timestamp'] for f in sys.argv[1:]))" "${FILES[@]}")
  echo "[extract] ${#FILES[@]} slices from $SLICED"
else
  for URL in $SOURCES; do FILES+=("$(bash stages/fetch_leaf.sh "$URL")"); done
  TS=$(osmium fileinfo -g header.option.osmosis_replication_timestamp "${FILES[0]}")
fi
if [ ${#FILES[@]} -gt 1 ]; then
  # Neighbouring leaves overlap at their borders: merge keeps one copy of each object.
  osmium merge "${FILES[@]}" -o "$OUT/source.osm.pbf" --overwrite
  SRC="$OUT/source.osm.pbf"
else
  SRC="${FILES[0]}"
fi

# The region's border: its OSM relation (hand-written regions), else the catalogue polygon.
if [ -n "$REL" ]; then
  osmium getid -r -t "$SRC" "r$REL" -o "$OUT/region-rel.osm.pbf" --overwrite
  osmium export "$OUT/region-rel.osm.pbf" --geometry-types=polygon -o "$OUT/region.geojson" --overwrite
else
  python stages/region_polygon.py
fi
python stages/coverage.py
osmium extract -p "$OUT/coverage.geojson" --strategy smart "$SRC" -o "$OUT/region.osm.pbf" --overwrite
osmium extract -p "$OUT/region.geojson" --strategy smart "$OUT/region.osm.pbf" -o "$OUT/map.osm.pbf" --overwrite

# The city area ("destination outside the city area" transit trigger): its relation, else the region's main city.
if [ -n "$CITY" ]; then
  osmium getid -r -t "$SRC" "r$CITY" -o "$OUT/city-rel.osm.pbf" --overwrite
  osmium export "$OUT/city-rel.osm.pbf" --geometry-types=polygon -o "$OUT/city.geojson" --overwrite
else
  python stages/main_city.py "$SRC"
fi

python stages/country_admin.py "$SRC"

python - "$OUT/sources/osm.json" "$TS" "$NAME" $SOURCES <<'PY'
import json, sys
out, ts, name, *urls = sys.argv[1:]
json.dump({"id": "osm", "name": name, "url": " ".join(urls), "date": ts,
           "licence": "ODbL-1.0", "attribution": "© OpenStreetMap contributors"}, open(out, "w"), indent=2, sort_keys=True)
PY
[ "$SRC" = "$OUT/source.osm.pbf" ] && rm -f "$SRC"
osmium fileinfo -e "$OUT/region.osm.pbf" | grep -E "Number of (nodes|ways|relations)"
