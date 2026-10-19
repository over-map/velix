"""Stage 2b: routing copy of the extract → out/<region>/routing.osm.pbf (input of the Valhalla tile build).

Valhalla's parser files surface=sett as plain `paved` (like asphalt) and cobblestone as `paved_rough`, and its
bicycle costing only penalises surfaces from `dirt` (hybrid) / `compacted` (road bike) up. So cobbled ways are
retagged surface=gravel (original kept in velix:surface): Valhalla then slows them down for every bike, penalises them
by `avoid_bad_surfaces` (which Velix sets from the "No cobbles" rule; ≈ 7× the cost of asphalt per metre for a hybrid
at 0.8), and road bikes refuse them. `gravel`, not `dirt`: avoiding cobbles is the most frequent reason riders accept a
longer route (Filippo, 15 Oct), and `dirt` (≈ 3×) left 300–600 m of cobbles on central Milan trips. The hazard sidecar
still knows them as cobbles, so the comfort mix and the paved-only rule are unaffected.

Walk stretches (Filippo, 18 Oct): short passages open to pedestrians but not to bikes (crosswalks, footpaths, sidewalks,
pedestrian streets, private roads with public foot access such as a hospital's internal road) are made rideable (see below), as
Google's "Walk your bicycle" stretches. Their way ids go to
walk_ways.json → hazards.sqlite `walk_ways`, so the app can exclude them when "Allow walking stretches" is off.
Filippo rides these passages slowly rather than pushing (19 Oct), so they are tagged bicycle=yes, not dismount: at
Valhalla's fixed walking speed (≈ 5 km/h) every crossing cost ≈ 5 s and a 150 m hospital road ≈ 1.5 min, and routes
through residential grids lost to longer detours. They stay in walk_ways, so "Allow walking stretches" off avoids them.
Indoor, underground and paid passages (metro stations) and unpaved paths are never walk stretches. Steps without a bicycle ramp get
bicycle=no: once footpaths are walkable, Valhalla would otherwise carry the bike up and down stairs (19 Oct goldens)."""
import json
import math

import osmium
import shapely

from common import cobble_class, load_config, log, out_dir

BIKE_OK = {"yes", "designated", "permissive", "dismount", "use_sidepath", "destination"}
FOOT_OK = {"yes", "designated", "permissive"}
WALK_MAX_M = 200
CLOSED = {"private", "no", "customers"}
UNPAVED = {"unpaved", "compacted", "fine_gravel", "gravel", "pebblestone", "dirt", "earth", "ground", "grass", "mud",
           "sand", "woodchips", "rock"}


def below_or_indoors(tags) -> bool:
    try:
        layer = float(tags.get("layer", "0").split(";")[0])
    except ValueError:
        layer = 0
    return (tags.get("indoor") not in (None, "no") or tags.get("tunnel") not in (None, "no")
            or tags.get("location") in {"underground", "indoor"} or tags.get("fee") == "yes" or layer < 0)


def open_to_bikes(tags: dict) -> dict:
    """bicycle=yes, and a private `access` moved to motor_vehicle: Valhalla treats access=private as destination-only
    and never enters such a way mid-route, even with bicycle=yes (Via Gaetano Pini was only usable as a route's end)."""
    tags["velix:bicycle"] = tags.get("bicycle", "")
    tags["bicycle"] = "yes"
    if tags.get("access") in CLOSED:
        # motor_vehicle=no, not =private: Valhalla makes a way destination-only for every mode from any "private".
        tags["velix:access"] = tags.pop("access")
        tags["motor_vehicle"] = "no"
        # A road closed to cars but open on foot is car-free: weigh it like the other passages (a footway open to
        # bikes), calmer than any street with traffic. As a service road or even a living street Valhalla rated it
        # busier than the residential street beside it (Via Gaetano Pini vs Via Bianca di Savoia, Filippo, 19 Oct).
        if tags.get("highway") in {"service", "residential", "unclassified"}:
            tags["velix:highway"] = tags["highway"]
            tags["highway"] = "footway"
            tags.setdefault("surface", "asphalt")  # a road: Valhalla would assume an untagged footway is rough
    return tags


def lift_gate_closed_to_bikes(tags) -> bool:
    """A car barrier: riders go round it. With access=private Valhalla closes the whole way to bikes (Via Gaetano Pini,
    Milan, a hospital road open on foot that Google routes bikes through)."""
    return tags.get("barrier") == "lift_gate" and tags.get("access") in CLOSED and "bicycle" not in tags


