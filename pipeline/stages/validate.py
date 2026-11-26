"""Stage 8: validate out/<region>/pack/manifest.json against the schema, sizes, checksums and the download budgets;
check routes.sqlite's mix shares."""
import json
import sqlite3
import sys

import jsonschema

from common import PIPELINE, load_config, log, out_dir, sha256


ROLES = {"routing_tiles", "hazards", "routes", "basemap", "overlays", "city"}


def main() -> int:
    cfg = load_config()
    pack = out_dir(cfg) / "pack"
    manifest = json.loads((pack / "manifest.json").read_text())
    schema = json.loads((PIPELINE / "schema" / "manifest.schema.json").read_text())
    errors = [e.message for e in jsonschema.Draft202012Validator(schema).iter_errors(manifest)]
    for f in manifest["files"]:
        p = pack / f["asset"]
        if not p.exists():
            errors.append(f"missing {f['asset']}")
            continue
        if p.stat().st_size != f["bytes"]:
            errors.append(f"{f['asset']}: size {p.stat().st_size} != {f['bytes']}")
        if sha256(p) != f["sha256"]:
            errors.append(f"{f['asset']}: sha256 mismatch")
    if manifest["download_bytes"] != sum(f["bytes"] for f in manifest["files"]):
        errors.append("download_bytes is not the sum of file sizes")
    errors += budget_errors(manifest)
    if {f["role"] for f in manifest["files"]} != ROLES:
        errors.append("pack must contain " + ", ".join(sorted(ROLES)))
    errors += check_routes(out_dir(cfg) / "routes.sqlite")
    for e in errors:
        log(f"FAIL {e}")
    if not errors:
        log(f"manifest OK · {manifest['pack']} {manifest['version']} · {manifest['download_bytes'] / 1e6:.1f} MB")
    return 1 if errors else 0


def parts(manifest: dict) -> dict:
    """The download in its two parts: the optional map (the basemap) and routing (every other file)."""
    map_bytes = sum(f["bytes"] for f in manifest["files"] if f["role"] == "basemap")
    return {"routing": sum(f["bytes"] for f in manifest["files"]) - map_bytes, "map": map_bytes}


def budget_errors(manifest: dict) -> list[str]:
    """Each part within its budget (24 Nov); a manifest without `map_budget_bytes` has one budget for the whole pack."""
    if "map_budget_bytes" not in manifest:
        total, budget = manifest["download_bytes"], manifest["budget_bytes"]
        return [f"over budget: {total / 1e6:.1f} MB > {budget / 1e6:.0f} MB"] if total > budget else []
    p = parts(manifest)
    return [f"{part} over budget: {p[part] / 1e6:.1f} MB > {budget / 1e6:.0f} MB"
            for part, budget in (("routing", manifest["budget_bytes"]), ("map", manifest["map_budget_bytes"]))
            if p[part] > budget]


def check_routes(path) -> list[str]:
    """routes.sqlite schema 2: the S7 mix shares are fractions that add up to at most the whole length."""
    if not path.exists():
        return [f"missing {path.name}"]
    db = sqlite3.connect(path)
    try:
        if db.execute("SELECT value FROM meta WHERE key = 'schema'").fetchone() != ("2",):
            return ["routes.sqlite: schema is not 2"]
        bad = db.execute("""SELECT count(*) FROM routes WHERE car_free_share < 0 OR quiet_share < 0 OR unpaved_share < 0
                            OR car_free_share + quiet_share + unpaved_share > 1.01""").fetchone()[0]
        return [f"routes.sqlite: {bad} routes with mix shares out of range"] if bad else []
    finally:
        db.close()


if __name__ == "__main__":
    sys.exit(main())
