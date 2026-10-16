"""Print the region polygon's bounding box as planetiler --bounds (minlon,minlat,maxlon,maxlat). Runs on the host."""
import json
import sys


def walk(c, xs, ys):
    if isinstance(c[0], (int, float)):
        xs.append(c[0]); ys.append(c[1])
    else:
        for x in c:
            walk(x, xs, ys)


xs, ys = [], []
for f in json.load(open(sys.argv[1]))["features"]:
    walk(f["geometry"]["coordinates"], xs, ys)
print(f"{min(xs):.5f},{min(ys):.5f},{max(xs):.5f},{max(ys):.5f}")