def stairs_closed_to_bikes(tags) -> bool:
    """Steps a rider can't wheel the bike up: no bicycle ramp and no explicit bicycle access."""
    return (tags.get("highway") == "steps" and tags.get("ramp:bicycle") not in {"yes", "both", "left", "right"}
            and tags.get("bicycle") not in BIKE_OK)


def length_m(way) -> float:
    try:
        pts = [(n.lat, n.lon) for n in way.nodes]
    except osmium.InvalidLocationError:
        return math.inf
    total = 0.0
    for (a, b), (c, d) in zip(pts, pts[1:]):
        dy = (c - a) * 111_320
        dx = (d - b) * 111_320 * math.cos(math.radians(a))
        total += math.hypot(dx, dy)
    return total


def walkable_not_rideable(tags) -> bool:
    """Pedestrians may pass, bikes may not be ridden (Velix walks them there)."""
    hw = tags.get("highway")
    if hw is None or tags.get("area") == "yes" or tags.get("bicycle") in BIKE_OK:
        return False
    if below_or_indoors(tags) or tags.get("velix:surface", tags.get("surface")) in UNPAVED:
        return False                                       # park paths aren't shortcuts (Road goldens, 19 Oct)
    if tags.get("foot") in CLOSED or (tags.get("access") in CLOSED and tags.get("foot") not in FOOT_OK):
        return False                                       # no one on foot either
    if hw == "footway":
        return True   # crossings, footpaths and sidewalks (sidewalks only away from roads: see `beside_road`)
    if hw == "pedestrian":
        return True
    if hw in {"service", "residential", "unclassified", "living_street"}:
        return tags.get("access") in CLOSED and tags.get("foot") in FOOT_OK
    return False


ROADS = {"motorway", "trunk", "primary", "secondary", "tertiary", "unclassified", "residential", "living_street",
         "service", "motorway_link", "trunk_link", "primary_link", "secondary_link", "tertiary_link"}
BESIDE_ROAD_M = 15.0   # a sidewalk runs 3–10 m from its road's centre line
K_LON = 111_320 * math.cos(math.radians(45.5))


def xy(lat, lon):
    return lon * K_LON, lat * 111_320


class RoadIndex:
    """Road centre lines, to tell sidewalks along a street from sidewalk-tagged paths away from roads."""

    def __init__(self, src):
        lines = []
        for w in osmium.FileProcessor(str(src), osmium.osm.NODE | osmium.osm.WAY).with_locations():
            if not w.is_way():
                continue
            if w.tags.get("highway") not in ROADS:
                continue
            try:
                pts = [xy(n.lat, n.lon) for n in w.nodes]
            except osmium.InvalidLocationError:
                continue
            if len(pts) > 1:
                lines.append(shapely.LineString(pts))
        self.tree = shapely.STRtree(lines)

    def beside_road(self, way) -> bool:
        """Most of the way within BESIDE_ROAD_M of a road (crossing one doesn't count)."""
        try:
            pts = [shapely.Point(*xy(n.lat, n.lon)) for n in way.nodes]
        except osmium.InvalidLocationError:
            return True
        line = shapely.LineString([p.coords[0] for p in pts]) if len(pts) > 1 else None
        samples = [line.interpolate(f, normalized=True) for f in (0.1, 0.3, 0.5, 0.7, 0.9)] if line else pts
        near = sum(1 for p in samples if len(self.tree.query(p, predicate="dwithin", distance=BESIDE_ROAD_M)))
        return near > len(samples) / 2


CONNECTOR_MAX_M = 40.0
CONNECTOR_ID_BASE = 4_000_000_000   # above every OSM way id today, below Valhalla's 32-bit way id limit


def is_passage(way, tags, roads) -> bool:
    return (walkable_not_rideable(tags) and length_m(way) <= WALK_MAX_M
            and not (tags.get("footway") == "sidewalk" and roads.beside_road(way)))


