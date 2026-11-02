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


def load_config(region: str | None = None) -> dict:
    """config/<region>.yml over config/_base.yml (what every region shares)."""
    region = region or os.environ.get("REGION", "lombardy")
    with open(PIPELINE / "config" / "_base.yml") as f:
        base = yaml.safe_load(f)
    with open(PIPELINE / "config" / f"{region}.yml") as f:
        return merge(base, yaml.safe_load(f))


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
