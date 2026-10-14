# M1 spike tiles

Throwaway tooling for the M1 tech spike. M2 replaces it with the real region-pack pipeline.

```bash
# needs osmium-tool and a Docker engine (Colima works: brew install colima && colima start)
./pipeline/spike/build_milan_tiles.sh            # → pipeline/cache/spike/valhalla_tiles.tar (≈ 70 MB)
python3 pipeline/spike/drive_path.py OUT.gpx lat,lon lat,lon …   # GPS path for simctl location
```

The tar is not bundled in the app. Side-load it into the app's Documents folder:

```bash
# simulator
cp pipeline/cache/spike/valhalla_tiles.tar "$(xcrun simctl get_app_container booted io.github.over-map.velix data)/Documents/"
# iPhone
xcrun devicectl device copy to --device <device-id> --domain-type appDataContainer \
  --domain-identifier io.github.over-map.velix \
  --source pipeline/cache/spike/valhalla_tiles.tar --destination Documents/valhalla_tiles.tar
```
