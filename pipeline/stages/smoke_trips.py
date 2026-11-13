"""Stage 9 (prep): out/<region>/smoke_trips.txt, the trips smoke_routes.sh routes and smoke.py checks.

Hand-written regions keep config/smoke_trips/<region>.txt (id|from lat,lon|to lat,lon|min km|max km). Others get a
generic trip between their two largest places (by population, cities first) at least 3 km apart, expected between
the straight distance and 2.2× it + 3 km."""
import json
import math

import osmium
from shapely.geometry import Point, shape

from common import PIPELINE, load_config, log, out_dir


def km(a, b):
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 12742 * math.asin(math.sqrt(h))


class Places(osmium.SimpleHandler):
    def __init__(self, region):
        super().__init__()
        self.region, self.found = region, []

    def node(self, n):
        if n.tags.get("place") in ("city", "town") and "name" in n.tags \
                and self.region.contains(Point(n.location.lon, n.location.lat)):
            try:
                pop = int(str(n.tags.get("population", "0")).replace(",", "").replace(".", "").split()[0])
            except ValueError:
                pop = 0
            self.found.append((n.tags["place"] == "city", pop, n.tags["name"], (n.location.lat, n.location.lon)))


def slug(s):
    return "".join(c if c.isalnum() else "-" for c in s.lower()).strip("-")


def main():
    cfg = load_config()
    out = out_dir(cfg)
    hand = PIPELINE / "config" / "smoke_trips" / f"{cfg['region']['id']}.txt"
    if hand.exists():
        (out / "smoke_trips.txt").write_text(hand.read_text())
        log(f"smoke trips from {hand.name}")
        return
    region = shape(json.loads((out / "region.geojson").read_text())["features"][0]["geometry"])
    p = Places(region)
    p.apply_file(str(out / "map.osm.pbf"))
    ranked = sorted(p.found, key=lambda t: (t[0], t[1], t[2]), reverse=True)
    lines = []
    if ranked:
        a = ranked[0]
        b = next((x for x in ranked[1:] if km(a[3], x[3]) >= 3), None)
        if b:
            d = km(a[3], b[3])
            lines.append(f"{slug(a[2])}-{slug(b[2])}|{a[3][0]:.5f},{a[3][1]:.5f}|{b[3][0]:.5f},{b[3][1]:.5f}|"
                         f"{d:.1f}|{2.2 * d + 3:.1f}")
    (out / "smoke_trips.txt").write_text("\n".join(lines) + ("\n" if lines else ""))
    log(f"generic smoke trips: {lines or 'none (fewer than two places)'}")


if __name__ == "__main__":
    main()
