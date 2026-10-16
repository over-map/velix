"""Stage 2: terrain model → 1-arc-second SRTM .hgt tiles that Valhalla's mjolnir reads to put grades on edges.
Source: GEDTM30 (global 30 m DTM, CC BY 4.0), read window by window from its Cloud Optimized GeoTIFF over HTTP.
The DEM is used at build time only; it is not shipped in the pack.
Outputs: out/<region>/elevation/N45/N45E009.hgt …, sources/elevation.json"""
import json
import math
import subprocess
from pathlib import Path

from common import cache_dir, load_config, log, out_dir


def region_bounds(geojson: Path) -> tuple[float, float, float, float]:
    xs, ys = [], []

    def walk(c):
        if isinstance(c[0], (int, float)):
            xs.append(c[0]); ys.append(c[1])
        else:
            for x in c:
                walk(x)

    for feat in json.loads(geojson.read_text())["features"]:
        walk(feat["geometry"]["coordinates"])
    return min(xs), min(ys), max(xs), max(ys)


def main() -> None:
    cfg = load_config()
    out = out_dir(cfg)
    el = cfg["elevation"]
    west, south, east, north = region_bounds(out / "region.geojson")
    tiles = [(lat, lon) for lat in range(math.floor(south), math.floor(north) + 1)
             for lon in range(math.floor(west), math.floor(east) + 1)]
    log(f"{len(tiles)} DEM tiles for bounds {west:.2f},{south:.2f},{east:.2f},{north:.2f}")
    dem_cache = cache_dir() / el["source"]
    dem_cache.mkdir(exist_ok=True)
    for lat, lon in tiles:
        ns, ew = ("N" if lat >= 0 else "S"), ("E" if lon >= 0 else "W")
        name = f"{ns}{abs(lat):02d}{ew}{abs(lon):03d}"
        hgt = out / "elevation" / name[:3] / f"{name}.hgt"
        if hgt.exists():
            continue
        # Pixel-is-point grid: centres on the 1/3600° lines, so the raster edge sits half a pixel outside the 1° tile.
        h = 1 / 7200
        window = dem_cache / f"{name}.tif"
        if not window.exists():
            log(f"read {name} window from {el['source']}")
            # Unscale (dm → m) while cutting the window, with a margin for the bilinear resample.
            m = 0.01
            subprocess.run(["gdal_translate", "-q", "-unscale", "-ot", "Float32",
                            "-projwin", f"{lon - m}", f"{lat + 1 + m}", f"{lon + 1 + m}", f"{lat - m}",
                            "-co", "COMPRESS=DEFLATE", f"/vsicurl/{el['url']}", str(window)], check=True)
        hgt.parent.mkdir(parents=True, exist_ok=True)
        tmp = hgt.with_suffix(".tif")
        subprocess.run(["gdalwarp", "-q", "-overwrite",
                        "-te", f"{lon - h:.10f}", f"{lat - h:.10f}", f"{lon + 1 + h:.10f}", f"{lat + 1 + h:.10f}",
                        "-tr", f"{1 / 3600:.12f}", f"{1 / 3600:.12f}", "-r", "bilinear", "-ot", "Int16",
                        "-dstnodata", "-32768", str(window), str(tmp)], check=True)
        subprocess.run(["gdal_translate", "-q", "-of", "SRTMHGT", str(tmp), str(hgt)], check=True)
        tmp.unlink()
        for aux in hgt.parent.glob(f"{name}.hgt.aux.xml"):
            aux.unlink()
    (out / "sources").mkdir(exist_ok=True)
    (out / "sources" / "elevation.json").write_text(json.dumps({
        "id": "elevation", "name": "GEDTM30 global terrain model (OpenGeoHub)",
        "url": "https://zenodo.org/records/15689805", "date": "2025-06-11",
        "licence": el["licence"], "attribution": el["attribution"]}, indent=2, sort_keys=True))
    log(f"elevation tiles ready in {out / 'elevation'}")


if __name__ == "__main__":
    main()
