"""The region index → packs.json, published as an asset of the fixed Release `pack-index` (runs on the host, stdlib only).

The app reads it to know which regions exist, where they are (so panning or searching into one offers its download)
and which release is the newest for each, instead of scanning the latest Releases (several regions overflow a page).
Usage: python3 stages/index.py out.json <tag> <manifest.json> [<tag> <manifest.json> …]"""
import json
import sys


def entry(tag: str, m: dict) -> dict:
    return {"id": m["pack"], "name": m["name"], "tag": tag, "version": m["version"], "built": m["built"],
            "bbox": m["bbox"], "polygon": m.get("polygon"),
            "coverage": m.get("coverage"), "download_bytes": m["download_bytes"], "unpacked_bytes": m["unpacked_bytes"],
            "manifest": f"https://github.com/over-map/velix/releases/download/{tag}/manifest.json"}


def build(pairs: list[tuple[str, dict]]) -> dict:
    regions = sorted((entry(t, m) for t, m in pairs), key=lambda e: e["name"])
    return {"schema": 1, "regions": regions}


if __name__ == "__main__":
    out, rest = sys.argv[1], sys.argv[2:]
    pairs = [(rest[i], json.load(open(rest[i + 1]))) for i in range(0, len(rest), 2)]
    with open(out, "w") as f:
        json.dump(build(pairs), f, separators=(",", ":"), ensure_ascii=False)
    print(f"[index] {len(pairs)} regions → {out}")
