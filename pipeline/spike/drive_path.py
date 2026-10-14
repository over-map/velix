#!/usr/bin/env python3
"""M1 spike: build a GPS drive path through the given points using Valhalla (Docker),
print it as "lat,lon lat,lon ..." for `xcrun simctl location start`, and write a GPX fixture.
Usage: drive_path.py OUT.gpx lat,lon lat,lon [lat,lon ...]"""
import json, subprocess, sys, os

def decode6(s):
    coords, i, lat, lon = [], 0, 0, 0
    while i < len(s):
        for which in (0, 1):
            shift = result = 0
            while True:
                b = ord(s[i]) - 63; i += 1
                result |= (b & 0x1f) << shift; shift += 5
                if b < 0x20: break
            d = ~(result >> 1) if result & 1 else result >> 1
            if which == 0: lat += d
            else: lon += d
        coords.append((lat / 1e6, lon / 1e6))
    return coords

out, pts = sys.argv[1], [tuple(map(float, p.split(","))) for p in sys.argv[2:]]
data = os.path.join(os.path.dirname(__file__), "../cache/spike")
req = {"locations": [{"lat": a, "lon": b, "type": "break"} for a, b in pts], "costing": "bicycle",
       "costing_options": {"bicycle": {"bicycle_type": "hybrid", "use_roads": 0.6}}}
res = subprocess.run(["docker", "run", "--rm", "-v", f"{os.path.abspath(data)}:/data", "ghcr.io/valhalla/valhalla:3.9.0",
                      "valhalla_service", "/data/valhalla.json", "route", json.dumps(req)], capture_output=True, text=True, check=True)
shape = []
for leg in json.loads(res.stdout)["trip"]["legs"]:
    shape += decode6(leg["shape"])
dedup = [p for i, p in enumerate(shape) if i == 0 or p != shape[i - 1]]
with open(out, "w") as f:
    f.write('<?xml version="1.0"?>\n<gpx version="1.1" creator="velix-spike"><trk><trkseg>\n')
    for a, b in dedup: f.write(f'<trkpt lat="{a:.6f}" lon="{b:.6f}"/>\n')
    f.write("</trkseg></trk></gpx>\n")
print(" ".join(f"{a:.6f},{b:.6f}" for a, b in dedup))
