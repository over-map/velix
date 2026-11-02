# Region pack pipeline

Builds the Velix offline region packs (Lombardy, Piedmont, Veneto, Emilia-Romagna, Trentino-South Tyrol) from open data. It runs in Docker, so local and CI builds match.

```bash
make -C pipeline pack REGION=piemonte   # every stage: extract → elevation → prepare → tiles → hazards → routes → transit → package → validate → smoke
make -C pipeline hazards         # one stage at a time (stages read the previous stages' outputs in pipeline/out/<region>/)
make -C pipeline clean           # remove pipeline/out/<region>/ (downloads stay in pipeline/cache/)
```

Needs Docker (Colima works: `brew install colima && colima start --cpu 6 --memory 12`) and `python3` on the host for the Makefile. A full build takes about 15 minutes on an M1 Pro, plus downloads (≈ 2.5 GB the first time: the Italy extract is shared by every region).

**Regions** are `config/<region>.yml` over `config/_base.yml` (merged key by key: what every region shares), with smoke expectations in the config's `smoke:` block and `config/smoke_trips/<region>.txt` (`id|from|to|min km|max km`). Each pack's routing data (tiles, hazards, cycle routes, timetable) covers its region **plus `coverage.buffer_km`** (10 km) past the border (`coverage.geojson`), so a trip just across a border plans in either pack (Valhalla tiles from two builds can't be joined on the phone); the map tiles (basemap, overlays) stop at the border (`map.osm.pbf`).

## Output: `pipeline/out/<region>/pack/`

These files are the GitHub Release assets. The app downloads them one by one and checks each one (`App/Data/RegionPackInstaller.swift`).

| Asset | Content |
|---|---|
| `manifest.json` | version, bbox, the border and the coverage (border + buffer) as simplified polygons, Valhalla version, sizes and sha256 per file (packed and unpacked), sources and licences. Schema: `schema/manifest.schema.json` |
| `valhalla_tiles.tar.xz` | Valhalla 3.9.0 routing tiles. Grades come from GEDTM30; cobbles are a bad surface for routing; the country and region come from the admin build |
| `hazards.sqlite.xz` | `hazards` table + `hazards_rtree`: tram, along, cobbles, steps, gap, dismount, lane (with heading), door; `ways` table: lighting and paths per way id (schema 2, see `stages/hazards.py`) |
| `routes.sqlite.xz` | OSM cycle-route relations (`route=bicycle|mtb`), merged geometry as polyline6, EuroVelo number; schema 2: S7 mix shares (car-free / quiet / unpaved), climb both ways, description, from, to |
| `transit.sqlite.xz` | Trenord rail + ATM metro GTFS subset for 60 days, `bike_rules` from `config/bikes_allowed_rules.yml`, and `hops`: the OSM track between consecutive stops (`stages/transit_paths.py`; GTFS has no shapes) |
| `city.geojson.xz` | The city area (`region.city_area_relation`, Comune di Milano): the app suggests bike + transit when the destination is outside it |
| `basemap.pmtiles.xz` | OpenMapTiles-schema vector tiles z0–14 for the map (planetiler), tiles uncompressed inside the PMTiles so xz compresses across them |
| `overlays.pmtiles.xz` | Velix overlay tiles: `velix_cycling`, `velix_routes`, `velix_transit`, `velix_stations` (see `stages/overlays.py`) |

The budget is **320 MB to download** per region (Filippo: 300 on 16 Oct 2026, 320 with the routing buffer on 2 Nov); `validate` fails the build above it.

## Stages (`stages/`)

| Stage | Image | What it does |
|---|---|---|
| `extract.sh` | tools | Geofabrik Italy (md5-checked) → region polygon (`region.osm_relation`) → coverage (`coverage.py`: border + buffer) → `region.osm.pbf`. Also builds `country.osm.pbf` (`country_admin.py`: the coverage tagged as the country) |
| `elevation.py` | tools | GEDTM30 terrain model (COG over HTTP, CC BY 4.0) → 1″ SRTM `.hgt`, used only at build time |
| `prepare_routing.py` | tools | Routing copy of the extract: cobbled ways retagged `surface=dirt` so Valhalla's bicycle costing can avoid them |
| `tiles.sh` | Valhalla 3.9.0 | admins, timezones, tiles with elevation, tar extract |
| `hazards.py` | tools | pyosmium + shapely, two passes over the extract |
| `routes.py` | tools | cycle-route relations |
| `transit.py` | tools | GTFS download, filter, 60-day window. A feed that ends inside the window repeats its last week (`projected`) |
| basemap (Makefile) + `basemap_meta.py` | planetiler 0.10.2 + tools | OpenMapTiles profile on the extract; downloads water polygons, Natural Earth and lake centerlines into `cache/planetiler`; records sources and per-layer sizes |
| `overlays.py` | tools | pyosmium (cycle tags shared with `hazards.py`, route relations) + `metro_colors.py` (P3 families) → tippecanoe → PMTiles |
| `package.py` | tools | xz -9 (single-threaded: identical output on any machine) + manifest |
| `validate.py` | tools | JSON Schema, sizes, sha256, budget |
| `smoke_routes.sh` + `smoke.py` | Valhalla + tools | per region: the trips in `config/smoke_trips/`, the config's `smoke:` expectations (hazard counts and spot checks, EuroVelo, trains, metro stops, city area) |

The pack is a pure function of its inputs: there are no wall-clock timestamps; the build date and transit window start come from the OSM extract date. Rebuilding from the same inputs gives byte-identical SQLite files. The Valhalla tiles match apart from Valhalla's own build stamps (a few bytes per tile), with the same size and the same routes (checked in M2).

## Publishing

`.github/workflows/region-pack.yml` runs monthly (1st, 03:00 UTC), on manual dispatch, and on PRs that touch `pipeline/`. It builds every region in a matrix (golden route tests on Lombardy). On `main` it publishes one Release per region, `pack-<region>-YYYY.MM` (`.N` if that tag exists), with the release notes from `stages/release_notes.py`, then rewrites `packs.json` on the Release `pack-index` (`stages/index.py`): the newest pack of every region, which the app reads as its catalog. A region whose build fails keeps its previous pack in the index. Pack binaries never go in git.

## Curated data

Bikes on board follow one order of evidence in every region:
1. the feed's own `trips.txt` `bikes_allowed` flag (`trips.bikes_allowed`);
2. the region's curated rules (`config/bikes_allowed_rules.yml`, one file for every region: by feed and route, each with its source);
3. otherwise `check`.

**Review the rules when an operator changes them.** Trenord marks bikes per train only in its own app, so Trenord trains carry `status: check`. A new region needs curated rules only for feeds without `bikes_allowed`.

The M1 spike tooling stays in `spike/` for reference.
