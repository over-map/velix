"""Release tags and pruning for the publish jobs (runs on the host, stdlib only).

`tags`: the tag each new pack gets, `pack-<id>-<version>`, then `.2`, `.3`… when that month already has one; the
existing tag when that release already holds these exact manifest bytes (a re-run).
`prune`: pack releases older than two months that the new index doesn't point to (DECISIONS 2026-11-14).
Both read the full release list (`gh api --paginate repos/<repo>/releases`, a JSON array per page, concatenated).
Usage: python3 stages/releases.py tags <releases.json> <manifest.json>…   → lines "<id> <tag>"
       python3 stages/releases.py prune <releases.json> <packs.json> [today] → one tag per line"""
import hashlib
import json
import sys
import urllib.request
from datetime import date, timedelta

KEEP_DAYS = 61            # "about two months"
FIXED = {"pack-index"}    # releases that are not packs


def load_pages(text: str) -> list[dict]:
    """`gh api --paginate` prints one JSON array per page back to back: `[…][…]`."""
    dec, out, i = json.JSONDecoder(), [], 0
    text = text.strip()
    while i < len(text):
        page, i = dec.raw_decode(text, i)
        out += page
        while i < len(text) and text[i].isspace():
            i += 1
    return out


def next_tag(region: str, version: str, existing: set[str]) -> str:
    tag, n = f"pack-{region}-{version}", 1
    while tag in existing:
        n += 1
        tag = f"pack-{region}-{version}.{n}"
    return tag


DOWNLOAD = "https://github.com/over-map/velix/releases/download/"


def fetch_manifest(tag: str) -> bytes | None:
    try:
        with urllib.request.urlopen(f"{DOWNLOAD}{tag}/manifest.json", timeout=30) as r:
            return r.read()
    except OSError:
        return None


def pick_tag(region: str, version: str, manifest: bytes, existing: set[str], fetch=fetch_manifest) -> str:
    """The release tag for this pack: an existing release of the same month whose manifest is these exact bytes (a
    re-run of the workflow: publish then only finishes its uploads), else the next free one. Before this, every
    "Re-run failed jobs" republished every region as .2, .3… (538 releases for 186 regions, 15–17 Nov 2026)."""
    same_month = sorted((t for t in existing if t == f"pack-{region}-{version}" or t.startswith(f"pack-{region}-{version}.")),
                        key=lambda t: int(t.rsplit(".", 1)[1]) if t.count(".") > 1 else 1, reverse=True)
    digest = hashlib.sha256(manifest).hexdigest()
    for tag in same_month:
        old = fetch(tag)
        if old is not None and hashlib.sha256(old).hexdigest() == digest:
            return tag
    return next_tag(region, version, existing)


def prune(releases: list[dict], index: dict, today: date) -> list[str]:
    keep = {r["tag"] for r in index["regions"]} | FIXED
    cutoff = today - timedelta(days=KEEP_DAYS)
    return sorted(r["tag_name"] for r in releases
                  if r["tag_name"].startswith("pack-") and r["tag_name"] not in keep
                  and date.fromisoformat(r["created_at"][:10]) < cutoff)


if __name__ == "__main__":
    cmd, releases = sys.argv[1], load_pages(open(sys.argv[2]).read())
    if cmd == "tags":
        existing = {r["tag_name"] for r in releases}
        for path in sys.argv[3:]:
            raw = open(path, "rb").read()
            m = json.loads(raw)
            tag = pick_tag(m["pack"], m["version"], raw, existing)
            existing.add(tag)
            print(m["pack"], tag)
    elif cmd == "prune":
        today = date.fromisoformat(sys.argv[4]) if len(sys.argv) > 4 else date.today()
        print("\n".join(prune(releases, json.load(open(sys.argv[3])), today)))
    else:
        raise SystemExit(f"unknown command {cmd!r}")
