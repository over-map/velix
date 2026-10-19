"""Stage 2b: routing copy of the extract → out/<region>/routing.osm.pbf (input of the Valhalla tile build).

Valhalla's parser files surface=sett as plain `paved` (like asphalt) and cobblestone as `paved_rough`, and its
bicycle costing only penalises surfaces from `dirt` (hybrid) / `compacted` (road bike) up. So cobbled ways are
retagged surface=gravel (original kept in velix:surface): Valhalla then slows them down for every bike, penalises them
by `avoid_bad_surfaces` (which Velix sets from the "No cobbles" rule; ≈ 7× the cost of asphalt per metre for a hybrid
at 0.8), and road bikes refuse them. `gravel`, not `dirt`: avoiding cobbles is the most frequent reason riders accept a
longer route (Filippo, 15 Oct), and `dirt` (≈ 3×) left 300–600 m of cobbles on central Milan trips. The hazard sidecar
still knows them as cobbles, so the comfort mix and the paved-only rule are unaffected.

Walk stretches (Filippo, 18 Oct): short passages open to pedestrians but not to bikes (crosswalks, footpaths,
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

from common import load_config, log, out_dir

COBBLES = {"sett", "cobblestone", "unhewn_cobblestone"}
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
        return tags.get("footway") != "sidewalk"          # crossings and footpaths; sidewalks run beside roads
    if hw == "pedestrian":
        return True
    if hw in {"service", "residential", "unclassified", "living_street"}:
        return tags.get("access") in CLOSED and tags.get("foot") in FOOT_OK
    return False


def transform(src, dst):
    """Writes the routing copy of `src` to `dst`; returns (cobbled ways, walk-stretch way ids, steps, lift gates)."""
    if dst.exists():
        dst.unlink()
    writer = osmium.SimpleWriter(str(dst))
    changed = 0
    walk: list[int] = []
    stairs = 0
    gates = 0
    for obj in osmium.FileProcessor(str(src)).with_locations():
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
        if tags.get("surface") in COBBLES:
            tags["velix:surface"] = tags["surface"]
            tags["surface"] = "gravel"
            changed += 1
            touched = True
        if stairs_closed_to_bikes(tags):
            tags["velix:bicycle"] = tags.get("bicycle", "")
            tags["bicycle"] = "no"
            stairs += 1
            touched = True
        elif walkable_not_rideable(tags) and length_m(obj) <= WALK_MAX_M:
            tags = open_to_bikes(tags)
            walk.append(obj.id)
            touched = True
        writer.add_way(obj.replace(tags=tags) if touched else obj)
    writer.close()
    return changed, walk, stairs, gates


def main():
    cfg = load_config()
    out = out_dir(cfg)
    dst = out / "routing.osm.pbf"
    changed, walk, stairs, gates = transform(out / "region.osm.pbf", dst)
    (out / "walk_ways.json").write_text(json.dumps(sorted(walk)))
    log(f"{dst.name}: {changed} cobbled ways retagged surface=gravel, {len(walk)} walk stretches bicycle=yes, "
        f"{stairs} steps bicycle=no, {gates} private lift gates bicycle=yes")


if __name__ == "__main__":
    main()
