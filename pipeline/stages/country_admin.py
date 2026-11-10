"""Writes out/<region>/country.osm.pbf: the countries of the pack's coverage (region border plus buffer), as admin_level=2.

Valhalla's admin builder skips the real country boundaries because the extracts cut them, and then loses each
country's default access rules. So each country's border (regions/countries.geojson, from Geofabrik, simplified),
clipped to the coverage, is written as a synthetic relation (nodes and ways from ids 9·10¹², clear of OSM's) with
the country's OSM name and name:en and its ISO codes: Lombardy's coverage holds Italy and Switzerland, each with its
own rules on its own side of the border. Before M11 the whole coverage was tagged as the config's one country.
Usage: python stages/country_admin.py <source.osm.pbf>"""
import json
import sys

import osmium
from shapely.geometry import shape

from common import PIPELINE, load_config, log, out_dir

BASE_ID = 9_000_000_000_000
WAY_NODES = 1900            # OSM ways hold at most 2000 nodes: long rings are split into chained ways


def rings(geom):
    polys = [geom] if geom.geom_type == "Polygon" else [g for g in getattr(geom, "geoms", []) if g.geom_type == "Polygon"]
    for p in polys:
        yield "outer", list(p.exterior.coords)
        for i in p.interiors:
            yield "inner", list(i.coords)


def relation_id(iso: str) -> int:
    """A stable synthetic relation id per country (2·10⁹ + the ISO code's letters)."""
    return 2_000_000_000 + ord(iso[0]) * 256 + ord(iso[1])


def country_tags(iso: str, name: str, name_en: str) -> dict:
    """The synthetic relation's tags. Valhalla's admin.lua skips level-2 "France" and "United Kingdom" (France's holds
    the overseas territories) and turns level-3 relations into countries ("Metropolitan France" becomes France, FR)."""
    tags = {"type": "boundary", "boundary": "administrative", "admin_level": "2", "name": name, "name:en": name_en,
            "ISO3166-1": iso, "ISO3166-1:alpha2": iso}
    if iso == "FR":
        tags.update({"admin_level": "3", "name": "France métropolitaine", "name:en": "Metropolitan France"})
    elif iso == "GB":
        tags["admin_level"] = "3"
    return tags


class CountryNames(osmium.SimpleHandler):
    """ISO alpha-2 → (name, name:en) from the extract's admin_level=2 relations (tags only)."""
    def __init__(self):
        super().__init__()
        self.names = {}

    def relation(self, r):
        if r.tags.get("admin_level") == "2" and r.tags.get("boundary") == "administrative":
            iso = r.tags.get("ISO3166-1:alpha2") or r.tags.get("ISO3166-1")
            if iso and "name" in r.tags:
                self.names[iso] = (r.tags["name"], r.tags.get("name:en", r.tags["name"]))


def parts(cov, countries: list) -> list:
    """[(iso, name, geometry)]: each country's share of the coverage, largest first, without overlaps (Geofabrik's
    borders overlap a little: an edge belongs to the first country that claims it)."""
    pieces, taken = [], None
    for f in sorted(countries, key=lambda f: -shape(f["geometry"]).intersection(cov).area):
        g = shape(f["geometry"]).buffer(0).intersection(cov)
        if taken is not None:
            g = g.difference(taken)
        if g.is_empty or g.area < 1e-8:
            continue
        taken = g if taken is None else taken.union(g)
        pieces.append((f["properties"]["iso"], f["properties"]["name"], g))
    return pieces


def main(src: str | None):
    cfg = load_config()
    out = out_dir(cfg)
    cov = shape(json.loads((out / "coverage.geojson").read_text())["features"][0]["geometry"])
    borders = PIPELINE / "regions" / "countries.geojson"
    if borders.exists():
        names = CountryNames()
        if src:
            names.apply_file(src)
        pieces = [(iso, *names.names.get(iso, (en, en)), g)
                  for iso, en, g in parts(cov, json.loads(borders.read_text())["features"])]
    else:   # no country borders yet: the whole coverage as the config's country (pre-M11 behaviour)
        c = cfg["region"]["country"]
        pieces = [(c["iso"], c["name"], c["name"], cov)]
    dst = out / "country.osm.pbf"
    if dst.exists():
        dst.unlink()
    writer = osmium.SimpleWriter(str(dst))
    nid = wid = BASE_ID
    nodes, ways, rels = [], [], []
    for iso, name, name_en, geom in pieces:
        members = []
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
        tags = country_tags(iso, name, name_en)
        rels.append(osmium.osm.mutable.Relation(id=relation_id(iso), members=members, tags=tags, version=1))
    for n in nodes:
        writer.add_node(n)
    for w in ways:
        writer.add_way(w)
    for r in sorted(rels, key=lambda r: r.id):
        writer.add_relation(r)
    writer.close()
    log(f"{dst.name}: {', '.join(f'{n} ({i})' for i, n, _, _ in pieces)}; {len(nodes)} nodes, {len(ways)} ways")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
