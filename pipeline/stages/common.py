"""Shared helpers for the region-pack stages. Every stage runs inside the tools image with the repo at /work."""
import hashlib
import json
import os
import sys
from pathlib import Path

import yaml

ROOT = Path(os.environ.get("VELIX_ROOT", "/work"))
PIPELINE = ROOT / "pipeline"


def merge(base: dict, over: dict) -> dict:
    """`over` merged into `base`, key by key (dicts recursively; anything else replaced)."""
    out = dict(base)
    for k, v in over.items():
        out[k] = merge(out[k], v) if isinstance(v, dict) and isinstance(out.get(k), dict) else v
    return out


def catalogue_entry(region: str) -> dict | None:
    """The region's entry in the generated catalogue (regions/europe.json, stages/regions.py), with its source leaves'
    download URLs, or None."""
    path = PIPELINE / "regions" / "europe.json"
    if not path.exists():
        return None
    cat = json.loads(path.read_text())
    entry = next((r for r in cat["regions"] if r["id"] == region), None)
    return dict(entry, source_urls=[cat["leaves"][leaf] for leaf in entry["sources"]]) if entry else None


def load_config(region: str | None = None) -> dict:
    """config/_base.yml (what every region shares), then the region's catalogue entry (generated), then
    config/<region>.yml when one exists (hand-written: Italy's timetables, smoke checks, pinned borders)."""
    region = region or os.environ.get("REGION", "lombardy")
    with open(PIPELINE / "config" / "_base.yml") as f:
        cfg = yaml.safe_load(f)
    entry = catalogue_entry(region)
    if entry:
        cfg = merge(cfg, {"region": {"id": entry["id"], "name": entry["name"], "timezone": entry["timezone"],
                                     "country": {"iso": entry["country"]}},
                          "osm": {"sources": entry["source_urls"]}})
    hand = PIPELINE / "config" / f"{region}.yml"
    if hand.exists():
        with open(hand) as f:
            cfg = merge(cfg, yaml.safe_load(f))
    elif not entry:
        raise SystemExit(f"unknown region {region!r}: not in regions/europe.json and no config/{region}.yml")
    return cfg


def utm_epsg(lon: float, lat: float) -> int:
    """WGS 84 / UTM zone of a point (metres for buffers and lengths): Lisbon 32629, Milan 32632, Helsinki 32635."""
    return (32600 if lat >= 0 else 32700) + int((lon + 180) // 6) % 60 + 1


def out_dir(cfg: dict) -> Path:
    d = PIPELINE / "out" / cfg["region"]["id"]
    d.mkdir(parents=True, exist_ok=True)
    return d


def cache_dir() -> Path:
    d = PIPELINE / "cache"
    d.mkdir(parents=True, exist_ok=True)
    return d


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def write_json(path: Path, data) -> None:
    path.write_text(json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False) + "\n")


def log(msg: str) -> None:
    print(f"[{Path(sys.argv[0]).stem}] {msg}", flush=True)


COBBLE_SURFACES = {"sett", "cobblestone", "unhewn_cobblestone"}
CAR_FREE = {"footway", "pedestrian", "cycleway", "path", "bridleway"}


def cobble_class(tags) -> str | None:
    """How rough a cobbled way rides (Filippo, 19 Oct): None if not cobbled, else "smooth", "mild" or "rough".
    OSM smoothness decides where tagged (≈ 9 % of Lombardy's cobbles); otherwise cobbles on car-free paths are small
    and well laid (a garden path's porphyry), and on streets they are big and worn by traffic and trams (Ripamonti)."""
    if tags.get("surface") not in COBBLE_SURFACES:
        return None
    smooth = tags.get("smoothness")
    if smooth in {"excellent", "good"}:
        return "smooth"
    if smooth == "intermediate":
        return "mild"
    if smooth:
        return "rough"
    return "mild" if tags.get("highway") in CAR_FREE else "rough"
