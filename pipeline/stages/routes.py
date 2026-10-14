"""Stage 5: OSM cycle-route relations for the Routes tab → out/<region>/routes.sqlite

Relations route=bicycle|mtb with network=lcn|rcn|ncn|icn (MTB routes are kept even without a network tag).
Geometry is the merged member ways, stored as encoded polylines (precision 6), one per merged piece."""
import json
import re
import sqlite3

import osmium
from shapely.geometry import LineString, MultiLineString
from shapely.ops import linemerge, transform

from common import load_config, log, out_dir, write_json
from hazards import TO_M, encode_polyline6

NETWORKS = {"lcn", "rcn", "ncn", "icn"}
EUROVELO = re.compile(r"^EV\s?(\d{1,2})$", re.I)


class Relations(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.routes: dict[int, dict] = {}
        self.way_ids: set[int] = set()

    def relation(self, r):
        t = r.tags
        if t.get("type") != "route" or t.get("route") not in {"bicycle", "mtb"}:
            return
        if t.get("state") == "proposed" or (t.get("route") == "bicycle" and t.get("network") not in NETWORKS):
            return
        ways = [m.ref for m in r.members if m.type == "w"]
        if not ways:
            return
        ref = t.get("ref", "")
        ev = EUROVELO.match(ref) if t.get("network") == "icn" else None
        self.routes[r.id] = {
            "kind": t.get("route"), "network": t.get("network", ""), "name": t.get("name") or t.get("name:en") or ref,
            "ref": ref, "eurovelo": int(ev.group(1)) if ev else None, "operator": t.get("operator", ""),
            "ways": ways}
        self.way_ids.update(ways)


class Ways(osmium.SimpleHandler):
    def __init__(self, wanted: set[int]):
        super().__init__()
        self.wanted = wanted
        self.coords: dict[int, list] = {}
        self.surface: dict[int, str] = {}

    def way(self, w):
        if w.id not in self.wanted:
            return
        try:
            self.coords[w.id] = [(n.lon, n.lat) for n in w.nodes]
        except osmium.InvalidLocationError:
            return
        self.surface[w.id] = w.tags.get("surface", "")


def main():
    cfg = load_config()
    out = out_dir(cfg)
    pbf = str(out / "region.osm.pbf")
    rel = Relations()
    rel.apply_file(pbf)
    ways = Ways(rel.way_ids)
    ways.apply_file(pbf, locations=True, idx="flex_mem")
    log(f"{len(rel.routes)} route relations, {len(ways.coords)}/{len(rel.way_ids)} member ways with geometry")

    path = out / "routes.sqlite"
    if path.exists():
        path.unlink()
    db = sqlite3.connect(path)
    db.executescript("""
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE routes (
            id INTEGER PRIMARY KEY,      -- OSM relation id
            kind TEXT NOT NULL,          -- bicycle | mtb
            network TEXT NOT NULL,       -- lcn | rcn | ncn | icn | ''
            name TEXT NOT NULL, ref TEXT NOT NULL, eurovelo INTEGER, operator TEXT NOT NULL,
            length_m REAL NOT NULL,
            paved_share REAL NOT NULL,   -- share of length on paved surfaces (unknown counts as paved)
            polylines TEXT NOT NULL      -- JSON array of polyline6 strings, one per merged piece
        );
        CREATE VIRTUAL TABLE routes_rtree USING rtree(id, min_lon, max_lon, min_lat, max_lat);
    """)
    unpaved = {"unpaved", "gravel", "fine_gravel", "compacted", "dirt", "earth", "ground", "grass", "mud", "sand",
               "pebblestone", "rock", "wood_chips"}
    counts = {"bicycle": 0, "mtb": 0, "eurovelo": 0}
    for rid in sorted(rel.routes):
        r = rel.routes[rid]
        pieces = [LineString(ways.coords[w]) for w in r["ways"] if w in ways.coords and len(ways.coords[w]) > 1]
        if not pieces:
            continue
        merged = linemerge(MultiLineString(pieces))
        lines = list(getattr(merged, "geoms", [merged]))
        length = sum(transform(TO_M, ln).length for ln in lines)
        if length < 200:
            continue
        unpaved_len = sum(transform(TO_M, LineString(ways.coords[w])).length for w in r["ways"]
                          if w in ways.coords and len(ways.coords[w]) > 1 and ways.surface.get(w) in unpaved)
        minx, miny, maxx, maxy = merged.bounds
        db.execute("INSERT INTO routes VALUES (?,?,?,?,?,?,?,?,?,?)", (
            rid, r["kind"], r["network"], r["name"], r["ref"], r["eurovelo"], r["operator"], round(length, 1),
            round(max(0.0, 1 - unpaved_len / length), 3),
            json.dumps([encode_polyline6(list(ln.coords)) for ln in lines])))
        db.execute("INSERT INTO routes_rtree VALUES (?,?,?,?,?)", (rid, minx, maxx, miny, maxy))
        counts[r["kind"]] += 1
        counts["eurovelo"] += r["eurovelo"] is not None
    db.execute("CREATE INDEX routes_kind ON routes(kind, network)")
    db.executemany("INSERT INTO meta VALUES (?,?)", [("region", cfg["region"]["id"]), ("schema", "1")])
    db.commit()
    db.execute("VACUUM")
    db.close()
    log(f"counts: {counts}")
    write_json(out / "routes.counts.json", counts)


if __name__ == "__main__":
    main()
