"""Stage 2b: routing copy of the extract → out/<region>/routing.osm.pbf (input of the Valhalla tile build).

Valhalla's parser files surface=sett as plain `paved` (like asphalt) and cobblestone as `paved_rough`, and its
bicycle costing only penalises surfaces from `dirt` (hybrid) / `compacted` (road bike) up. So cobbled ways are
retagged surface=dirt (original kept in velix:surface): Valhalla then slows them down for every bike, penalises them
by `avoid_bad_surfaces` (which Velix sets from the "No cobbles" rule), and road bikes avoid them. The hazard sidecar
still knows them as cobbles, so the comfort mix and the paved-only rule are unaffected."""
import osmium

from common import load_config, log, out_dir

COBBLES = {"sett", "cobblestone", "unhewn_cobblestone"}


def main():
    cfg = load_config()
    out = out_dir(cfg)
    src, dst = out / "region.osm.pbf", out / "routing.osm.pbf"
    if dst.exists():
        dst.unlink()
    writer = osmium.SimpleWriter(str(dst))
    changed = 0
    for obj in osmium.FileProcessor(str(src)):
        if obj.is_way() and obj.tags.get("surface") in COBBLES and "highway" in obj.tags:
            tags = dict(obj.tags)
            tags["velix:surface"] = tags["surface"]
            tags["surface"] = "dirt"
            writer.add_way(obj.replace(tags=tags))
            changed += 1
        else:
            writer.add(obj)
    writer.close()
    log(f"{dst.name}: {changed} cobbled ways retagged surface=dirt for routing")


if __name__ == "__main__":
    main()