def sidewalk_connectors(src, roads) -> list[tuple[int, list[int]]]:
    """Short pieces (≤ 40 m) of street sidewalks that link a passage to a crossing or a street: a path away from roads
    (Giardino Oriana Fallaci, Milan) often joins the street network only through the sidewalk beside it."""
    sidewalks: list[tuple[int, list[int], list[tuple[float, float]]]] = []
    passage_nodes: set[int] = set()
    for w in osmium.FileProcessor(str(src), osmium.osm.NODE | osmium.osm.WAY).with_locations():
        if not w.is_way() or "highway" not in w.tags:
            continue
        tags = dict(w.tags)
        if is_passage(w, tags, roads):
            if tags.get("footway") != "crossing":  # a crosswalk already joins its sidewalk to the street
                passage_nodes.update(n.ref for n in w.nodes)
        elif tags.get("highway") == "footway" and tags.get("footway") == "sidewalk" and walkable_not_rideable(tags):
            try:
                sidewalks.append((w.id, [n.ref for n in w.nodes], [(n.lat, n.lon) for n in w.nodes]))
            except osmium.InvalidLocationError:
                pass
    on_sidewalk = {r for _, refs, _ in sidewalks for r in refs}
    link_nodes: set[int] = set()
    for w in osmium.FileProcessor(str(src), osmium.osm.WAY):
        t = w.tags
        if t.get("highway") in ROADS or (t.get("highway") == "footway" and t.get("footway") == "crossing"):
            link_nodes.update(n.ref for n in w.nodes if n.ref in on_sidewalk)
    out, seen = [], set()
    for wid, refs, pts in sidewalks:
        for i, r in enumerate(refs):
            if r not in passage_nodes:
                continue
            for step in (1, -1):
                d, j = 0.0, i
                while 0 <= j + step < len(refs):
                    (a, b), (c, e) = pts[j], pts[j + step]
                    d += math.hypot((c - a) * 111_320, (e - b) * 111_320 * math.cos(math.radians(a)))
                    j += step
                    if d > CONNECTOR_MAX_M:
                        break
                    if refs[j] in link_nodes:
                        seg = tuple(refs[min(i, j):max(i, j) + 1])
                        if seg not in seen:
                            seen.add(seg)
                            out.append((wid, list(seg)))
                        break
    return out


def transform(src, dst):
    """Writes the routing copy of `src` to `dst`; returns (cobbled ways, walk-stretch way ids, steps, lift gates)."""
    if dst.exists():
        dst.unlink()
    writer = osmium.SimpleWriter(str(dst))
    changed = 0
    walk: list[int] = []
    stairs = 0
    gates = 0
    roads = RoadIndex(src)
    links = sidewalk_connectors(src, roads)
    pending = True
    for obj in osmium.FileProcessor(str(src)).with_locations():
        if pending and obj.is_relation():
            for k, (wid, refs) in enumerate(links):
                cid = CONNECTOR_ID_BASE + k
                writer.add_way(osmium.osm.mutable.Way(id=cid, version=1, nodes=refs, tags={
                    "highway": "footway", "footway": "sidewalk", "bicycle": "yes", "velix:connector": str(wid)}))
                walk.append(cid)
            pending = False
        if obj.is_node() and lift_gate_closed_to_bikes(obj.tags):
            tags = open_to_bikes(dict(obj.tags))
            tags["access"] = "yes"  # an access tag keeps Valhalla from timing it as an untagged gate (30 s)
            writer.add_node(obj.replace(tags=tags))
            gates += 1
            continue
        if not obj.is_way() or "highway" not in obj.tags:
            writer.add(obj)
            continue
        tags = dict(obj.tags)
        touched = False
        kind = cobble_class(tags)
        if kind:
            # Rough cobbles reach Valhalla as gravel (avoided, slow); smooth and mild ones as paving stones (ridden at
            # normal speed; Velix's "No cobbles" rule still counts mild ones at a third, see RuleChecker).
            tags["velix:surface"] = tags["surface"]
            tags["surface"] = "gravel" if kind == "rough" else "paving_stones"
            changed += 1
            touched = True
        if stairs_closed_to_bikes(tags):
            tags["velix:bicycle"] = tags.get("bicycle", "")
            tags["bicycle"] = "no"
            stairs += 1
            touched = True
        elif is_passage(obj, tags, roads):
            tags = open_to_bikes(tags)
            walk.append(obj.id)
            touched = True
        writer.add_way(obj.replace(tags=tags) if touched else obj)
    writer.close()
    log(f"{len(links)} sidewalk connectors (≤ {CONNECTOR_MAX_M:.0f} m) between passages and crossings or streets")
    return changed, walk, stairs, gates


def main():
    cfg = load_config()
    out = out_dir(cfg)
    dst = out / "routing.osm.pbf"
    changed, walk, stairs, gates = transform(out / "region.osm.pbf", dst)
    (out / "walk_ways.json").write_text(json.dumps(sorted(walk)))
    log(f"{dst.name}: {changed} cobbled ways retagged (rough → gravel, mild or smooth → paving_stones), {len(walk)} walk stretches bicycle=yes, "
        f"{stairs} steps bicycle=no, {gates} private lift gates bicycle=yes")


if __name__ == "__main__":
    main()
