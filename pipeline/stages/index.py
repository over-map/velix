"""The region index → packs.json (schema 2), published with its signature on the fixed Release `pack-index` (runs on
the host, stdlib only).

The app reads it to know which regions exist, where they are (so panning or searching into one offers its download)
and which release is the newest for each. Regions this run didn't rebuild keep their entry from the previous index, so
the job never lists releases (GitHub's list stopped at 200 before M11), unless the catalogue no longer has them (a
regrouped country: the old region would overlap its new ones). Kept small (≈ 330 KB for 219 regions): the
outline is the manifest's `outline`, the coverage polygon stays in the manifest.
Usage: python3 stages/index.py out.json [--previous packs.json] [--catalogue regions/europe.json] <tag> <manifest.json> [<tag> <manifest.json> …]"""
import json
import sys

SCHEMA = 2
# Where the release assets are, in the order the app tries them: `<mirror><tag>/<asset>`. A second free host can be
# added here without an app update (DECISIONS 2026-11-09).
MIRRORS = ["https://github.com/over-map/velix/releases/download/"]


def entry(tag: str, m: dict) -> dict:
    return {"id": m["pack"], "name": m["name"], "country": m.get("country"), "tag": tag, "version": m["version"],
            "built": m["built"], "bbox": m["bbox"], "polygon": m.get("outline") or m.get("polygon"),
            "download_bytes": m["download_bytes"], "unpacked_bytes": m["unpacked_bytes"],
            # The optional offline map's share of the download (24 Nov): the app offers routing only by default.
            "map_bytes": sum(f["bytes"] for f in m.get("files", []) if f["role"] == "basemap"),
            # Read by app builds before schema 2.
            "manifest": f"{MIRRORS[0]}{tag}/manifest.json"}


def carried(e: dict) -> dict:
    """An entry of the previous index, in this schema (schema 1 had the coverage polygon)."""
    keep = ("id", "name", "country", "tag", "version", "built", "bbox", "polygon", "download_bytes", "unpacked_bytes")
    extra = {"map_bytes": e["map_bytes"]} if "map_bytes" in e else {}
    return {**{k: e.get(k) for k in keep}, **extra, "manifest": f"{MIRRORS[0]}{e['tag']}/manifest.json"}


def build(pairs: list[tuple[str, dict]], previous: dict | None = None, catalogue: set | None = None) -> dict:
    regions = {e["id"]: carried(e) for e in (previous or {}).get("regions", [])
               if catalogue is None or e["id"] in catalogue}
    regions.update({e["id"]: e for e in (entry(t, m) for t, m in pairs)})
    return {"schema": SCHEMA, "mirrors": MIRRORS, "regions": sorted(regions.values(), key=lambda e: e["name"])}


def dumps(index: dict) -> str:
    return json.dumps(index, separators=(",", ":"), ensure_ascii=False)


if __name__ == "__main__":
    out, rest = sys.argv[1], sys.argv[2:]
    previous = None
    if rest[:1] == ["--previous"]:
        try:
            previous = json.load(open(rest[1]))
        except (OSError, ValueError):
            print(f"[index] no previous index at {rest[1]}")
        rest = rest[2:]
    catalogue = None
    if rest[:1] == ["--catalogue"]:
        catalogue = {r["id"] for r in json.load(open(rest[1]))["regions"]}
        rest = rest[2:]
    pairs = [(rest[i], json.load(open(rest[i + 1]))) for i in range(0, len(rest), 2)]
    index = build(pairs, previous, catalogue)
    with open(out, "w") as f:
        f.write(dumps(index))
    kept = len(index["regions"]) - len(pairs)
    dropped = sorted({e["id"] for e in (previous or {}).get("regions", [])} - {e["id"] for e in index["regions"]})
    print(f"[index] {len(pairs)} rebuilt + {kept} kept → {out}" + (f"; dropped (not in the catalogue): {', '.join(dropped)}" if dropped else ""))
