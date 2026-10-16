"""After planetiler: record the basemap's data sources (manifest sources[]) and per-layer sizes (counts)."""
import collections
import datetime as dt
import gzip

from common import load_config, log, out_dir, write_json

# Planetiler's OpenMapTiles inputs besides the OSM extract (downloaded with --download).
SOURCES = [
    {"id": "openmaptiles", "name": "OpenMapTiles schema (planetiler-openmaptiles)",
     "url": "https://github.com/openmaptiles/openmaptiles", "licence": "CC-BY-4.0 (schema), BSD-3-Clause (code)",
     "attribution": "© OpenMapTiles"},
    {"id": "water_polygons", "name": "OSM water polygons (osmdata.openstreetmap.de)",
     "url": "https://osmdata.openstreetmap.de/download/water-polygons-split-3857.zip", "licence": "ODbL-1.0",
     "attribution": "© OpenStreetMap contributors"},
    {"id": "natural_earth", "name": "Natural Earth vector", "url": "https://naciscdn.org/naturalearth/packages/natural_earth_vector.sqlite.zip",
     "licence": "Public domain", "attribution": "Made with Natural Earth"},
    {"id": "lake_centerlines", "name": "OSM lake centerlines (osm-lakelines)",
     "url": "https://github.com/acalcutt/osm-lakelines", "licence": "ODbL-1.0", "attribution": "© OpenStreetMap contributors"},
]


def main():
    cfg = load_config()
    out = out_dir(cfg)
    today = dt.date.today().isoformat()
    for s in SOURCES:
        write_json(out / "sources" / f"{s['id']}.json", {**s, "date": today})
    stats = out / "basemap.pmtiles.layerstats.tsv.gz"
    by_layer = collections.Counter()
    tiles = 0
    with gzip.open(stats, "rt") as f:
        header = f.readline().rstrip("\n").split("\t")
        seen = set()
        for line in f:
            r = dict(zip(header, line.rstrip("\n").split("\t")))
            by_layer[r["layer"]] += int(r["layer_bytes"])
            seen.add((r["z"], r["x"], r["y"]))
        tiles = len(seen)
    stats.unlink()
    counts = {"bytes": (out / "basemap.pmtiles").stat().st_size, "tiles": tiles,
              "layer_mb": {k: round(v / 1e6, 1) for k, v in by_layer.most_common()}}
    write_json(out / "basemap.counts.json", counts)
    log(f"basemap.pmtiles {counts['bytes'] / 1e6:.0f} MB raw, {tiles} tiles")


if __name__ == "__main__":
    main()
