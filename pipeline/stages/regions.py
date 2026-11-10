"""The region catalogue → regions/europe.json (+ regions/countries.geojson): every Velix pack in Europe, generated.

Filippo, 8–9 Nov 2026: packs for the EU, EFTA and the UK, each under the 320 MB budget, generated rather than written
by hand. Rules in regions/rules.yml:
- each Geofabrik leaf extract of a country in scope that fits (≤ group_mb of OSM data) is one region;
- a bigger leaf is split into its admin areas (the first admin level that covers it), measured with osmium, and
  neighbouring areas are grouped up to group_mb; an area over single_mb is split again at a deeper level;
- a tiny region (< tiny_mb) joins its smallest neighbour of the same country when the sum fits;
- today's Italian packs are pinned (ids, names, borders), so installed packs keep updating.
Each region lists its source leaves: every Geofabrik leaf its border + buffer_km touches, across national borders,
so the pipeline (stages/extract.sh) merges them and a trip just over the border plans.

Runs on GitHub (.github/workflows/regions.yml; the countries with big leaves are ≈ 23 GB, one at a time), about quarterly so ids stay stable.
Usage: python stages/regions.py <work dir> (downloads go there; outputs to pipeline/regions/)."""
import json
import os
import re
import shutil
import subprocess
import sys
import time
import unicodedata
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

import yaml
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[2]
REGIONS = ROOT / "pipeline" / "regions"
INDEX_URL = "https://download.geofabrik.de/index-v1.json"
UA = {"User-Agent": "Velix region catalogue (https://github.com/over-map/velix)"}
MB = 1_000_000
SPLITS = []   # (leaf, admin level, areas, % of the leaf's bytes they hold): in the report, to spot a lost area


@dataclass
class Unit:
    """A building block of a region: a Geofabrik leaf, or an admin area inside a big leaf."""
    key: str
    name: str
    country: str          # ISO 3166-1 alpha-2 (after join_country)
    size: int             # OSM extract bytes
    geom: object = None   # shapely geometry (lon/lat)
    pinned: dict | None = None


@dataclass
class Region:
    members: list = field(default_factory=list)

    @property
    def size(self):
        return sum(u.size for u in self.members)

    @property
    def lead(self):
        return max(self.members, key=lambda u: (u.size, u.key))


# ---- pure rules (unit-tested) ---------------------------------------------------------------------------------------

def slug(name: str) -> str:
    s = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", "-", s).strip("-")


def touches(a: Unit, b: Unit) -> bool:
    return a.geom.buffer(0.002).intersects(b.geom)


def group(units: list, limit: int) -> list:
    """Neighbouring units grouped up to `limit` bytes, deterministically: the largest free unit starts a group, which
    takes the free neighbour nearest its centre (compact groups: the largest-first rule made "Bern" reach Ticino) that
    still fits, until none does. Pinned units stay alone."""
    free = sorted(units, key=lambda u: (-u.size, u.key))
    taken, out = set(), []
    for u in free:
        if u.key in taken:
            continue
        taken.add(u.key)
        g = Region([u])
        if not u.pinned:
            while True:
                fits = [v for v in free if v.key not in taken and not v.pinned and g.size + v.size <= limit
                        and any(touches(v, m) for m in g.members)]
                if not fits:
                    break
                centre = unary_union([m.geom for m in g.members]).centroid
                v = min(fits, key=lambda v: (v.geom.centroid.distance(centre), v.key))
                taken.add(v.key)
                g.members.append(v)
        out.append(g)
    return out


def merge_tiny(regions: list, tiny: int, limit: int) -> list:
    """A region under `tiny` bytes joins its smallest neighbour of the same country when the sum stays ≤ `limit`
    (never a pinned one); the smallest go first."""
    regions = list(regions)
    for r in sorted(regions, key=lambda r: (r.size, r.lead.key)):
        if r not in regions or r.size >= tiny or any(u.pinned for u in r.members):
            continue
        hosts = [h for h in regions if h is not r and h.lead.country == r.lead.country and not any(u.pinned for u in h.members)
                 and h.size + r.size <= limit and any(touches(a, b) for a in h.members for b in r.members)]
        if hosts:
            host = min(hosts, key=lambda h: (h.size, h.lead.key))
            host.members.extend(r.members)
            regions.remove(r)
    return regions


def name_of(region: Region, names: dict) -> str:
    lead = region.lead
    if lead.pinned:
        return lead.pinned["name"]
    base = names.get(lead.name, lead.name)
    split_parts = [u for u in region.members if "/" in u.key]    # admin areas of a split leaf
    return f"{base} and around" if len(split_parts) > 1 else base


