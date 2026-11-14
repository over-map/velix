"""Stage 7: compress each pack file with xz and write manifest.json → out/<region>/pack/

Release assets are the files in pack/ (manifest.json + *.xz); the app downloads and verifies them one by one.
xz runs single-threaded (one block): the best ratio, and output that does not depend on the machine's core count."""
import json
import subprocess

from shapely.geometry import shape

from common import load_config, log, out_dir, sha256, write_json
from coverage import index_outline, manifest_polygon

FILES = [("valhalla_tiles.tar", "routing_tiles"), ("hazards.sqlite", "hazards"),
         ("routes.sqlite", "routes"), ("transit.sqlite", "transit"),
         ("basemap.pmtiles", "basemap"), ("overlays.pmtiles", "overlays"),
         # The city area (config region.city_area_relation): the "destination outside the city" transit trigger (M8).
         ("city.geojson", "city")]


def main():
    cfg = load_config()
    out = out_dir(cfg)
    pack = out / "pack"
    pack.mkdir(exist_ok=True)
    files = []
    for name, role in FILES:
        src = out / name
        dst = pack / f"{name}.xz"
        log(f"xz {name} ({src.stat().st_size / 1e6:.0f} MB)")
        with open(dst, "wb") as f:
            subprocess.run(["xz", f"-{cfg['pack']['xz_preset']}", "-T1", "-c", str(src)],
                           stdout=f, check=True)
        files.append({"name": name, "asset": dst.name, "role": role, "bytes": dst.stat().st_size,
                      "sha256": sha256(dst), "unpacked_bytes": src.stat().st_size, "unpacked_sha256": sha256(src)})

    sources = [json.loads(p.read_text()) for p in sorted((out / "sources").glob("*.json"))]
    counts = {p.name.split(".")[0]: json.loads(p.read_text()) for p in sorted(out.glob("*.counts.json"))}
    region = shape(json.loads((out / "region.geojson").read_text())["features"][0]["geometry"])
    coverage = shape(json.loads((out / "coverage.geojson").read_text())["features"][0]["geometry"])
    box = lambda g: [round(v, 5) for v in g.bounds]  # noqa: E731
    built = next(s["date"][:10] for s in sources if s["id"] == "osm")
    manifest = {
        "schema": 1, "pack": cfg["region"]["id"], "name": cfg["region"]["name"], "version": built[:7].replace("-", "."),
        "country": cfg["region"]["country"]["iso"],
        "built": built, "valhalla": cfg["valhalla"]["version"],
        "bbox": box(region),
        "polygon_sha256": sha256(out / "region.geojson"),
        # The app's "which region is this point in" (exact border) and "can this pack route here" (border + buffer).
        "polygon": manifest_polygon(region, 250),
        # The index's small outline (stages/index.py copies it into packs.json).
        "outline": index_outline(region),
        "coverage": {"buffer_km": cfg["coverage"]["buffer_km"], "bbox": box(coverage), "polygon": manifest_polygon(coverage, 250)},
        "files": files,
        "download_bytes": sum(f["bytes"] for f in files),
        "unpacked_bytes": sum(f["unpacked_bytes"] for f in files),
        "budget_bytes": cfg["pack"]["budget_mb"] * 1_000_000,
        "sources": sources, "counts": counts}
    write_json(pack / "manifest.json", manifest)
    log(f"download {manifest['download_bytes'] / 1e6:.1f} MB · on phone {manifest['unpacked_bytes'] / 1e6:.0f} MB "
        f"· budget {cfg['pack']['budget_mb']} MB")


if __name__ == "__main__":
    main()
