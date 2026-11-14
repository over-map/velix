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

# Each source leaf: its slice when the Region pack workflow's slice jobs cut one for this region (stages/slice.py),
# else the whole leaf, downloaded here. A slice job that failed (Geofabrik refused one runner for 30 min on 14 Nov)
# then costs one download instead of a pack without that leaf's roads.
FILES=(); STAMPS=(); SLICED="slices/$REGION"; N_SLICES=0
for URL in $SOURCES; do
  LEAF=$(basename "$URL" -latest.osm.pbf)
  if [ -f "$SLICED/$LEAF.osm.pbf" ] && [ -f "$SLICED/$LEAF.json" ]; then
    FILES+=("$SLICED/$LEAF.osm.pbf"); N_SLICES=$((N_SLICES + 1))
    STAMPS+=("$(python -c "import json,sys;print(json.load(open(sys.argv[1]))['timestamp'])" "$SLICED/$LEAF.json")")
  else
    [ -d "$SLICED" ] && echo "[extract] no slice of $LEAF: downloading it"
    F=$(bash stages/fetch_leaf.sh "$URL"); FILES+=("$F")
    STAMPS+=("$(osmium fileinfo -g header.option.osmosis_replication_timestamp "$F")")
  fi
done
TS=$(printf '%s\n' "${STAMPS[@]}" | sort | head -1)   # the oldest source (ISO times sort as text)
echo "[extract] ${#FILES[@]} sources, $N_SLICES from slices"
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
