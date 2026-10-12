# Third-party software, data and assets

Velix is licensed under Apache-2.0 (see `LICENSE`). Everything below keeps its own licence. Every dependency must have an OSI licence (fonts: OFL; icons: ISC; data: ODbL / CC BY). Update this file with every new dependency.

## Swift packages (pinned in `project.yml`, resolved in `Package.resolved`)

| Package | Version | Licence | Used for |
|---|---|---|---|
| [Ferrostar](https://github.com/stadiamaps/ferrostar) (FerrostarCore, FerrostarMapLibreUI, FerrostarSwiftUI) | 0.57.0 | BSD-3-Clause | Navigation core, route progress, rerouting |
| [MapLibre Native iOS](https://github.com/maplibre/maplibre-gl-native-distribution) | 6.31.0 | BSD-2-Clause | Map rendering |
| [MapLibre SwiftUI DSL](https://github.com/maplibre/swiftui-dsl) (via Ferrostar) | 0.25.0 | BSD-3-Clause | SwiftUI map wrapper |
| [valhalla-mobile](https://github.com/Rallista/valhalla-mobile) | 0.6.3 | MIT | On-device Valhalla routing |
| [Valhalla](https://github.com/valhalla/valhalla) (inside valhalla-mobile) | bundled | MIT | Routing engine |
| [valhalla-openapi-models-swift](https://github.com/Rallista/valhalla-openapi-models-swift) (via valhalla-mobile) | 0.5.4 | MIT | Valhalla request/response models |
| [Light-Swift-Untar](https://github.com/UInt2048/Light-Swift-Untar) (via valhalla-mobile) | 1.0.4 | BSD-2-Clause | Tile archive extraction |
| [AnyCodable](https://github.com/Flight-School/AnyCodable) (via valhalla models) | 0.6.7 | MIT | JSON models |
| [swift-syntax](https://github.com/swiftlang/swift-syntax) (build-time, macros) | 602.0.0 | Apache-2.0 | MapLibre DSL macros |
| [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) (tests only) | 1.19.6 | MIT | Snapshot tests |
| [swift-custom-dump](https://github.com/pointfreeco/swift-custom-dump) (tests only) | 1.7.3 | MIT | Test diffs |
| [xctest-dynamic-overlay](https://github.com/pointfreeco/xctest-dynamic-overlay) (tests only) | 1.13.1 | MIT | Test support |

## Fonts (bundled in `App/Resources/Fonts/`)

| Font | Files | Licence |
|---|---|---|
| Atkinson Hyperlegible, © 2020 Braille Institute of America | Regular, Bold (from google/fonts) | SIL OFL 1.1 (`OFL-AtkinsonHyperlegible.txt`) |
| Familjen Grotesk, © 2021 The Familjen Grotesk Project Authors | Medium, SemiBold, Bold: static instances cut from the google/fonts variable font v2.002 with fontTools `varLib.instancer` (no Reserved Font Name declared) | SIL OFL 1.1 (`OFL-FamiljenGrotesk.txt`) |

## Icons and artwork

| Asset | Licence |
|---|---|
| [Lucide](https://lucide.dev) icons (`design/assets/lucide/`) | ISC |
| Velix custom glyphs and app icon (`design/assets/`) | Apache-2.0 (this project) |

## Map and routing data

| Data | Licence | Attribution |
|---|---|---|
| OpenStreetMap | ODbL 1.0 | "© OpenStreetMap contributors" on every map |
| OpenFreeMap tiles | Free, attribution requested | You → About |
| Copernicus GLO-30 DEM | Copernicus licence (free, attribution) | You → About |
| Trenord / ATM GTFS | Per operator open-data terms (to confirm in M2) | You → About |
