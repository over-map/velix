"""What a Region pack run builds (runs on the host, stdlib only): the regions, and the Geofabrik leaves they need
grouped by country, so the slice jobs download each leaf once (M11 PR 3).

Regions: "all" (the monthly run: every catalogue region, 219), "sample" (pull requests: three that cover the pipeline's
cases), or a comma-separated list of ids. Prints GitHub Actions outputs: regions=<JSON list>, groups=<JSON list of
{"group", "leaves"}>. Regions with a hand-written config but no catalogue entry download their own `osm.url`.
Usage: python3 stages/plan_run.py <all|sample|id,id…>"""
import json
import sys
from pathlib import Path

PIPELINE = Path(__file__).resolve().parents[1]
# Lombardy: hand config, timetables, cross-border coverage, golden tests. Luxembourg: smallest, four countries' rules.
# Paris and around: a split leaf, a group, a big city.
SAMPLE = ["lombardy", "luxembourg", "paris-and-around"]
MAX_JOBS = 256            # GitHub's matrix limit


def catalogue() -> dict:
    return json.loads((PIPELINE / "regions" / "europe.json").read_text())


def group_of(url: str) -> str:
    """The country folder of a Geofabrik URL: …/europe/france/alsace-latest.osm.pbf → france; …/europe/malta-… → malta."""
    path = url.split("/europe/", 1)[1]
    return path.split("/", 1)[0].removesuffix("-latest.osm.pbf")


def regions(choice: str, cat: dict) -> list[str]:
    ids = [r["id"] for r in cat["regions"]]
    if choice == "all":
        return ids
    if choice == "sample":
        return SAMPLE
    picked = [x.strip() for x in choice.split(",") if x.strip()]
    unknown = [x for x in picked if x not in ids]
    if unknown:
        raise SystemExit(f"not in regions/europe.json: {', '.join(unknown)}")
    return picked


def groups(picked: list[str], cat: dict) -> list[dict]:
    by_id = {r["id"]: r for r in cat["regions"]}
    leaves = sorted({leaf for rid in picked for leaf in by_id[rid]["sources"]})
    out: dict[str, list[str]] = {}
    for leaf in leaves:
        out.setdefault(group_of(cat["leaves"][leaf]), []).append(leaf)
    return [{"group": g, "leaves": ls} for g, ls in sorted(out.items())]


def plan(choice: str, cat: dict | None = None) -> dict:
    cat = cat or catalogue()
    picked = regions(choice, cat)
    if len(picked) > MAX_JOBS:
        raise SystemExit(f"{len(picked)} regions: more than GitHub's {MAX_JOBS} jobs per matrix; split the run")
    return {"regions": picked, "groups": groups(picked, cat)}


if __name__ == "__main__":
    p = plan(sys.argv[1] if len(sys.argv) > 1 else "sample")
    print(f"regions={json.dumps(p['regions'])}")
    print(f"groups={json.dumps(p['groups'])}")
    print(f"[plan] {len(p['regions'])} regions, {sum(len(g['leaves']) for g in p['groups'])} leaves "
          f"in {len(p['groups'])} groups", file=sys.stderr)
