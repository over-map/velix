"""Stage 2b: routing copy of the extract → out/<region>/routing.osm.pbf (input of the Valhalla tile build).

Valhalla's parser files surface=sett as plain `paved` (like asphalt) and cobblestone as `paved_rough`, and its
bicycle costing only penalises surfaces from `dirt` (hybrid) / `compacted` (road bike) up. So cobbled ways are
retagged surface=gravel (original kept in velix:surface): Valhalla then slows them down for every bike, penalises them
by `avoid_bad_surfaces` (which Velix sets from the "No cobbles" rule; ≈ 7× the cost of asphalt per metre for a hybrid
at 0.8), and road bikes refuse them. `gravel`, not `dirt`: avoiding cobbles is the most frequent reason riders accept a
longer route (Filippo, 15 Oct), and `dirt` (≈ 3×) left 300–600 m of cobbles on central Milan trips. The hazard sidecar
still knows them as cobbles, so the comfort mix and the paved-only rule are unaffected.

Walk stretches (Filippo, 18 Oct): short passages open to pedestrians but not to bikes (crosswalks, footpaths,
pedestrian streets, private roads with public foot access such as a hospital's internal road) get bicycle=dismount, which
Valhalla routes at walking speed. Riders push the bike there, as Google's "Walk your bicycle". Their way ids go to
walk_ways.json → hazards.sqlite `walk_ways`, so the app can exclude them when "Allow walking stretches" is off.
Crosswalks up to 30 m get bicycle=yes instead: riders cross them at about riding speed, and at Valhalla's walking
speed every crossing cost ≈ 5 s, so routes with many of them lost to longer detours (Via Soave → Piazza Santo Stefano:
Google's calm route crosses 12, ≈ 1 min). They stay in walk_ways, so "Allow walking stretches" off still avoids them.
Indoor, underground and paid passages (metro stations) are never walk stretches. Steps without a bicycle ramp get
bicycle=no: once footpaths are walkable, Valhalla would otherwise carry the bike up and down stairs (19 Oct goldens)."""
import json
import math

import osmium

from common import load_config, log, out_dir

COBBLES = {"sett", "cobblestone", "unhewn_cobblestone"}
BIKE_OK = {"yes", "designated", "permissive", "dismount", "use_sidepath", "destination"}
FOOT_OK = {"yes", "designated", "permissive"}
WALK_MAX_M = 200
CROSSING_MAX_M = 30
CLOSED = {"private", "no", "customers"}


def below_or_indoors(tags) -> bool:
    try:
        layer = float(tags.get("layer", "0").split(";")[0])
    except ValueError:
        layer = 0
    return (tags.get("indoor") not in (None, "no") or tags.get("tunnel") not in (None, "no")
            or tags.get("location") in {"underground", "indoor"} or tags.get("fee") == "yes" or layer < 0)


def is_short_crossing(tags, length: float) -> bool:
    return tags.get("highway") == "footway" and tags.get("footway") == "crossing" and length <= CROSSING_MAX_M


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
    if below_or_indoors(tags):
        return False
    if tags.get("foot") in CLOSED or (tags.get("access") in CLOSED and tags.get("foot") not in FOOT_OK):
        return False                                       # no one on foot either
    if hw == "footway":
        return tags.get("footway") != "sidewalk"          # crossings and footpaths; sidewalks run beside roads
    if hw == "pedestrian":
        return True
    if hw in {"service", "residential", "unclassified", "living_street"}:
        return tags.get("access") in CLOSED and tags.get("foot") in FOOT_OK
    return False


def main():
    cfg = load_config()
    out = out_dir(cfg)
    src, dst = out / "region.osm.pbf", out / "routing.osm.pbf"
    if dst.exists():
        dst.unlink()
    writer = osmium.SimpleWriter(str(dst))
    changed = 0
    walk: list[int] = []
    stairs = 0
    for obj in osmium.FileProcessor(str(src)).with_locations():
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
        elif walkable_not_rideable(tags) and (length := length_m(obj)) <= WALK_MAX_M:
            tags["velix:bicycle"] = tags.get("bicycle", "")
            tags["bicycle"] = "yes" if is_short_crossing(tags, length) else "dismount"
            walk.append(obj.id)
            touched = True
        writer.add_way(obj.replace(tags=tags) if touched else obj)
    writer.close()
    (out / "walk_ways.json").write_text(json.dumps(sorted(walk)))
    log(f"{dst.name}: {changed} cobbled ways retagged surface=gravel, {len(walk)} walk stretches bicycle=dismount, "
        f"{stairs} steps bicycle=no")


if __name__ == "__main__":
    main()
