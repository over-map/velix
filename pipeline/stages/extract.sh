#!/usr/bin/env bash
# Stage 1: download the Geofabrik extract (md5-checked) and clip it to the region polygon.
# Outputs: out/<region>/region.osm.pbf, region.geojson (border), city.geojson, sources/osm.json
set -euo pipefail
cd /work/pipeline
REGION="${REGION:-lombardy}"
cfg() { python -c "import yaml,sys;c=yaml.safe_load(open('config/$REGION.yml'));print(eval('c'+sys.argv[1]))" "$1"; }
URL=$(cfg "['osm']['url']"); REL=$(cfg "['region']['osm_relation']"); CITY=$(cfg "['region']['city_area_relation']")
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
osmium extract -p "$OUT/region.geojson" --strategy smart "$SRC" -o "$OUT/region.osm.pbf" --overwrite

python stages/country_admin.py

TS=$(osmium fileinfo -g header.option.osmosis_replication_timestamp "$SRC")
python - "$OUT/sources/osm.json" "$URL" "$TS" <<'PY'
import json, sys
out, url, ts = sys.argv[1:]
json.dump({"id": "osm", "name": "OpenStreetMap (Geofabrik nord-ovest)", "url": url, "date": ts,
           "licence": "ODbL-1.0", "attribution": "© OpenStreetMap contributors"}, open(out, "w"), indent=2, sort_keys=True)
PY
osmium fileinfo -e "$OUT/region.osm.pbf" | grep -E "Number of (nodes|ways|relations)"
