"""Slice stage (M11 PR 3): download each Geofabrik leaf once and cut it for every region of the run that needs it, so a
Europe run downloads 201 leaves instead of 1,202 (each region job used to fetch its own). One `osmium extract` pass per
leaf writes all its slices.

A slice is the leaf clipped to the region's catalogue border grown by the coverage buffer + 5 km (simplification and
hand-written borders stay inside), → slices/<region>/<leaf>.osm.pbf, with <leaf>.json: the source URL, the data's
timestamp and the leaf's country names (country_admin reads them: a slice can lose the country relations).
extract.sh then merges the slices instead of downloading.
Usage: REGIONS="id id…" python stages/slice.py [--delete] <leaf>…   (REGIONS: the run's regions; default all)"""
import json
import os
import subprocess
import sys

from shapely.geometry import mapping, shape

from common import PIPELINE, load_config, log, write_json
from country_admin import CountryNames
from coverage import grow

MARGIN_KM = 5
SLICES = PIPELINE / "slices"


def wanted(leaf: str, cat: dict, run: set[str] | None) -> list[dict]:
    return [r for r in cat["regions"] if leaf in r["sources"] and (run is None or r["id"] in run)]


def extract_config(leaf: str, regions: list[dict], workdir) -> dict:
    """osmium extract --config: one output per region, its polygon as a GeoJSON file in workdir."""
    extracts = []
    for r in regions:
        km = load_config(r["id"])["coverage"]["buffer_km"] + MARGIN_KM
        poly = workdir / f"{r['id']}.geojson"
        write_json(poly, {"type": "FeatureCollection", "features": [
            {"type": "Feature", "properties": {}, "geometry": mapping(grow(shape(r["polygon"]), km))}]})
        extracts.append({"output": f"{r['id']}/{leaf}.osm.pbf", "polygon": {"file_name": str(poly), "file_type": "geojson"}})
    return {"directory": str(SLICES), "extracts": extracts}


def header_timestamp(path) -> str:
    return subprocess.run(["osmium", "fileinfo", "-g", "header.option.osmosis_replication_timestamp", str(path)],
                          capture_output=True, text=True, check=True).stdout.strip()


def main(leaves: list[str], delete: bool):
    cat = json.loads((PIPELINE / "regions" / "europe.json").read_text())
    run = set(os.environ["REGIONS"].split()) if os.environ.get("REGIONS") else None
    work = PIPELINE / "out" / "_slice"
    work.mkdir(parents=True, exist_ok=True)
    for leaf in leaves:
        regions = wanted(leaf, cat, run)
        if not regions:
            log(f"{leaf}: no region of this run needs it")
            continue
        url = cat["leaves"][leaf]
        src = PIPELINE / subprocess.run(["bash", "stages/fetch_leaf.sh", url], cwd=PIPELINE, capture_output=False,
                                        stdout=subprocess.PIPE, text=True, check=True).stdout.strip()
        for r in regions:
            (SLICES / r["id"]).mkdir(parents=True, exist_ok=True)
        cfg = work / f"{leaf}.json"
        write_json(cfg, extract_config(leaf, regions, work))
        subprocess.run(["osmium", "extract", "--config", str(cfg), "--strategy", "smart", "--overwrite", str(src)],
                       check=True)
        names = CountryNames()
        names.apply_file(str(src))
        meta = {"leaf": leaf, "url": url, "timestamp": header_timestamp(src), "countries": names.names}
        for r in regions:
            write_json(SLICES / r["id"] / f"{leaf}.json", meta)
        log(f"{leaf}: {len(regions)} slices ({', '.join(r['id'] for r in regions)})")
        if delete:
            for p in (src, src.with_name(src.name + ".md5")):
                p.unlink(missing_ok=True)


if __name__ == "__main__":
    args = sys.argv[1:]
    delete = "--delete" in args
    main([a for a in args if a != "--delete"], delete)
