# Region pack pipeline

Builds the Velix offline region pack (Lombardy) from open data. It runs in Docker, so local and CI builds match.

```bash
make -C pipeline pack            # every stage: extract → elevation → tiles → hazards → routes → transit → package → validate → smoke
make -C pipeline hazards         # one stage at a time (stages read the previous stages' outputs in pipeline/out/<region>/)
make -C pipeline clean           # remove pipeline/out/<region>/ (downloads stay in pipeline/cache/)
```

Needs Docker (Colima works: `brew install colima && colima start --cpu 6 --memory 12`) and `python3` on the host for the Makefile. A full build takes about 15 minutes on an M1 Pro, plus downloads (≈ 1.2 GB the first time).

## Output: `pipeline/out/lombardy/pack/`

These files are the GitHub Release assets. The app downloads them one by one and checks each one (`App/Data/RegionPackInstaller.swift`).

| Asset | Content |
|---|---|
| `manifest.json` | version, bbox, Valhalla version, sizes and sha256 per file (packed and unpacked), sources and licences. Schema: `schema/manifest.schema.json` |
| `valhalla_tiles.tar.xz` | Valhalla 3.9.0 routing tiles. Grades come from Copernicus GLO-30; the country and region come from the admin build |
| `hazards.sqlite.xz` | `hazards` table + `hazards_rtree`: tram, along, cobbles, steps, gap, dismount, lane, door (see `stages/hazards.py`) |
| `routes.sqlite.xz` | OSM cycle-route relations (`route=bicycle|mtb`), merged geometry as polyline6, EuroVelo number |
| `transit.sqlite.xz` | Trenord rail + ATM metro GTFS subset for 60 days, and `bike_rules` from `config/bikes_allowed_rules.yml` |

The budget is **220 MB to download** (Filippo, 14 Oct 2026); `validate` fails the build above it.

## Stages (`stages/`)

| Stage | Image | What it does |
|---|---|---|
| `extract.sh` | tools | Geofabrik nord-ovest (md5-checked) → Lombardy polygon (relation 44879) → `region.osm.pbf`. Also builds `country.osm.pbf` (`country_admin.py`) |
| `elevation.py` | tools | Copernicus GLO-30 COGs (AWS Open Data) → 1″ SRTM `.hgt`, used only at build time |
| `tiles.sh` | Valhalla 3.9.0 | admins, timezones, tiles with elevation, tar extract |
| `hazards.py` | tools | pyosmium + shapely, two passes over the extract |
| `routes.py` | tools | cycle-route relations |
| `transit.py` | tools | GTFS download, filter, 60-day window. A feed that ends inside the window repeats its last week (`projected`) |
| `package.py` | tools | xz -9 (single-threaded: identical output on any machine) + manifest |
| `validate.py` | tools | JSON Schema, sizes, sha256, budget |
| `smoke_routes.sh` + `smoke.py` | Valhalla + tools | 6 Milan/Bergamo routes with the City profile, hazard counts and spot checks, EuroVelo 5, Centrale → Monza trains, M1 stops |

The pack is a pure function of its inputs: there are no wall-clock timestamps; the build date and transit window start come from the OSM extract date. Rebuilding from the same inputs gives byte-identical SQLite files. The Valhalla tiles match apart from Valhalla's own build stamps (a few bytes per tile), with the same size and the same routes (checked in M2).

## Publishing

`.github/workflows/region-pack.yml` runs monthly (1st, 03:00 UTC), on manual dispatch, and on PRs that touch `pipeline/`. On `main` it publishes the Release `pack-lombardy-YYYY.MM` (`.N` if that tag exists), with the release notes from `stages/release_notes.py`. Pack binaries never go in git.

## Curated data

`config/bikes_allowed_rules.yml` lists the bikes-on-board rules by operator and line, each with its source. **Review it when an operator changes its rules.** Trenord marks bikes per train only in its own app, so Trenord trains carry `status: check`.

The M1 spike tooling stays in `spike/` for reference.
