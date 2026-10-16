#!/usr/bin/env bash
# Map label glyphs (SDF PBF) from the bundled fonts, with node-fontnik (BSD-3-Clause) in Docker.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
docker run --rm -v "$ROOT:/work" -w /work node:22.11.0-bookworm \
  bash -c "cd /tmp && npm install --silent --no-save fontnik@0.7.7 >/dev/null && NODE_PATH=/tmp/node_modules node /work/tools/glyphs/build.js"
