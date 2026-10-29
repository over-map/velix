"""Stage 8: validate out/<region>/pack/manifest.json against the schema, sizes, checksums and the download budget;
check routes.sqlite's mix shares."""
import json
import sqlite3
import sys

import jsonschema

from common import PIPELINE, load_config, log, out_dir, sha256


ROLES = {"routing_tiles", "hazards", "routes", "transit", "basemap", "overlays", "city"}


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
    if manifest["download_bytes"] > manifest["budget_bytes"]:
        errors.append(f"over budget: {manifest['download_bytes'] / 1e6:.1f} MB > {manifest['budget_bytes'] / 1e6:.0f} MB")
    if {f["role"] for f in manifest["files"]} != ROLES:
        errors.append("pack must contain " + ", ".join(sorted(ROLES)))
    errors += check_routes(out_dir(cfg) / "routes.sqlite")
    for e in errors:
        log(f"FAIL {e}")
    if not errors:
        log(f"manifest OK · {manifest['pack']} {manifest['version']} · {manifest['download_bytes'] / 1e6:.1f} MB")
    return 1 if errors else 0


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
