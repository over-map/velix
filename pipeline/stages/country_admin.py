"""Writes out/<region>/country.osm.pbf: the region border re-tagged as its country (admin_level=2).

Valhalla's admin builder skips the real country boundary because the extract cuts it, and then loses the country's
default access rules. The pack ends exactly at the region border, so every edge in it lies in that one country:
the region polygon tagged as the country gives Valhalla the same answer without fetching the whole national boundary."""
import osmium

from common import load_config, log, out_dir


def main():
    cfg = load_config()
    out = out_dir(cfg)
    country = cfg["region"]["country"]
    src, dst = out / "region-rel.osm.pbf", out / "country.osm.pbf"
    if dst.exists():
        dst.unlink()
    writer = osmium.SimpleWriter(str(dst))
    for obj in osmium.FileProcessor(str(src)):
        if obj.is_relation() and obj.id == cfg["region"]["osm_relation"]:
            tags = {"type": "boundary", "boundary": "administrative", "admin_level": "2",
                    "name": country["name"], "ISO3166-1": country["iso"], "ISO3166-1:alpha2": country["iso"]}
            writer.add_relation(obj.replace(id=country["osm_relation"], tags=tags))
        elif obj.is_relation():
            continue
        else:
            writer.add(obj)
    writer.close()
    log(f"{dst.name}: {cfg['region']['name']} border as {country['name']} ({country['iso']})")


if __name__ == "__main__":
    main()
