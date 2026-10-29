"""Stage 5: OSM cycle-route relations for the Routes tab → out/<region>/routes.sqlite

Relations route=bicycle|mtb with network=lcn|rcn|ncn|icn (MTB routes are kept even without a network tag).
Geometry is the merged member ways, stored as encoded polylines (precision 6), one per merged piece.
Schema 2 adds the S7 mix (car-free / quiet road / gravel shares of the length), the climb both ways from the pack's
elevation tiles, and the OSM description, from and to."""
import json
import math
import mmap
import re
import sqlite3
from pathlib import Path

import osmium
from shapely.geometry import LineString, MultiLineString
from shapely.ops import linemerge, transform

from common import load_config, log, out_dir, write_json
from hazards import TO_M, encode_polyline6
from overlays import cycling_kind

NETWORKS = {"lcn", "rcn", "ncn", "icn"}
UNPAVED = {"unpaved", "gravel", "fine_gravel", "compacted", "dirt", "earth", "ground", "grass", "mud", "sand",
           "pebblestone", "rock", "wood_chips"}
PAVED = {"paved", "asphalt", "concrete", "concrete:plates", "paving_stones", "sett", "cobblestone", "chipseal"}
QUIET = {"residential", "living_street", "service", "unclassified", "pedestrian"}
# The S7 mix bar's three keys (P7: car-free paved, quiet road, gravel); the rest of the length is busier road.
MIX = ("car_free", "quiet", "unpaved")


def mix_class(tags) -> str:
    """car_free | quiet | unpaved | road for one member way (S7 mix bar). Unpaved wins: gravel is what it is."""
    surface, hw = tags.get("surface", ""), tags.get("highway", "")
    untagged_dirt = hw == "track" or (hw in {"path", "bridleway"} and tags.get("bicycle") != "designated")
    if surface in UNPAVED or (untagged_dirt and surface not in PAVED and tags.get("tracktype") != "grade1"):
        return "unpaved"
    if hw in {"cycleway", "footway", "path"} or cycling_kind(tags) == ("protected", "both") \
            or tags.get("bicycle_road") == "yes" or tags.get("cyclestreet") == "yes":
        return "car_free"
    # Paved farm tracks carry the odd tractor: quiet road, like residential streets.
    return "quiet" if hw in QUIET or hw == "track" else "road"


class Elevation:
    """Heights from the pack's 1″ SRTM-format tiles (out/<region>/elevation/N45/N45E009.hgt), nearest sample."""
    SIZE = 3601

    def __init__(self, root: Path):
        self.root = root
        self.tiles: dict[str, mmap.mmap | None] = {}

    def __call__(self, lon: float, lat: float) -> float | None:
        la, lo = math.floor(lat), math.floor(lon)
        name = f"{'N' if la >= 0 else 'S'}{abs(la):02d}{'E' if lo >= 0 else 'W'}{abs(lo):03d}"
        if name not in self.tiles:
            path = self.root / name[:3] / f"{name}.hgt"
            if path.exists():
                with path.open("rb") as f:   # the map outlives the file object
                    self.tiles[name] = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
            else:
                self.tiles[name] = None
        tile = self.tiles[name]
        if tile is None:
            return None
        row = round((la + 1 - lat) * (self.SIZE - 1))
        col = round((lon - lo) * (self.SIZE - 1))
        i = 2 * (row * self.SIZE + col)
        v = int.from_bytes(tile[i:i + 2], "big", signed=True)
        return None if v == -32768 else float(v)


def smooth(profile: list[float], window: int = 5) -> list[float]:
    """Moving average (5 samples ≈ 150 m): the terrain model's pixel noise isn't climbing."""
    half = window // 2
    return [sum(profile[max(0, i - half):i + half + 1]) / len(profile[max(0, i - half):i + half + 1]) for i in range(len(profile))]


def climb(profile: list[float], step: float = 2.0) -> float:
    """Metres climbed along a height profile, ignoring changes under `step` (the app's RideStats rule)."""
    total, ref = 0.0, None
    for h in profile:
        if ref is None:
            ref = h
        elif abs(h - ref) >= step:
            total += max(0.0, h - ref)
            ref = h
    return total