def assign_ids(regions: list, names: dict) -> list:
    """(id, name, region): slugs of the names; a name used in two countries gets the country code."""
    named = [(name_of(r, names), r) for r in regions]
    counts = {}
    for n, r in named:
        counts.setdefault(slug(n), set()).add(r.lead.country)
    out = []
    for n, r in named:
        rid = r.lead.pinned["id"] if r.lead.pinned else slug(n)
        if not r.lead.pinned and len(counts[slug(n)]) > 1:
            rid = f"{rid}-{r.lead.country.lower()}"
        out.append((rid, n, r))
    ids = [i for i, _, _ in out]
    dupes = {i for i in ids if ids.count(i) > 1}
    if dupes:
        raise SystemExit(f"duplicate region ids: {sorted(dupes)}")
    return out


def pick_level(candidates: dict, total: int) -> int | None:
    """The first admin level whose areas (≥ 2) hold ≥ 80 % of the leaf's bytes: {level: [(name, bytes)]}."""
    for level in sorted(candidates):
        areas = candidates[level]
        if len(areas) >= 2 and sum(b for _, b in areas) >= 0.8 * total:
            return level
    return None


# ---- data (GitHub run) ---------------------------------------------------------------------------------------------

def fetch_json(url: str, dst: Path):
    if not dst.exists():
        with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=300) as r:
            dst.write_bytes(r.read())
    return json.loads(dst.read_text())


def head_size(url: str) -> int:
    for attempt in range(8):
        r = subprocess.run(["curl", "-sIL", "-m", "60", "-A", UA["User-Agent"], url], capture_output=True, text=True)
        sizes = re.findall(r"(?im)^content-length:\s*(\d+)", r.stdout)
        if r.returncode == 0 and sizes:
            return int(sizes[-1])
        time.sleep(5 * (attempt + 1))
    raise SystemExit(f"no size for {url}")


def download(url: str, dst: Path) -> Path:
    """Downloads with resume: Geofabrik sometimes drops a long transfer (curl 18), so curl runs again from where it
    stopped, up to 20 times."""
    if not dst.exists():
        part = Path(f"{dst}.part")
        for attempt in range(20):
            r = subprocess.run(["curl", "-fsSL", "-C", "-", "-A", UA["User-Agent"], "-o", str(part), url])
            if r.returncode == 0:
                break
            print(f"[regions] {url}: curl {r.returncode}, resuming ({attempt + 1})", flush=True)
            time.sleep(min(60, 5 * (attempt + 1)))
        else:
            raise SystemExit(f"download failed: {url}")
        part.rename(dst)
    return dst


def admin_areas(pbf: Path, work: Path, level: int, within) -> list:
    """(name, geometry, osm id) of the admin areas at `level` whose representative point lies in `within`."""
    from shapely.geometry import shape
    adm = work / f"{pbf.stem}.adm{level}.osm.pbf"
    seq = work / f"{pbf.stem}.adm{level}.geojsonseq"
    if not seq.exists():
        subprocess.run(["osmium", "tags-filter", str(pbf), f"r/admin_level={level}", "-o", str(adm), "--overwrite"], check=True)
        subprocess.run(["osmium", "export", str(adm), "--geometry-types=polygon", "-f", "geojsonseq", "-o", str(seq),
                        "--overwrite"], check=True)
    out = []
    for line in seq.read_text().splitlines():
        line = line.strip("\x1e \t")
        if not line:
            continue
        f = json.loads(line)
        p = f.get("properties", {})
        if p.get("boundary") != "administrative" or str(p.get("admin_level")) != str(level) or not p.get("name"):
            continue
        g = shape(f["geometry"])
        if not g.is_valid:
            g = g.buffer(0)               # a self-touching ring dropped Campania (Naples) from the Italian split
        if g.area < 1e-4:                 # ≈ 1 km²: islets mapped as regions (Puglia's)
            continue
        if within.contains(g.representative_point()):
            out.append((p.get("name:en") or p["name"], p["name"], g, f.get("id")))
    return out


