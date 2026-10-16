#!/usr/bin/env bash
# P3 frame (design/p3v3 renderer at phone size) next to the same frame in the simulator's -map-preview.
# Usage: tools/p3-frames/shoot.sh <name> <style> <mode> <zoom> <route|loreto|monza> [overlays]
# Needs: the repo served on 127.0.0.1:8766 (python3 -m http.server 8766 --bind 127.0.0.1), Google Chrome, the app on
# the booted simulator with the pack side-loaded (see CLAUDE.md), its UDID in build/sim-udid. Output: build/compare/m5/.
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/compare/m5
N=$1; ST=$2; MO=$3; Z=$4; FR=$5; OV=${6:-}
UDID=$(cat build/sim-udid)
CH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
Q="frame=$FR&z=$Z&style=$ST&mode=$MO"; [ -n "$OV" ] && Q="$Q&bike=1&transit=1"
"$CH" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=3 --window-size=393,852 --virtual-time-budget=20000 \
  --screenshot=build/compare/m5/$N-p3.png "http://127.0.0.1:8766/tools/p3-frames/index.html?$Q" 2>/dev/null
ARGS=(-map-preview -use-sideloaded -map-bare -map-style $ST -map-mode $MO -map-zoom $Z -map-frame $FR)
[ -n "$OV" ] && ARGS+=(-map-overlays)
xcrun simctl launch --terminate-running-process $UDID io.github.over-map.velix "${ARGS[@]}" >/dev/null
sleep ${WAIT:-7}
xcrun simctl io $UDID screenshot build/compare/m5/$N-velix.png >/dev/null 2>&1
python3 - "$N" <<'PY'
import sys
from PIL import Image
n=sys.argv[1]
a=Image.open(f'build/compare/m5/{n}-p3.png').convert('RGB'); b=Image.open(f'build/compare/m5/{n}-velix.png').convert('RGB').resize(a.size)
o=Image.new('RGB',(a.width*2+30,a.height),'white'); o.paste(a,(0,0)); o.paste(b,(a.width+30,0))
o.resize((o.width//3,o.height//3)).save(f'build/compare/m5/{n}.png')
PY
echo "build/compare/m5/$N.png"
