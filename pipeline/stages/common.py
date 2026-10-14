"""Shared helpers for the region-pack stages. Every stage runs inside the tools image with the repo at /work."""
import hashlib
import json
import os
import sys
from pathlib import Path

import yaml

ROOT = Path(os.environ.get("VELIX_ROOT", "/work"))
PIPELINE = ROOT / "pipeline"


def load_config(region: str | None = None) -> dict:
    region = region or os.environ.get("REGION", "lombardy")
    with open(PIPELINE / "config" / f"{region}.yml") as f:
        return yaml.safe_load(f)


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