def profile(lines, height, every: float = 30.0) -> list[float]:
    """Heights every `every` metres along the lines (lon/lat), in order."""
    out = []
    for line in lines:
        coords = list(line.coords)
        carry = 0.0
        for (x0, y0), (x1, y1) in zip(coords, coords[1:]):
            d = math.hypot((x1 - x0) * 111_320 * math.cos(math.radians(y0)), (y1 - y0) * 110_574)
            t = carry
            while t < d:
                h = height(x0 + (x1 - x0) * t / d, y0 + (y1 - y0) * t / d)
                if h is not None:
                    out.append(h)
                t += every
            carry = t - d
    return out
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
            "description": t.get("description") or t.get("description:en") or "", "from": t.get("from", ""),
            "to": t.get("to", ""), "ways": ways}
        self.way_ids.update(ways)


class Ways(osmium.SimpleHandler):
    def __init__(self, wanted: set[int]):
        super().__init__()
        self.wanted = wanted
        self.coords: dict[int, list] = {}
        self.surface: dict[int, str] = {}
        self.mix: dict[int, str] = {}

    def way(self, w):
        if w.id not in self.wanted:
            return
        try:
            self.coords[w.id] = [(n.lon, n.lat) for n in w.nodes]
        except osmium.InvalidLocationError:
            return
        tags = {k: w.tags.get(k) for k in ("highway", "surface", "tracktype", "bicycle", "bicycle_road", "cyclestreet",
                                           "cycleway", "cycleway:both", "cycleway:left", "cycleway:right")
                if w.tags.get(k) is not None}
        self.surface[w.id] = tags.get("surface", "")
        self.mix[w.id] = mix_class(tags)


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
            polylines TEXT NOT NULL,     -- JSON array of polyline6 strings, one per merged piece
            car_free_share REAL NOT NULL,  -- S7 mix: cycleways and car-free paths
            quiet_share REAL NOT NULL,     -- residential, service, unclassified, living streets
            unpaved_share REAL NOT NULL,   -- gravel and other unpaved surfaces (the rest is busier road)
            climb_m REAL,                  -- metres up along the pieces in stored order; NULL without elevation
            descent_m REAL,                -- the same the other way
            description TEXT NOT NULL, "from" TEXT NOT NULL, "to" TEXT NOT NULL
        );
        CREATE VIRTUAL TABLE routes_rtree USING rtree(id, min_lon, max_lon, min_lat, max_lat);
    """)
    unpaved = UNPAVED
    height = Elevation(out / "elevation")
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
        by_mix = {k: 0.0 for k in MIX}
        for w in r["ways"]:
            if w in ways.coords and len(ways.coords[w]) > 1 and ways.mix.get(w) in by_mix:
                by_mix[ways.mix[w]] += transform(TO_M, LineString(ways.coords[w])).length
        shares = [round(min(1.0, by_mix[k] / length), 3) for k in MIX]
        # Per merged piece (the gaps between pieces aren't ridden), smoothed.
        pieces_h = [smooth(profile([ln], height)) for ln in lines]
        pieces_h = [h for h in pieces_h if len(h) > 1]
        up = round(sum(climb(h) for h in pieces_h), 0) if pieces_h else None
        down = round(sum(climb(h[::-1]) for h in pieces_h), 0) if pieces_h else None
        minx, miny, maxx, maxy = merged.bounds
        db.execute("INSERT INTO routes VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", (
            rid, r["kind"], r["network"], r["name"], r["ref"], r["eurovelo"], r["operator"], round(length, 1),
            round(max(0.0, 1 - unpaved_len / length), 3),
            json.dumps([encode_polyline6(list(ln.coords)) for ln in lines]), *shares, up, down,
            r["description"], r["from"], r["to"]))
        db.execute("INSERT INTO routes_rtree VALUES (?,?,?,?,?)", (rid, minx, maxx, miny, maxy))
        counts[r["kind"]] += 1
        counts["eurovelo"] += r["eurovelo"] is not None
    db.execute("CREATE INDEX routes_kind ON routes(kind, network)")
    db.executemany("INSERT INTO meta VALUES (?,?)", [("region", cfg["region"]["id"]), ("schema", "2")])
    db.commit()
    db.execute("VACUUM")
    db.close()
    log(f"counts: {counts}")
    write_json(out / "routes.counts.json", counts)


if __name__ == "__main__":
    main()
