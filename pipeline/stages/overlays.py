"""Stage: Velix overlay tiles (P3 velix_cycling / velix_transit) → out/<region>/overlays.pmtiles.

OpenMapTiles has separate cycleways but no painted lanes and no metro line colours, so the pack carries its own
small vector layers, built from the same OSM extract as routing:

  velix_cycling   kind = protected | painted, side = both | left | right    (z11–14)
  velix_routes    EuroVelo (route=bicycle, network=icn), ref                (z8–14)
  velix_transit   mode = metro | train, ref, family, alt, tunnel             (z8–14)
  velix_stations  mode = metro | train, name, lines ("M1,M3")               (z11–14)

Cycle-lane tags follow hazards.py (one definition of "protected" / "painted" for the map and the comfort mix).
Metro families: metro_colors.py (P3 mapRules). Tiles: tippecanoe, written straight to PMTiles."""
import json
import subprocess
from collections import defaultdict

import osmium

from common import load_config, log, out_dir, write_json
from hazards import NO_BIKE, cycle_usable
from metro_colors import assign

PROTECTED_VALUES = {"track", "opposite_track", "separate"}
PAINTED_VALUES = {"lane", "opposite_lane", "shared_busway"}
SIDE_KEYS = {"both": ("cycleway", "cycleway:both"), "left": ("cycleway:left",), "right": ("cycleway:right",)}


def cycling_kind(tags) -> tuple[str, str] | None:
    """(kind, side) for a way that is or carries cycle infrastructure, else None."""
    hw = tags.get("highway")
    if hw == "cycleway" or (hw in {"path", "footway", "track"} and tags.get("bicycle") == "designated"):
        return ("protected", "both") if tags.get("bicycle") not in NO_BIKE else None
    if not cycle_usable(tags):
        return None
    found: dict[str, str] = {}
    for side, keys in SIDE_KEYS.items():
        for k in keys:
            v = tags.get(k)
            if v in PROTECTED_VALUES:
                found[side] = "protected"
            elif v in PAINTED_VALUES and found.get(side) != "protected":
                found[side] = "painted"
    if not found:
        return None
    kind = "protected" if "protected" in found.values() else "painted"
    sides = set(found)
    side = "both" if "both" in sides or sides == {"left", "right"} else sides.pop()
    return kind, side


METRO_ROUTES = {"subway"}
TRAIN_ROUTES = {"train", "light_rail"}


class Relations(osmium.SimpleHandler):
    """Pass 1: route relations we draw, and which ways and stop nodes they use."""

    def __init__(self):
        super().__init__()
        self.ways: dict[int, list[dict]] = defaultdict(list)   # way id → [{mode, ref, colour}]
        self.stops: dict[int, set[str]] = defaultdict(set)      # node id → metro refs
        self.metro_lines: dict[str, dict[str, str | None]] = defaultdict(dict)   # network → {ref: colour}

    def relation(self, r):
        t = r.tags
        route = t.get("route")
        if t.get("type") != "route" or route not in METRO_ROUTES | TRAIN_ROUTES | {"bicycle"}:
            return
        if route == "bicycle":
            ref = t.get("ref", "")
            if t.get("network") != "icn" or not ref.upper().startswith("EV"):
                return
            info = {"mode": "eurovelo", "ref": ref.upper().replace(" ", "")}
        else:
            mode = "metro" if route in METRO_ROUTES else "train"
            ref = t.get("ref") or t.get("name") or ""
            network = t.get("network") or t.get("operator") or ""
            info = {"mode": mode, "ref": ref, "network": network, "colour": t.get("colour")}
            if mode == "metro" and ref:
                self.metro_lines[network].setdefault(ref, t.get("colour"))
        for m in r.members:
            if m.type == "w" and m.role in {"", "forward", "backward", "main"}:
                self.ways[m.ref].append(info)
            elif m.type == "n" and info["mode"] == "metro" and m.role.startswith(("stop", "platform")):
                self.stops[m.ref].add(info["ref"])


