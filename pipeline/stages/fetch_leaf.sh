#!/usr/bin/env bash
# Download one Geofabrik extract into cache/ (md5-checked; resumes when Geofabrik drops a long transfer, curl 18) and
# print its path. Skips the download when the cached copy matches the server's md5. Used by extract.sh and slice.py.
# Usage: bash stages/fetch_leaf.sh <url>
set -euo pipefail
cd /work/pipeline
URL="$1"; SRC="cache/$(basename "$URL")"; mkdir -p cache
# Geofabrik sometimes refuses a runner for a while (14 Nov: 30 min): ≈ 10 min of retries, then fail clearly (a build
# whose slice job failed downloads the leaf itself, from another runner).
OK=""
for i in $(seq 1 8); do curl -fsSL --connect-timeout 30 -o "$SRC.md5.new" "$URL.md5" && { OK=1; break; }; sleep $((i * 15)); done
[ -n "$OK" ] || { echo "[fetch] $URL.md5: Geofabrik unreachable" >&2; exit 1; }
if [ ! -f "$SRC" ] || [ ! -f "$SRC.md5" ] || ! cmp -s "$SRC.md5" "$SRC.md5.new"; then
  echo "[fetch] downloading $URL" >&2
  OK=""
  for i in $(seq 1 20); do
    curl -fsSL --connect-timeout 30 -C - -o "$SRC.part" "$URL" && { OK=1; break; }
    echo "[fetch] resuming ($i)" >&2; sleep $((i * 5))
  done
  [ -n "$OK" ] || { echo "[fetch] $URL: download failed" >&2; exit 1; }
  mv "$SRC.part" "$SRC"
fi
mv "$SRC.md5.new" "$SRC.md5"
(cd cache && md5sum -c --quiet "$(basename "$SRC").md5") >&2
echo "$SRC"