def measure(pbf: Path, work: Path, areas: list, level: int) -> list:
    """Bytes of each area's extract from `pbf` (one osmium pass, strategy simple), kept in <stem>.areas<level>/."""
    from shapely.geometry import mapping
    d = work / f"{pbf.stem}.areas{level}"
    d.mkdir(exist_ok=True)
    # Four areas per pass: osmium keeps an id set per extract, and 26 Swiss cantons at once took more than 11 GB.
    for start in range(0, len(areas), 4):
        cfg = {"directory": str(d), "extracts": []}
        for i in range(start, min(start + 4, len(areas))):
            poly = d / f"{i}.geojson"
            poly.write_text(json.dumps({"type": "Feature", "geometry": mapping(areas[i][2]), "properties": {}}))
            cfg["extracts"].append({"output": f"{i}.osm.pbf", "polygon": {"file_name": str(poly), "file_type": "geojson"}})
        (d / "config.json").write_text(json.dumps(cfg))
        subprocess.run(["osmium", "extract", "-c", str(d / "config.json"), "-s", "simple", "--overwrite", str(pbf)], check=True)
    return [(d / f"{i}.osm.pbf").stat().st_size for i in range(len(areas))]


def split(pbf: Path, work: Path, leaf_key: str, country: str, geom, size: int, rules: dict, depth: int = 0) -> list:
    """A big leaf (or area) → Units of admin areas, each ≤ single_mb (deeper levels where needed)."""
    pinned = rules.get("pinned", {})
    levels = [lv for lv in rules["levels"] if lv > depth]
    candidates, found = {}, {}
    for level in levels:
        areas = admin_areas(pbf, work, level, geom)
        if len(areas) < 2:
            continue
        sizes = measure(pbf, work, areas, level)
        candidates[level] = [(a[0], s) for a, s in zip(areas, sizes)]
        found[level] = list(zip(areas, sizes))
        if pick_level({level: candidates[level]}, size) == level:
            break
    level = pick_level(candidates, size)
    if level is None:
        raise SystemExit(f"{leaf_key}: no admin level splits it ({size / MB:.0f} MB)")
    held = sum(b for _, b in candidates[level])
    SPLITS.append((leaf_key, level, len(candidates[level]), round(100 * held / size)))
    units = []
    for idx, ((en, local, g, _), s) in enumerate(found[level]):
        key = f"{leaf_key}/{slug(local)}"
        pin = pinned.get(local)
        if s > rules["single_mb"] * MB and not pin:
            sub = work / f"{slug(local)}.osm.pbf"
            (work / f"{pbf.stem}.areas{level}" / f"{idx}.osm.pbf").replace(sub)
            units += split(sub, work, key, country, g, s, rules, level)
        else:
            units.append(Unit(key, en, country, s, g, pin))
    return units


