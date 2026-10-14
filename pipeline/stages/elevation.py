"""Stage 2: Copernicus GLO-30 DEM → 1-arc-second SRTM .hgt tiles that Valhalla's mjolnir reads to put grades on edges.
The DEM is used at build time only; it is not shipped in the pack.
Outputs: out/<region>/elevation/N45/N45E009.hgt …, sources/elevation.json"""
import json
import math
import subprocess
import urllib.request
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
    dem_cache = cache_dir() / "copernicus-glo30"
    dem_cache.mkdir(exist_ok=True)
    for lat, lon in tiles:
        ns, ew = ("N" if lat >= 0 else "S"), ("E" if lon >= 0 else "W")
        name = f"{ns}{abs(lat):02d}{ew}{abs(lon):03d}"
        hgt = out / "elevation" / name[:3] / f"{name}.hgt"
        if hgt.exists():
            continue
        url = el["url_template"].format(ns=ns, lat=abs(lat), ew=ew, lon=abs(lon))
        tif = dem_cache / Path(url).name
        if not tif.exists():
            log(f"download {tif.name}")
            try:
                urllib.request.urlretrieve(url, tif.with_suffix(".part"))
            except urllib.error.HTTPError as e:
                if e.code in (403, 404):  # sea-only tiles don't exist
                    log(f"no DEM tile {name} ({e.code}), skipping")
                    continue
                raise
            tif.with_suffix(".part").rename(tif)
        hgt.parent.mkdir(parents=True, exist_ok=True)
        # SRTM HGT: 3601×3601 samples.
        tmp = hgt.with_suffix(".tif")
        # Pixel-is-point grid: centres on the 1/3600° lines, so the raster edge sits half a pixel outside the 1° tile.
        h = 1 / 7200
        subprocess.run(["gdalwarp", "-q", "-overwrite",
                        "-te", f"{lon - h:.10f}", f"{lat - h:.10f}", f"{lon + 1 + h:.10f}", f"{lat + 1 + h:.10f}",
                        "-tr", f"{1 / 3600:.12f}", f"{1 / 3600:.12f}", "-r", "bilinear", "-ot", "Int16",
                        "-dstnodata", "-32768", str(tif), str(tmp)], check=True)
        subprocess.run(["gdal_translate", "-q", "-of", "SRTMHGT", str(tmp), str(hgt)], check=True)
        tmp.unlink()
        for aux in hgt.parent.glob(f"{name}.hgt.aux.xml"):
            aux.unlink()
    (out / "sources").mkdir(exist_ok=True)
    (out / "sources" / "elevation.json").write_text(json.dumps({
        "id": "elevation", "name": "Copernicus DEM GLO-30 (AWS Open Data)",
        "url": "https://registry.opendata.aws/copernicus-dem/", "date": "2021",
        "licence": el["licence"], "attribution": el["attribution"]}, indent=2, sort_keys=True))
    log(f"elevation tiles ready in {out / 'elevation'}")


if __name__ == "__main__":
    main()
