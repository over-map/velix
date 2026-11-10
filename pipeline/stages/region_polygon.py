"""Stage 1a: out/<region>/region.geojson from the catalogue (regions/europe.json) for a region without an OSM relation."""
from common import catalogue_entry, load_config, log, out_dir, write_json

cfg = load_config()
entry = catalogue_entry(cfg["region"]["id"])
if not entry:
    raise SystemExit(f"{cfg['region']['id']}: no osm_relation and no catalogue entry")
write_json(out_dir(cfg) / "region.geojson", {"type": "FeatureCollection", "features": [
    {"type": "Feature", "properties": {"name": entry["name"], "members": entry["members"]}, "geometry": entry["polygon"]}]})
log(f"region.geojson from the catalogue ({len(entry['members'])} areas)")
