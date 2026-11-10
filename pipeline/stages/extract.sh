#!/usr/bin/env bash
# Stage 1: download the Geofabrik extracts the region needs (md5-checked) and clip them to the region plus its border
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
for URL in $SOURCES; do
  SRC="cache/$(basename "$URL")"
  curl -fsSL -o "$SRC.md5.new" "$URL.md5"
  if [ ! -f "$SRC" ] || [ ! -f "$SRC.md5" ] || ! cmp -s "$SRC.md5" "$SRC.md5.new"; then
    echo "[extract] downloading $URL"
    # Resumes: Geofabrik sometimes drops a long transfer (curl 18).
    for i in $(seq 1 20); do curl -fsSL -C - -o "$SRC.part" "$URL" && break; echo "[extract] resuming ($i)"; sleep $((i * 5)); done
    mv "$SRC.part" "$SRC"
  fi
  mv "$SRC.md5.new" "$SRC.md5"
  (cd cache && md5sum -c "$(basename "$SRC").md5")
  FILES+=("$SRC")
done
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

TS=$(osmium fileinfo -g header.option.osmosis_replication_timestamp "${FILES[0]}")
python - "$OUT/sources/osm.json" "$TS" "$NAME" $SOURCES <<'PY'
import json, sys
out, ts, name, *urls = sys.argv[1:]
json.dump({"id": "osm", "name": name, "url": " ".join(urls), "date": ts,
           "licence": "ODbL-1.0", "attribution": "© OpenStreetMap contributors"}, open(out, "w"), indent=2, sort_keys=True)
PY
[ "$SRC" = "$OUT/source.osm.pbf" ] && rm -f "$SRC"
osmium fileinfo -e "$OUT/region.osm.pbf" | grep -E "Number of (nodes|ways|relations)"
