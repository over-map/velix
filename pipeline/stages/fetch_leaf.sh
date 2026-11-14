#!/usr/bin/env bash
# Download one Geofabrik extract into cache/ (md5-checked; resumes when Geofabrik drops a long transfer, curl 18) and
# print its path. Skips the download when the cached copy matches the server's md5. Used by extract.sh and slice.py.
# Usage: bash stages/fetch_leaf.sh <url>
set -euo pipefail
cd /work/pipeline
URL="$1"; SRC="cache/$(basename "$URL")"; mkdir -p cache
for i in $(seq 1 5); do curl -fsSL -o "$SRC.md5.new" "$URL.md5" && break; sleep $((i * 10)); done
if [ ! -f "$SRC" ] || [ ! -f "$SRC.md5" ] || ! cmp -s "$SRC.md5" "$SRC.md5.new"; then
  echo "[fetch] downloading $URL" >&2
  for i in $(seq 1 20); do curl -fsSL -C - -o "$SRC.part" "$URL" && break; echo "[fetch] resuming ($i)" >&2; sleep $((i * 5)); done
  mv "$SRC.part" "$SRC"
fi
mv "$SRC.md5.new" "$SRC.md5"
(cd cache && md5sum -c --quiet "$(basename "$SRC").md5") >&2
echo "$SRC"
