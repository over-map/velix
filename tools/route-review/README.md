# Golden-route review map

A private review page for the M3 golden routes (10 trips × 6 ride types).

1. Run the golden tests with `TEST_RUNNER_VELIX_GOLDEN_OUT=$PWD/build/golden` (see docs/TEST_TRIPS.md).
2. Basemap (tools image): `docker run --rm -v "$PWD:/work" -w /work velix-pipeline-tools python tools/route-review/basemap.py build/golden build/review/basemap.json`
3. Build `routes.json` (hazard tubes sliced from Best) and `glyphs.json` (design/assets/glyphs), inline MapLibre's CSS into `index.template.html`, and publish the folder as an Artifact.

It isn't part of the app; it follows the design tokens and the P3 marker spec, with the M3 Fastest colour override.
