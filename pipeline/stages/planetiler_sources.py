"""Stage 8a: planetiler's side sources in cache/planetiler/: OSM water polygons, Natural Earth, lake centerlines.

Each comes from the cache, else its own server, else Velix's mirror (Release `pipeline-sources`, refreshed from a good
download). The sources change slowly: a copy up to 35 days old is used without asking the server. osmdata.openstreetmap.de
was down on 9–10 Nov 2026 and planetiler's own --download failed every region."""
import subprocess
import time
from pathlib import Path

from common import cache_dir, log

MIRROR = "https://github.com/over-map/velix/releases/download/pipeline-sources/"
SOURCES = {
    "water-polygons-split-3857.zip": "https://osmdata.openstreetmap.de/download/water-polygons-split-3857.zip",
    "natural_earth_vector.sqlite.zip": "https://naciscdn.org/naturalearth/packages/natural_earth_vector.sqlite.zip",
    "lake_centerline.shp.zip": "https://github.com/acalcutt/osm-lakelines/releases/download/v12/lake_centerline.shp.zip",
}
MAX_AGE_DAYS = 35


def get(url: str, dst: Path) -> bool:
    part = dst.with_suffix(dst.suffix + ".part")
    for attempt in range(3):
        if subprocess.run(["curl", "-fsSL", "--connect-timeout", "30", "-C", "-", "-o", str(part), url]).returncode == 0:
            part.rename(dst)
            return True
        time.sleep(10 * (attempt + 1))
    part.unlink(missing_ok=True)
    return False


def main():
    d = cache_dir() / "planetiler"
    d.mkdir(exist_ok=True)
    for name, url in SOURCES.items():
        dst = d / name
        if dst.exists() and time.time() - dst.stat().st_mtime < MAX_AGE_DAYS * 86400:
            continue
        if get(url, dst):
            log(f"{name}: from {url}")
        elif get(MIRROR + name, dst):
            log(f"{name}: {url} failed, from the mirror")
        elif dst.exists():
            log(f"{name}: both sources failed, keeping the cached copy")
        else:
            raise SystemExit(f"{name}: no source answered and no cached copy")


if __name__ == "__main__":
    main()
