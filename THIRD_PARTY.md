# Third-party software, data and assets

Velix is licensed under Apache-2.0 (see `LICENSE`). Everything below keeps its own licence. Every dependency must have an OSI licence (fonts: OFL; icons: ISC; data: ODbL / CC BY). Update this file with every new dependency.

## Swift packages (pinned in `project.yml`, resolved in `Package.resolved`)

| Package | Version | Licence | Used for |
|---|---|---|---|
| [Ferrostar](https://github.com/stadiamaps/ferrostar) (FerrostarCore, FerrostarMapLibreUI, FerrostarSwiftUI) | 0.57.0 | BSD-3-Clause | Navigation core, route progress, rerouting |
| [MapLibre Native iOS](https://github.com/maplibre/maplibre-gl-native-distribution) | 6.31.0 | BSD-2-Clause | Map rendering |
| [MapLibre SwiftUI DSL](https://github.com/maplibre/swiftui-dsl) (MapLibreSwiftUI; also via Ferrostar) | 0.25.0 | BSD-3-Clause | SwiftUI map wrapper |
| [valhalla-mobile](https://github.com/Rallista/valhalla-mobile) | 0.6.3 | MIT | On-device Valhalla routing |
| [Valhalla](https://github.com/valhalla/valhalla) (inside valhalla-mobile) | bundled | MIT | Routing engine |
| [valhalla-openapi-models-swift](https://github.com/Rallista/valhalla-openapi-models-swift) (via valhalla-mobile) | 0.5.4 | MIT | Valhalla request/response models |
| [Light-Swift-Untar](https://github.com/UInt2048/Light-Swift-Untar) (via valhalla-mobile) | 1.0.4 | BSD-2-Clause | Tile archive extraction |
| [AnyCodable](https://github.com/Flight-School/AnyCodable) (via valhalla models) | 0.6.7 | MIT | JSON models |
| [swift-syntax](https://github.com/swiftlang/swift-syntax) (build-time, macros) | 602.0.0 | Apache-2.0 | MapLibre DSL macros |
| [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) (tests only) | 1.19.6 | MIT | Snapshot tests |
| [swift-custom-dump](https://github.com/pointfreeco/swift-custom-dump) (tests only) | 1.7.3 | MIT | Test diffs |
| [xctest-dynamic-overlay](https://github.com/pointfreeco/xctest-dynamic-overlay) (tests only) | 1.13.1 | MIT | Test support |

## Build tools (not shipped)

| Tool | Licence | Used for |
|---|---|---|
| [Valhalla](https://github.com/valhalla/valhalla) Docker image `ghcr.io/valhalla/valhalla:3.9.0` | MIT | Building routing tiles |
| [osmium-tool](https://osmcode.org/osmium-tool/) | GPL-3.0 (tool only, not linked) | Clipping OSM extracts |
| [Colima](https://github.com/abiosoft/colima) | MIT | Local Docker engine |
| [fontTools](https://github.com/fonttools/fonttools) | MIT | Cutting static font instances |
| [GDAL](https://gdal.org) image `ghcr.io/osgeo/gdal:ubuntu-small-3.11.4` | MIT | DEM → SRTM tiles |
| [MapLibre GL JS](https://github.com/maplibre/maplibre-gl-js) 4.7.1 | BSD-3-Clause | Golden-route review map (`tools/route-review`, not in the app) |
| [pyosmium](https://osmcode.org/pyosmium/) 4.0.2 | BSD-2-Clause | Reading OSM in the pipeline |
| [Shapely](https://github.com/shapely/shapely) 2.0.7 | BSD-3-Clause | Hazard geometry |
| [pyproj](https://github.com/pyproj4/pyproj) 3.7.1 | MIT | Metric projection |
| [PyYAML](https://github.com/yaml/pyyaml) 6.0.2 | MIT | Config |
| [jsonschema](https://github.com/python-jsonschema/jsonschema) 4.23.0 | MIT | Manifest validation |
| [planetiler](https://github.com/onthegomap/planetiler) 0.10.2 (OpenMapTiles profile) | Apache-2.0 (profile BSD-3-Clause) | Building the basemap tiles |
| [tippecanoe](https://github.com/felt/tippecanoe) 2.79.0 | BSD-2-Clause | Building the overlay tiles |
| [node-fontnik](https://github.com/mapbox/node-fontnik) 0.7.7 | BSD-3-Clause | Map label glyphs (SDF PBF) from the bundled fonts |
| [@maplibre/maplibre-gl-style-spec](https://github.com/maplibre/maplibre-style-spec) 26.4.4 (`gl-style-validate`) | BSD-3-Clause | Validating the generated map styles (CI) |
| [d3](https://d3js.org) 7.9.0 (cdnjs, P3 frame harness only) | ISC | `tools/p3-frames` runs the design's renderer, which uses d3 for contours |

## Fonts (bundled in `App/Resources/Fonts/`)

| Font | Files | Licence |
|---|---|---|
| Atkinson Hyperlegible, © 2020 Braille Institute of America | Regular, Bold (from google/fonts); also as map glyphs in `App/Resources/MapStyle/glyphs/` (SDF PBF built from the same files) | SIL OFL 1.1 (`OFL-AtkinsonHyperlegible.txt`) |
| Familjen Grotesk, © 2021 The Familjen Grotesk Project Authors | Medium, SemiBold, Bold: static instances cut from the google/fonts variable font v2.002 with fontTools `varLib.instancer` (no Reserved Font Name declared) | SIL OFL 1.1 (`OFL-FamiljenGrotesk.txt`) |

## Icons and artwork

| Asset | Licence |
|---|---|
| [Lucide](https://lucide.dev) icons (`design/assets/lucide/`, and `tools/icons-extra/` from lucide-static 0.460.0) | ISC |
| Velix custom glyphs and app icon (`design/assets/`, `tools/glyphs-extra/`) | Apache-2.0 (this project) |

## Map and routing data

| Data | Licence | Attribution |
|---|---|---|
| OpenStreetMap (Geofabrik extracts) | ODbL 1.0 | "© OpenStreetMap contributors" on every map |
| OpenMapTiles schema; basemap tiles built from OSM with planetiler (in the pack) | CC BY 4.0 (schema/tiles), ODbL (data) | "© OpenMapTiles © OpenStreetMap contributors" on the map |
| OSM water polygons and lake centerlines (osmdata.openstreetmap.de, osm-lakelines) | ODbL 1.0 | "© OpenStreetMap contributors" |
| Natural Earth vector | Public domain | "Made with Natural Earth" (You → About) |
| Photon geocoder (komoot, photon.komoot.io; OpenStreetMap data) | Service: fair use; data ODbL 1.0 | "Search by Photon · © OpenStreetMap contributors" (You → About) |
| OpenFreeMap tiles (debug spike screen only, until M7) | Free, attribution requested | Spike screen |
| GEDTM30 global 30 m terrain model, Ho et al. (2025), OpenGeoHub (doi:10.5281/zenodo.15689805) | CC BY 4.0 | "GEDTM30, OpenGeoHub, CC BY 4.0" (You → About, release notes). Grades in the routing tiles only; the DEM is not shipped |
| Trenord GTFS "Orario Ferroviario Regionale" (Regione Lombardia open data, dataset 3z4k-mxz9) | CC BY 4.0 | "Trenord" (You → About) |
| ATM GTFS (Comune di Milano open data, ds929) | CC BY 4.0 | "ATM, via Comune di Milano" (You → About) |
