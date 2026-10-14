"""Stage 4: hazard sidecar from OSM → out/<region>/hazards.sqlite

Types (names match the hazard glyphs in design/assets/glyphs/hazard-*.svg):
  tram     tram-rail crossing point (railway=tram_level_crossing/tram_crossing nodes + geometric crossings)
  along    tram rail running within 3 m and < 20° of a cycle-usable way for > 30 m
  cobbles  surface=sett|cobblestone|unhewn_cobblestone on a cycle-usable way
  steps    highway=steps
  gap      barrier node on a cycle-usable way (bollard, gate, cycle_barrier…), or maxwidth < 1 m
  dismount bicycle=dismount, or a pedestrian street/area where bicycles aren't allowed
  lane     a cycle lane/track/cycleway ends and the road carries on (rider joins traffic)
  door     painted cycle lane next to parallel on-street parking (door zone)
Steep descents/climbs are not here: they come from Valhalla's per-edge grades on the phone (elevation is baked into the tiles).
"""
import math
import sqlite3
from collections import defaultdict

import osmium
import shapely
from pyproj import Transformer
from shapely.geometry import LineString, Point
from shapely.ops import transform

from common import load_config, log, out_dir, write_json

TO_M = Transformer.from_crs("EPSG:4326", "EPSG:32632", always_xy=True).transform
TO_LL = Transformer.from_crs("EPSG:32632", "EPSG:4326", always_xy=True).transform

COBBLES = {"sett", "cobblestone", "unhewn_cobblestone"}
ROADS = {"primary", "primary_link", "secondary", "secondary_link", "tertiary", "tertiary_link", "unclassified",
         "residential", "living_street", "service", "trunk", "trunk_link"}
PATHS = {"cycleway", "path", "track", "footway", "pedestrian", "bridleway"}
BARRIERS = {"bollard", "gate", "cycle_barrier", "lift_gate", "kissing_gate", "stile", "block", "swing_gate",
            "chain", "turnstile", "full-height_turnstile", "motorcycle_barrier", "sliding_gate"}
NO_BIKE = {"no", "dismount", "use_sidepath"}
LANE_VALUES = {"lane", "track", "opposite_lane", "opposite_track", "shared_busway"}
PARALLEL_PARKING = {"parallel", "lane", "street_side", "on_street", "half_on_kerb", "on_kerb"}


def cycle_usable(tags) -> bool:
    hw = tags.get("highway")
    if hw is None or tags.get("bicycle") in {"no"} or tags.get("area") == "yes" and hw != "pedestrian":
        return False
    if hw in ROADS or hw == "cycleway":
        return True
    if hw in {"path", "track", "bridleway"}:
        return tags.get("bicycle") not in NO_BIKE
    if hw in {"footway", "pedestrian"}:
        return tags.get("bicycle") in {"yes", "designated", "permissive"}
    return False


def has_cycle_infra(tags) -> bool:
    if tags.get("highway") == "cycleway":
        return True
    keys = ("cycleway", "cycleway:right", "cycleway:left", "cycleway:both")
    return any(tags.get(k) in LANE_VALUES for k in keys)


def painted_lane_sides(tags) -> set[str]:
    sides = set()
    for side in ("right", "left"):
        for key in (f"cycleway:{side}", "cycleway:both", "cycleway"):
            if tags.get(key) in {"lane", "opposite_lane"}:
                sides.add(side)
    return sides


def parking_sides(tags) -> set[str]:
    sides = set()
    for side in ("right", "left"):
        # parking:lane:* (old scheme) and parking:* + orientation (new scheme)
        old = tags.get(f"parking:lane:{side}") or tags.get("parking:lane:both")
        new = tags.get(f"parking:{side}") or tags.get("parking:both")
        orient = tags.get(f"parking:{side}:orientation") or tags.get("parking:both:orientation") or "parallel"
        if old == "parallel" or (new in PARALLEL_PARKING and orient == "parallel"):
            sides.add(side)
    return sides


def encode_polyline6(coords) -> str:
    out, plat, plon = [], 0, 0
    for lon, lat in coords:
        ilat, ilon = round(lat * 1e6), round(lon * 1e6)
        for d in (ilat - plat, ilon - plon):
            v = ~(d << 1) if d < 0 else d << 1
            while v >= 0x20:
                out.append(chr((0x20 | (v & 0x1F)) + 63))
                v >>= 5
            out.append(chr(v + 63))
        plat, plon = ilat, ilon
    return "".join(out)


