"""Stage 1b: the area the pack covers → out/<region>/coverage.geojson: the region polygon grown by coverage.buffer_km.

Routing, hazards, routes and the timetable reach past the border so a trip just across it plans in this pack (Valhalla
tiles from two builds can't be joined on the phone). The map basemap and "you're in <region>" keep the exact border.
Both polygons ship in the manifest, simplified (manifest_polygon)."""
import json

from pyproj import Transformer
from shapely import make_valid
from shapely.geometry import mapping, shape
from shapely.ops import transform

from common import load_config, log, out_dir, utm_epsg, write_json


def utm(geom) -> int:
    """The UTM zone of the geometry's centre (was fixed at 32N, northern Italy, before M11)."""
    c = geom.representative_point()
    return utm_epsg(c.x, c.y)


def grow(geom, km: float):
    zone = utm(geom)
    to_m = Transformer.from_crs(4326, zone, always_xy=True).transform
    to_ll = Transformer.from_crs(zone, 4326, always_xy=True).transform
    return transform(to_ll, transform(to_m, geom).buffer(km * 1000, resolution=8).simplify(100))


def manifest_polygon(geom, tolerance_m: float) -> list:
    """A small GeoJSON MultiPolygon coordinate list for the app's point-in-region test (coordinates to 5 decimals)."""
    zone = utm(geom)
    to_m = Transformer.from_crs(4326, zone, always_xy=True).transform
    to_ll = Transformer.from_crs(zone, 4326, always_xy=True).transform
    g = transform(to_ll, transform(to_m, geom).simplify(tolerance_m))
    polys = [g] if g.geom_type == "Polygon" else list(g.geoms)

    def ring(r):
        return [[round(x, 5), round(y, 5)] for x, y in r.coords]
    return [[ring(p.exterior)] + [ring(i) for i in p.interiors] for p in polys]


def index_outline(geom, grow_m: float = 3000, tolerance_m: float = 1500) -> list:
    """The region's outline for the index (packs.json), a few KB: grown by 3 km so islets merge into one shape, simplified
    to 1.5 km, outer rings only, coordinates to 3 decimals (≈ 100 m). 266 KB for the 219 European regions (5 MB at the
    manifest's 250 m). Good enough for "this point is in a region you can download"; the exact border is in the manifest."""
    zone = utm(geom)
    to_m = Transformer.from_crs(4326, zone, always_xy=True).transform
    to_ll = Transformer.from_crs(zone, 4326, always_xy=True).transform
    g = make_valid(transform(to_m, geom)).buffer(grow_m, resolution=2).simplify(tolerance_m)
    polys = [g] if g.geom_type == "Polygon" else list(g.geoms)
    return [[[[round(x, 3), round(y, 3)] for x, y in transform(to_ll, p).exterior.coords]] for p in polys]


def main():
    cfg = load_config()
    out = out_dir(cfg)
    region = shape(json.loads((out / "region.geojson").read_text())["features"][0]["geometry"])
    km = cfg["coverage"]["buffer_km"]
    cov = grow(region, km) if km > 0 else region
    write_json(out / "coverage.geojson", {"type": "FeatureCollection", "features": [
        {"type": "Feature", "properties": {"buffer_km": km}, "geometry": mapping(cov)}]})
    log(f"coverage: border + {km} km, bounds {[round(v, 3) for v in cov.bounds]}")


if __name__ == "__main__":
    main()
