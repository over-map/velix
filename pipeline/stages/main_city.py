"""Stage 1c: out/<region>/city.geojson for a region without a configured city: the area of its main city.

The app's "destination outside the city area" transit trigger (M8) needs one city per pack. The main city is the
`place=city` in the region with the largest population (else the largest `place=town`); its area is the
administrative boundary named like it that contains it (admin level 7–9, the most local first), else a 5 km circle.
Usage: python stages/main_city.py <source.osm.pbf>"""
import json
import subprocess
import sys

import osmium
from pyproj import Transformer
from shapely.geometry import Point, mapping, shape
from shapely.ops import transform

from common import load_config, log, out_dir, utm_epsg, write_json


class Places(osmium.SimpleHandler):
    def __init__(self, region):
        super().__init__()
        self.region, self.found = region, []

    def node(self, n):
        kind = n.tags.get("place")
        if kind not in ("city", "town") or "name" not in n.tags:
            return
        try:
            pop = int(str(n.tags.get("population", "0")).replace(",", "").replace(".", "").split()[0])
        except ValueError:
            pop = 0
        p = Point(n.location.lon, n.location.lat)
        if self.region.contains(p):
            self.found.append((kind == "city", pop, n.tags["name"], p))


def circle(p: Point, km: float):
    zone = utm_epsg(p.x, p.y)
    to_m = Transformer.from_crs(4326, zone, always_xy=True).transform
    to_ll = Transformer.from_crs(zone, 4326, always_xy=True).transform
    return transform(to_ll, transform(to_m, p).buffer(km * 1000, resolution=16))


def main(src: str) -> None:
    cfg = load_config()
    out = out_dir(cfg)
    region = shape(json.loads((out / "region.geojson").read_text())["features"][0]["geometry"])
    places = Places(region)
    places.apply_file(str(out / "map.osm.pbf"))
    if not places.found:
        area, name = circle(region.representative_point(), 5), "region centre"
    else:
        _, pop, name, p = max(places.found, key=lambda t: (t[0], t[1], t[2]))
        filtered = out / "city-candidates.osm.pbf"
        seq = out / "city-candidates.geojsonseq"
        subprocess.run(["osmium", "tags-filter", src, f"r/name={name}", "-o", str(filtered), "--overwrite"], check=True)
        subprocess.run(["osmium", "export", str(filtered), "--geometry-types=polygon", "-f", "geojsonseq", "-o", str(seq),
                        "--overwrite"], check=True)
        best = None
        for line in seq.read_text().splitlines():
            line = line.strip("\x1e \t")
            if not line:
                continue
            f = json.loads(line)
            t = f.get("properties", {})
            lvl = str(t.get("admin_level", ""))
            if t.get("boundary") == "administrative" and lvl in ("7", "8", "9") and shape(f["geometry"]).contains(p):
                rank = {"8": 0, "9": 1, "7": 2}[lvl]
                if best is None or rank < best[0]:
                    best = (rank, shape(f["geometry"]))
        area = best[1] if best else circle(p, 5)
        name = f"{name} ({'boundary' if best else '5 km circle'}, population {pop})"
    write_json(out / "city.geojson", {"type": "FeatureCollection", "features": [
        {"type": "Feature", "properties": {"name": name}, "geometry": mapping(area)}]})
    log(f"city area: {name}")


if __name__ == "__main__":
    main(sys.argv[1])