class Collect(osmium.SimpleHandler):
    """One pass over the region with node locations."""

    def __init__(self):
        super().__init__()
        self.barrier_nodes: dict[int, tuple[str, float, float]] = {}
        self.crossing_nodes: list[tuple[int, float, float]] = []
        self.trams: list[tuple[int, list]] = []
        self.cycle_ways: list[tuple[int, list, dict]] = []
        self.infra_ends: list[tuple[int, int, float, float]] = []  # (way, node, lon, lat) ends of cycle infrastructure
        self.features: list[dict] = []

    def node(self, n):
        t = n.tags
        if t.get("barrier") in BARRIERS:
            self.barrier_nodes[n.id] = (t.get("barrier"), n.location.lon, n.location.lat)
        if t.get("railway") in {"tram_level_crossing", "tram_crossing"}:
            self.crossing_nodes.append((n.id, n.location.lon, n.location.lat))
        if t.get("bicycle") == "dismount" and not t.get("highway"):
            self.features.append(point("dismount", n.location.lon, n.location.lat, f"n{n.id}", "bicycle=dismount"))

    def way(self, w):
        t = w.tags
        try:
            coords = [(nd.lon, nd.lat) for nd in w.nodes]
        except osmium.InvalidLocationError:
            return
        if len(coords) < 2:
            return
        if t.get("railway") == "tram":
            self.trams.append((w.id, coords))
            return
        hw = t.get("highway")
        if hw == "steps":
            self.features.append(line("steps", coords, f"w{w.id}", t.get("step_count", "")))
            return
        if hw == "pedestrian" and t.get("bicycle") not in {"yes", "designated", "permissive"}:
            self.features.append(line("dismount", coords, f"w{w.id}", "pedestrian street"))
            return
        if not cycle_usable(t):
            return
        tags = {k: t.get(k) for k in ("highway", "surface", "bicycle", "maxwidth", "width", "name") if t.get(k)}
        for nd in w.nodes:
            if nd.ref in self.barrier_nodes:
                kind, lon, lat = self.barrier_nodes[nd.ref]
                self.features.append(point("gap", lon, lat, f"n{nd.ref}", kind))
        if t.get("surface") in COBBLES:
            self.features.append(line("cobbles", coords, f"w{w.id}", t.get("surface")))
        if t.get("bicycle") == "dismount":
            self.features.append(line("dismount", coords, f"w{w.id}", "bicycle=dismount"))
        width = parse_m(t.get("maxwidth"))
        if width is not None and width < 1.0:
            self.features.append(line("gap", coords, f"w{w.id}", f"maxwidth {width:g} m"))
        if painted_lane_sides(t) & parking_sides(t):
            self.features.append(line("door", coords, f"w{w.id}", "painted lane beside parking"))
        if has_cycle_infra(t):
            for nd in (w.nodes[0], w.nodes[-1]):
                self.infra_ends.append((w.id, nd.ref, nd.lon, nd.lat))
        self.cycle_ways.append((w.id, coords, tags))


class Neighbours(osmium.SimpleHandler):
    """Second pass: every way (cycle infra or road) that touches an end node of cycle infrastructure."""

    def __init__(self, nodes: set[int]):
        super().__init__()
        self.nodes = nodes
        self.node_ways: dict[int, list[tuple[int, bool, bool]]] = defaultdict(list)  # node → (way, infra, road)

    def way(self, w):
        t = w.tags
        hw = t.get("highway")
        if hw is None:
            return
        infra = has_cycle_infra(t)
        road = hw in ROADS and hw != "service" and not infra
        if not (infra or road):
            return
        for nd in w.nodes:
            if nd.ref in self.nodes:
                self.node_ways[nd.ref].append((w.id, infra, road))


def parse_m(value):
    if not value:
        return None
    try:
        return float(value.replace(",", ".").replace("m", "").strip())
    except ValueError:
        return None


def point(kind, lon, lat, osm, detail=""):
    return {"type": kind, "coords": [(lon, lat)], "osm": osm, "detail": detail, "length": 0.0}


def line(kind, coords, osm, detail=""):
    return {"type": kind, "coords": coords, "osm": osm, "detail": detail,
            "length": transform(TO_M, LineString(coords)).length}


def bearing(a, b) -> float:
    return math.degrees(math.atan2(b[1] - a[1], b[0] - a[0])) % 180


