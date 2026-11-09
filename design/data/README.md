# Design reference data

These files feed the design references in `design/` (map frames and prototypes). They are not shipped in the app.

- **Map features** (`como.json`, `milan.json`, `monza*.json`, `north.json`, `wide.json`): extracted by `design/tools/extract.js`
  from OpenFreeMap vector tiles. © OpenStreetMap contributors, available under the
  [Open Database License 1.0](https://opendatacommons.org/licenses/odbl/1-0/); © OpenMapTiles (CC BY 4.0).
- **Routes** (`routes-*.json`): computed on OpenStreetMap data, © OpenStreetMap contributors (ODbL 1.0).
- **Elevation grids** (`dem-*.json`): sampled from open terrain data for the design's contour drawing. The handoff
  doesn't record the exact source; treat them as derived from Copernicus GLO-30 (© DLR e.V. 2010–2014 and © Airbus
  2014–2018, provided under COPERNICUS by the European Union and ESA).
