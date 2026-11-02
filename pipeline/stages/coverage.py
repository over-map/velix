"""Stage 1b: the area the pack covers → out/<region>/coverage.geojson: the region polygon grown by coverage.buffer_km.

Routing, hazards, routes and the timetable reach past the border so a trip just across it plans in this pack (Valhalla
tiles from two builds can't be joined on the phone). The map basemap and "you're in <region>" keep the exact border.
Both polygons ship in the manifest, simplified (manifest_polygon)."""
import json

from pyproj import Transformer
from shapely.geometry import mapping, shape
from shapely.ops import transform

from common import load_config, log, out_dir, write_json

UTM = 32632   # WGS 84 / UTM 32N: metres across northern Italy


def grow(geom, km: float):
    to_m = Transformer.from_crs(4326, UTM, always_xy=True).transform
    to_ll = Transformer.from_crs(UTM, 4326, always_xy=True).transform
    return transform(to_ll, transform(to_m, geom).buffer(km * 1000, resolution=8).simplify(100))


def manifest_polygon(geom, tolerance_m: float) -> list:
    """A small GeoJSON MultiPolygon coordinate list for the app's point-in-region test (coordinates to 5 decimals)."""
    to_m = Transformer.from_crs(4326, UTM, always_xy=True).transform
    to_ll = Transformer.from_crs(UTM, 4326, always_xy=True).transform
    g = transform(to_ll, transform(to_m, geom).simplify(tolerance_m))
    polys = [g] if g.geom_type == "Polygon" else list(g.geoms)

    def ring(r):
        return [[round(x, 5), round(y, 5)] for x, y in r.coords]
    return [[ring(p.exterior)] + [ring(i) for i in p.interiors] for p in polys]


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