def tram_hazards(c: Collect) -> list[dict]:
    """Crossings (tagged nodes + geometric) and rails along cycle-usable ways."""
    if not c.trams:
        return []
    trams_m = [transform(TO_M, LineString(co)) for _, co in c.trams]
    tram_tree = shapely.STRtree(trams_m)
    out: list[dict] = []
    seen_m: list[Point] = []

    def add_crossing(lon, lat, osm, detail):
        p = Point(TO_M(lon, lat))
        if any(p.distance(q) < 10 for q in seen_m):
            return
        seen_m.append(p)
        out.append(point("tram", lon, lat, osm, detail))

    for nid, lon, lat in sorted(c.crossing_nodes):
        add_crossing(lon, lat, f"n{nid}", "tagged crossing")
    tram_area = shapely.union_all([t.buffer(10) for t in trams_m]).envelope
    for wid, coords, _ in c.cycle_ways:
        lm = transform(TO_M, LineString(coords))
        if not lm.intersects(tram_area):
            continue
        for ti in tram_tree.query(lm.buffer(3)):
            tram = trams_m[ti]
            inter = lm.intersection(tram)
            for g in getattr(inter, "geoms", [inter]):
                if g.geom_type == "Point" and not g.is_empty:
                    lon, lat = TO_LL(g.x, g.y)
                    add_crossing(lon, lat, f"w{wid}", "geometric crossing")
            # rails along: overlap of the way with a 3 m buffer around the rail, nearly parallel, > 30 m
            overlap = lm.intersection(tram.buffer(3, cap_style="flat"))
            for piece in getattr(overlap, "geoms", [overlap]):
                if piece.geom_type != "LineString" or piece.length < 30:
                    continue
                pc = list(piece.coords)
                proj_a = tram.interpolate(tram.project(Point(pc[0])))
                proj_b = tram.interpolate(tram.project(Point(pc[-1])))
                if proj_a.distance(proj_b) < 1:
                    continue
                diff = abs(bearing(pc[0], pc[-1]) - bearing(proj_a.coords[0], proj_b.coords[0]))
                if min(diff, 180 - diff) < 20:
                    ll = [TO_LL(x, y) for x, y in pc]
                    out.append({"type": "along", "coords": ll, "osm": f"w{wid}", "detail": "rails along the lane",
                                "length": piece.length})
    return out


def lane_end_hazards(c: Collect, pbf: str) -> list[dict]:
    n = Neighbours({nref for _, nref, _, _ in c.infra_ends})
    n.apply_file(pbf)
    out = []
    seen = set()
    for wid, nref, lon, lat in sorted(c.infra_ends):
        ways = n.node_ways.get(nref, [])
        other_infra = any(infra for w, infra, _ in ways if w != wid)
        continues_on_road = any(road for w, _, road in ways if w != wid)
        if continues_on_road and not other_infra and nref not in seen:
            seen.add(nref)
            out.append(point("lane", lon, lat, f"n{nref}", "cycle lane ends"))
    return out


def write_sqlite(path, features, meta):
    if path.exists():
        path.unlink()
    db = sqlite3.connect(path)
    db.executescript("""
        PRAGMA page_size = 4096;
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE hazards (
            id INTEGER PRIMARY KEY,
            type TEXT NOT NULL,          -- tram | along | cobbles | steps | gap | dismount | lane | door
            geom TEXT NOT NULL,          -- 'point' | 'line'
            lon REAL NOT NULL, lat REAL NOT NULL,   -- point, or line midpoint
            length_m REAL NOT NULL,
            polyline6 TEXT NOT NULL,     -- encoded polyline, precision 6 (lat, lon)
            detail TEXT NOT NULL,
            osm TEXT NOT NULL            -- n123 / w456
        );
        CREATE VIRTUAL TABLE hazards_rtree USING rtree(id, min_lon, max_lon, min_lat, max_lat);
    """)
    features.sort(key=lambda f: (f["type"], f["osm"], f["coords"][0]))
    for i, f in enumerate(features, start=1):
        co = f["coords"]
        lons, lats = [p[0] for p in co], [p[1] for p in co]
        if len(co) == 1:
            mid = co[0]
        else:
            ls = LineString(co)
            mid = ls.interpolate(0.5, normalized=True).coords[0]
        db.execute("INSERT INTO hazards VALUES (?,?,?,?,?,?,?,?,?)",
                   (i, f["type"], "point" if len(co) == 1 else "line", round(mid[0], 7), round(mid[1], 7),
                    round(f["length"], 1), encode_polyline6(co), f["detail"], f["osm"]))
        db.execute("INSERT INTO hazards_rtree VALUES (?,?,?,?,?)", (i, min(lons), max(lons), min(lats), max(lats)))
    db.execute("CREATE INDEX hazards_type ON hazards(type)")
    db.executemany("INSERT INTO meta VALUES (?,?)", sorted(meta.items()))
    db.commit()
    db.execute("VACUUM")
    db.close()


def main():
    cfg = load_config()
    out = out_dir(cfg)
    c = Collect()
    log("reading OSM")
    c.apply_file(str(out / "region.osm.pbf"), locations=True, idx="flex_mem")
    log(f"{len(c.cycle_ways)} cycle-usable ways, {len(c.trams)} tram ways, {len(c.barrier_nodes)} barrier nodes")
    features = c.features + tram_hazards(c) + lane_end_hazards(c, str(out / "region.osm.pbf"))
    counts = defaultdict(int)
    for f in features:
        counts[f["type"]] += 1
    log("counts: " + ", ".join(f"{k}={v}" for k, v in sorted(counts.items())))
    write_sqlite(out / "hazards.sqlite", features, {"schema": "1", "region": cfg["region"]["id"]})
    write_json(out / "hazards.counts.json", dict(sorted(counts.items())))


if __name__ == "__main__":
    main()