def main(work: Path) -> int:
    from shapely.geometry import mapping, shape
    from shapely.ops import unary_union, transform
    from pyproj import Transformer
    from timezonefinder import TimezoneFinder

    work.mkdir(parents=True, exist_ok=True)
    rules = yaml.safe_load((REGIONS / "rules.yml").read_text())
    index = fetch_json(INDEX_URL, work / "index-v1.json")["features"]
    props = {f["properties"]["id"]: f["properties"] for f in index}
    geoms = {f["properties"]["id"]: shape(f["geometry"]) for f in index if f["geometry"]}
    kids = {}
    for p in props.values():
        kids.setdefault(p.get("parent"), []).append(p["id"])
    excluded = set(rules["exclude"])

    def leaves(i):
        k = [c for c in kids.get(i, []) if c not in excluded]
        return [x for c in k for x in leaves(c)] if k else [i]

    if only := os.environ.get("VELIX_REGION_COUNTRIES"):      # a trial on a few countries (local checks)
        rules["countries"] = only.split(",")
    iso = {c: props[c]["iso3166-1:alpha2"][0] for c in rules["countries"]}
    join = rules.get("join_country", {})
    units = []
    for c in rules["countries"]:
        country = join.get(iso[c], iso[c])
        sized = []
        for leaf in leaves(c):
            sized.append((leaf, head_size(props[leaf]["urls"]["pbf"])))
            print(f"[regions] {leaf}: {sized[-1][1] / MB:.0f} MB", flush=True)
        big = [(leaf, size) for leaf, size in sized if size > rules["group_mb"] * MB]
        if big:
            # Admin areas come from the whole country's extract: a leaf cuts the boundaries that cross it (Emilia-Romagna
            # is incomplete in Geofabrik's nord-est), and osmium can't build an area from an incomplete relation.
            pbf = download(props[c]["urls"]["pbf"], work / f"{c}.osm.pbf")
            for leaf, size in big:
                units += split(pbf, work, leaf, country, geoms[leaf], size, rules)
            for f in work.glob("*"):        # disk: a country and its areas are up to ≈ 10 GB
                if f.is_dir():
                    shutil.rmtree(f)
                elif f.suffix != ".json":
                    f.unlink()
        units += [Unit(leaf, props[leaf]["name"], country, size, geoms[leaf]) for leaf, size in sized
                  if size <= rules["group_mb"] * MB]

    regions = []
    for country in sorted({u.country for u in units}):
        cu = [u for u in units if u.country == country]
        regions += group(cu, rules["group_mb"] * MB)
    regions = merge_tiny(regions, rules["tiny_mb"] * MB, rules["group_mb"] * MB)

    # Source leaves: every leaf in Europe (scope or not) that the region's border + buffer touches.
    all_leaves = [l for l in leaves("europe") if l in geoms]
    tf = TimezoneFinder()
    out, countries_seen = [], set()
    for rid, name, r in sorted(assign_ids(regions, rules.get("names", {})), key=lambda t: t[0]):
        poly = unary_union([u.geom for u in r.members]).buffer(0)
        c = poly.representative_point()
        zone = 32600 + int((c.x + 180) // 6) + 1 if c.y >= 0 else 32700 + int((c.x + 180) // 6) + 1
        to_m = Transformer.from_crs(4326, zone, always_xy=True).transform
        to_ll = Transformer.from_crs(zone, 4326, always_xy=True).transform
        cov = transform(to_ll, transform(to_m, poly).buffer(rules["buffer_km"] * 1000, resolution=4))
        sources = sorted(l for l in all_leaves if geoms[l].intersects(cov))
        simple = transform(to_ll, transform(to_m, poly).simplify(200))
        countries_seen.add(r.lead.country)
        out.append({"id": rid, "name": name, "country": r.lead.country, "timezone": tf.timezone_at(lng=c.x, lat=c.y),
                    "forecast_mb": round(r.size / MB * rules["forecast_factor"]), "members": [u.key for u in r.members],
                    "sources": sources, "polygon": json.loads(json.dumps(mapping(simple)), parse_float=lambda f: round(float(f), 4))})
    catalogue = {"schema": 1, "generated_from": INDEX_URL, "budget_mb": 320,
                 "leaves": {l: props[l]["urls"]["pbf"] for l in sorted({s for r in out for s in r["sources"]})},
                 "regions": out}
    (REGIONS / "europe.json").write_text(json.dumps(catalogue, ensure_ascii=False, indent=1) + "\n")

    # Country borders for stages/country_admin.py: every European country Geofabrik knows, simplified.
    feats = []
    for cid, p in sorted(props.items()):
        if p.get("parent") == "europe" and p.get("iso3166-1:alpha2") and cid in geoms:
            g = geoms[cid].simplify(0.002)
            feats.append({"type": "Feature", "properties": {"iso": p["iso3166-1:alpha2"][0], "name": p["name"]},
                          "geometry": json.loads(json.dumps(mapping(g)), parse_float=lambda f: round(float(f), 4))})
    (REGIONS / "countries.geojson").write_text(json.dumps({"type": "FeatureCollection", "features": feats}) + "\n")

    over = [r for r in out if r["forecast_mb"] > catalogue["budget_mb"]]
    per = {}
    for r in out:
        per[r["country"]] = per.get(r["country"], 0) + 1
    report = [f"## Region catalogue: {len(out)} regions\n", "| Country | Regions |", "|---|---|"]
    report += [f"| {k} | {v} |" for k, v in sorted(per.items())]
    sizes = sorted(out, key=lambda r: r["forecast_mb"])
    report += ["", f"Smallest: {sizes[0]['name']} {sizes[0]['forecast_mb']} MB · largest: {sizes[-1]['name']} "
               f"{sizes[-1]['forecast_mb']} MB (forecast pack size)", ""]
    report += ["| Region | Country | Forecast MB | Sources |", "|---|---|---|---|"]
    report += [f"| {r['name']} | {r['country']} | {r['forecast_mb']} | {len(r['sources'])} |" for r in out]
    report += ["", "| Split | Admin level | Areas | Bytes held |", "|---|---|---|---|"]
    report += [f"| {k} | {lv} | {n} | {pct} % |" for k, lv, n, pct in SPLITS]
    if over:
        report += ["", f"**Over budget:** {', '.join(r['id'] for r in over)}"]
    (work / "report.md").write_text("\n".join(report) + "\n")
    print("\n".join(report[:6]), flush=True)
    return 1 if over else 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/tmp/velix-regions")))
