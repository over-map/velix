#!/usr/bin/env bash
# Download one Geofabrik extract into cache/ (md5-checked; resumes when Geofabrik drops a long transfer, curl 18) and
# print its path. Skips the download when the cached copy matches the server's md5. Used by extract.sh and slice.py.
#
# Since ≈ 18 Nov 2026 every extract lives in its own folder and `…-latest.osm.pbf` redirects to a dated file
# (europe/luxembourg-latest.osm.pbf → europe/luxembourg/luxembourg-latest.osm.pbf → …/luxembourg-261118.osm.pbf);
# the .md5 exists only next to the dated file. So the URL is resolved first, and the checksum is compared by hash
# (its file name is the dated one). Old-layout URLs (the catalogue's) keep working through the redirects.
# Usage: bash stages/fetch_leaf.sh <url>
set -euo pipefail
cd /work/pipeline
URL="$1"; SRC="cache/$(basename "$URL")"; mkdir -p cache
# Geofabrik sometimes refuses a runner for a while (14 Nov: 30 min): ≈ 10 min of retries, then fail clearly (a build
# whose slice job failed downloads the leaf itself, from another runner).
retry() { local what="$1"; shift; for i in $(seq 1 8); do "$@" && return 0; sleep $((i * 15)); done
          echo "[fetch] $what: Geofabrik unreachable" >&2; return 1; }
resolve() { FINAL=$(curl -fsSIL --connect-timeout 30 -o /dev/null -w '%{url_effective}' "$URL"); }
# Geofabrik's servers disagreed for a while after its Nov 2026 move (two .md5 answers for one file a minute apart): on a
# mismatch, start over (address, checksum, file) up to 4 times before failing.
for round in 1 2 3 4; do
  retry "$URL" resolve
  retry "$FINAL.md5" curl -fsSL --connect-timeout 30 -o "$SRC.md5.new" "$FINAL.md5"
  WANT=$(cut -d' ' -f1 "$SRC.md5.new"); rm -f "$SRC.md5.new"
  [[ "$WANT" =~ ^[0-9a-f]{32}$ ]] || { echo "[fetch] $FINAL.md5: not an md5" >&2; exit 1; }
  if [ -f "$SRC" ] && [ "$(cat "$SRC.md5" 2>/dev/null)" = "$WANT" ]; then
    [ "$(md5sum "$SRC" | cut -d' ' -f1)" = "$WANT" ] && { echo "$SRC"; exit 0; }
    rm -f "$SRC" "$SRC.md5"; echo "[fetch] $SRC: cached copy corrupt, downloading again" >&2
  fi
  echo "[fetch] downloading $FINAL" >&2
  # The partial file is named after the dated file, so a resume never mixes two days' extracts.
  PART="cache/$(basename "$FINAL").part"
  OK=""
  for i in $(seq 1 20); do
    curl -fsSL --connect-timeout 30 -C - -o "$PART" "$FINAL" && { OK=1; break; }
    echo "[fetch] resuming ($i)" >&2; sleep $((i * 5))
  done
  [ -n "$OK" ] || { echo "[fetch] $FINAL: download failed" >&2; exit 1; }
  if [ "$(md5sum "$PART" | cut -d' ' -f1)" = "$WANT" ]; then
    mv "$PART" "$SRC"; echo "$WANT" > "$SRC.md5"; echo "$SRC"; exit 0
  fi
  rm -f "$PART"; echo "[fetch] $FINAL: md5 mismatch (round $round), starting over" >&2; sleep $((round * 30))
done
echo "[fetch] $URL: md5 never matched" >&2; exit 1