class Geometry(osmium.SimpleHandler):
    """Pass 2: geometries for cycle infrastructure, route ways and stations."""

    def __init__(self, rel: Relations, families: dict[str, tuple[str, bool]]):
        super().__init__()
        self.rel, self.families = rel, families
        self.layers: dict[str, list[dict]] = defaultdict(list)
        self.stop_points: dict[int, tuple[float, float]] = {}

    def node(self, n):
        t = n.tags
        if n.id in self.rel.stops:
            self.stop_points[n.id] = (n.location.lon, n.location.lat)
        if t.get("railway") != "station" and t.get("public_transport") != "station":
            return
        name = t.get("name")
        if not name:
            return
        metro = t.get("station") == "subway" or t.get("subway") == "yes"
        train = t.get("train") == "yes" or (t.get("railway") == "station" and t.get("station") in (None, "train"))
        if metro or train:
            self.layers["velix_stations"].append(feature(
                {"type": "Point", "coordinates": [round(n.location.lon, 6), round(n.location.lat, 6)]},
                {"mode": "metro" if metro else "train", "name": name}))

    def way(self, w):
        coords = None
        kind = cycling_kind(w.tags)
        if kind or w.id in self.rel.ways:
            try:
                coords = [[round(nd.lon, 6), round(nd.lat, 6)] for nd in w.nodes]
            except osmium.InvalidLocationError:
                return
            if len(coords) < 2:
                return
        if kind:
            self.layers["velix_cycling"].append(feature(line(coords), {"kind": kind[0], "side": kind[1]}))
        seen_train = False
        for info in self.rel.ways.get(w.id, ()):
            tunnel = w.tags.get("tunnel") in {"yes", "building_passage"} or w.tags.get("layer", "0").startswith("-")
            if info["mode"] == "eurovelo":
                self.layers["velix_routes"].append(feature(line(coords), {"ref": info["ref"]}))
            elif info["mode"] == "metro":
                fam, alt = self.families.get((info["network"], info["ref"]), ("grey", False))
                self.layers["velix_transit"].append(feature(line(coords), {
                    "mode": "metro", "ref": info["ref"], "family": fam, "alt": alt, "tunnel": tunnel}))
            elif not seen_train:   # one train feature per way, however many services share it
                seen_train = True
                self.layers["velix_transit"].append(feature(line(coords), {"mode": "train", "tunnel": tunnel}))


def line(coords):
    return {"type": "LineString", "coordinates": coords}


def feature(geom, props):
    return {"type": "Feature", "geometry": geom, "properties": props}


def attach_lines(stations: list[dict], stops: dict[int, tuple[float, float]], refs: dict[int, set[str]]) -> None:
    """Metro stations get the lines whose stop members lie within 250 m."""
    pts = [(lon, lat, refs[nid]) for nid, (lon, lat) in stops.items()]
    for s in stations:
        if s["properties"]["mode"] != "metro":
            continue
        lon0, lat0 = s["geometry"]["coordinates"]
        lines = set()
        for lon, lat, r in pts:
            if abs(lat - lat0) < 0.0023 and abs(lon - lon0) < 0.0033:
                lines |= r
        s["properties"]["lines"] = ",".join(sorted(lines))


def dedupe_stations(stations: list[dict]) -> list[dict]:
    """OSM often maps a station twice (railway=station node + public_transport=station): keep one per name and mode
    within 300 m."""
    kept: list[dict] = []
    for s in stations:
        p = s["properties"]
        lon, lat = s["geometry"]["coordinates"]
        if not any(k["properties"]["name"] == p["name"] and k["properties"]["mode"] == p["mode"]
                   and abs(k["geometry"]["coordinates"][1] - lat) < 0.0027
                   and abs(k["geometry"]["coordinates"][0] - lon) < 0.0039 for k in kept):
            kept.append(s)
    return kept


ZOOMS = {"velix_cycling": (11, 14), "velix_routes": (8, 14), "velix_transit": (8, 14), "velix_stations": (11, 14)}


def main():
    cfg = load_config()
    out = out_dir(cfg)
    pbf = str(out / "region.osm.pbf")
    rel = Relations()
    rel.apply_file(pbf)
    # The "second line of a family takes alt" rule is per city: one network at a time.
    families = {(net, ref): fa for net, lines in rel.metro_lines.items() for ref, fa in assign(list(lines.items())).items()}
    log("metro lines: " + ", ".join(f"{n}/{r}={f}{'(alt)' if a else ''}" for (n, r), (f, a) in sorted(families.items())))
    geo = Geometry(rel, families)
    geo.apply_file(pbf, locations=True, idx="flex_mem")
    geo.layers["velix_stations"] = dedupe_stations(geo.layers["velix_stations"])
    attach_lines(geo.layers["velix_stations"], geo.stop_points, rel.stops)
    work = out / "overlays"
    work.mkdir(exist_ok=True)
    args = ["tippecanoe", "-o", str(out / "overlays.pmtiles"), "--force", "-Z8", "-z14",
            "--no-feature-limit", "--no-tile-size-limit", "--no-tile-stats", "--simplification=4",
            "--attribution=© OpenStreetMap contributors", "-n", "Velix overlays"]
    counts = {}
    for name, feats in sorted(geo.layers.items()):
        path = work / f"{name}.geojsonl"
        with open(path, "w") as f:
            for ft in feats:
                ft["tippecanoe"] = {"minzoom": ZOOMS[name][0], "maxzoom": ZOOMS[name][1]}
                f.write(json.dumps(ft, ensure_ascii=False) + "\n")
        args += ["-L", json.dumps({"file": str(path), "layer": name})]
        counts[name] = len(feats)
    log("features: " + ", ".join(f"{k}={v}" for k, v in counts.items()))
    subprocess.run(args, check=True)
    counts["bytes"] = (out / "overlays.pmtiles").stat().st_size
    counts["metro_lines"] = {f"{n}/{r}": {"family": f, "alt": a} for (n, r), (f, a) in sorted(families.items())}
    write_json(out / "overlays.counts.json", counts)
    log(f"overlays.pmtiles {counts['bytes'] / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
