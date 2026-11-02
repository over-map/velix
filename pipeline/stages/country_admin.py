"""Writes out/<region>/country.osm.pbf: the pack's coverage (region border plus buffer) as its country (admin_level=2).

Valhalla's admin builder skips the real country boundary because the extract cuts it, and then loses the country's
default access rules. Every edge in the pack lies in the coverage polygon, and the extract is Italy's: the coverage
tagged as the country gives Valhalla the same answer without the whole national boundary. The polygon is written as
synthetic nodes and ways (ids from 9·10¹², clear of OSM's) with the relation id of the config."""
import json

import osmium
from shapely.geometry import shape

from common import load_config, log, out_dir

BASE_ID = 9_000_000_000_000
WAY_NODES = 1900            # OSM ways hold at most 2000 nodes: long rings are split into chained ways


def rings(geom):
    polys = [geom] if geom.geom_type == "Polygon" else list(geom.geoms)
    for p in polys:
        yield "outer", list(p.exterior.coords)
        for i in p.interiors:
            yield "inner", list(i.coords)


def main():
    cfg = load_config()
    out = out_dir(cfg)
    country = cfg["region"]["country"]
    geom = shape(json.loads((out / "coverage.geojson").read_text())["features"][0]["geometry"])
    dst = out / "country.osm.pbf"
    if dst.exists():
        dst.unlink()
    writer = osmium.SimpleWriter(str(dst))
    nid = wid = BASE_ID
    nodes, ways, members = [], [], []
    for role, coords in rings(geom):
        first = nid + 1
        ids = []
        for lon, lat in coords[:-1]:
            nid += 1
            nodes.append(osmium.osm.mutable.Node(id=nid, location=(lon, lat), version=1))
            ids.append(nid)
        ids.append(first)                                   # closed ring
        for i in range(0, len(ids) - 1, WAY_NODES):
            wid += 1
            ways.append(osmium.osm.mutable.Way(id=wid, nodes=ids[i:i + WAY_NODES + 1], version=1))
            members.append(("w", wid, role))
    for n in nodes:
        writer.add_node(n)
    for w in ways:
        writer.add_way(w)
    tags = {"type": "boundary", "boundary": "administrative", "admin_level": "2",
            "name": country["name"], "ISO3166-1": country["iso"], "ISO3166-1:alpha2": country["iso"]}
    writer.add_relation(osmium.osm.mutable.Relation(id=country["osm_relation"], members=members, tags=tags, version=1))
    writer.close()
    log(f"{dst.name}: {cfg['region']['name']} coverage as {country['name']} ({country['iso']}), "
        f"{len(nodes)} nodes, {len(ways)} ways")


if __name__ == "__main__":
    main()
