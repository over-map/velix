#!/usr/bin/env bash
# Stage 9a (Valhalla image): route the smoke trips on the built tiles with the City profile → out/<region>/smoke/*.json
set -euo pipefail
OUT="/work/pipeline/out/${REGION:-lombardy}"
mkdir -p "$OUT/smoke"
OPTS=$(python3 -c "import json;p=json.load(open('/work/App/Resources/RoutingProfiles/city.json'));print(json.dumps({'bicycle':p['best']['costing_options']}))")
while IFS='|' read -r id a b; do
  [ -z "$id" ] && continue
  REQ="{\"locations\":[{\"lat\":${a%,*},\"lon\":${a#*,}},{\"lat\":${b%,*},\"lon\":${b#*,}}],\"costing\":\"bicycle\",\"costing_options\":$OPTS,\"units\":\"km\"}"
  valhalla_service "$OUT/valhalla.json" route "$REQ" 2>/dev/null > "$OUT/smoke/$id.json" || echo '{"error":"no route"}' > "$OUT/smoke/$id.json"
done < /work/pipeline/config/smoke_trips.txt
ls "$OUT/smoke"
