"""Basemap for the golden-route review page: OSM roads, paths, tram rails, water and parks around each trip,
clipped to the trips' route corridors and simplified. Run in the tools image:
  docker run --rm -v "$PWD:/work" -w /work velix-pipeline-tools python tools/route-review/basemap.py build/golden build/review/basemap.json"""
import glob, json, subprocess, sys, tempfile, os
from shapely.geometry import shape, mapping, box
from shapely.ops import unary_union

golden, out = sys.argv[1], sys.argv[2]
PBF = "pipeline/out/lombardy/region.osm.pbf"
boxes = []
for t in range(1, 11):
    xs, ys = [], []
    for f in glob.glob(f"{golden}/{t}-*.geojson"):
        for feat in json.load(open(f))["features"]:
            g = feat["geometry"]
            pts = g["coordinates"] if g["type"] == "LineString" else [g["coordinates"]]
            xs += [p[0] for p in pts]; ys += [p[1] for p in pts]
    if xs:
        boxes.append((min(xs) - 0.004, min(ys) - 0.003, max(xs) + 0.004, max(ys) + 0.003))
classes = {"motorway": "major", "trunk": "major", "primary": "major", "secondary": "major", "tertiary": "minor",
           "unclassified": "minor", "residential": "minor", "living_street": "minor", "pedestrian": "minor",
           "cycleway": "cycle", "track": "path"}
feats, seen = [], set()
with tempfile.TemporaryDirectory() as tmp:
    for i, (w, s, e, n) in enumerate(boxes):
        clip = f"{tmp}/c{i}.pbf"
        subprocess.run(["osmium", "extract", "-b", f"{w},{s},{e},{n}", PBF, "-o", clip, "--overwrite", "-s", "simple"], check=True)
        filt = f"{tmp}/f{i}.pbf"
        subprocess.run(["osmium", "tags-filter", clip, "w/highway", "w/railway=tram", "w/waterway=canal,river",
                        "wa/natural=water", "wa/leisure=park", "wa/landuse=grass,recreation_ground,forest",
                        "-o", filt, "--overwrite"], check=True)
        gj = f"{tmp}/g{i}.geojsonseq"
        subprocess.run(["osmium", "export", filt, "-f", "geojsonseq", "-o", gj, "--overwrite", "-a", "id"], check=True)
        clipbox = box(w, s, e, n)
        for line in open(gj):
            f = json.loads(line.lstrip("\x1e"))
            fid = f["properties"].get("@id") or json.dumps(f["geometry"])[:80]
            if fid in seen:
                continue
            seen.add(fid)
            p = f["properties"]
            if p.get("railway") == "tram": cls = "tram"
            elif p.get("waterway") or p.get("natural") == "water": cls = "water"
            elif p.get("leisure") or p.get("landuse"): cls = "park"
            else: cls = classes.get(p.get("highway"))
            if not cls:
                continue
            g = shape(f["geometry"]).intersection(clipbox).simplify(0.00007, preserve_topology=False)
            if g.is_empty or (cls == "park" and g.area < 2e-7):
                continue
            m = mapping(g)
            def rnd(c):
                return [round(c[0], 5), round(c[1], 5)] if isinstance(c[0], float) else [rnd(x) for x in c]
            feats.append({"type": "Feature", "properties": {"c": cls}, "geometry": {"type": m["type"], "coordinates": rnd(m["coordinates"])}})
# Region-wide context: the pack border, main roads and railways across Lombardy (heavily simplified).
with tempfile.TemporaryDirectory() as tmp:
    filt = f"{tmp}/region.pbf"
    subprocess.run(["osmium", "tags-filter", PBF, "w/highway=motorway,trunk,primary,secondary", "w/railway=rail",
                    "-o", filt, "--overwrite"], check=True)
    gj = f"{tmp}/region.geojsonseq"
    subprocess.run(["osmium", "export", filt, "-f", "geojsonseq", "-o", gj, "--overwrite"], check=True)
    for line in open(gj):
        f = json.loads(line.lstrip("\x1e"))
        if f["geometry"]["type"] != "LineString":
            continue
        cls = "rail" if f["properties"].get("railway") == "rail" else "region-road"
        g = shape(f["geometry"]).simplify(0.0006, preserve_topology=False)
        if g.is_empty or g.length < 0.002:
            continue
        m = mapping(g)
        feats.append({"type": "Feature", "properties": {"c": cls},
                      "geometry": {"type": "LineString", "coordinates": [[round(x, 4), round(y, 4)] for x, y in m["coordinates"]]}})
border = shape(json.load(open("pipeline/out/lombardy/region.geojson"))["features"][0]["geometry"]).simplify(0.002)
bm = mapping(border.boundary)
lines = bm["coordinates"] if bm["type"] == "MultiLineString" else [bm["coordinates"]]
for ln in lines:
    feats.append({"type": "Feature", "properties": {"c": "border"},
                  "geometry": {"type": "LineString", "coordinates": [[round(x, 4), round(y, 4)] for x, y in ln]}})
os.makedirs(os.path.dirname(out), exist_ok=True)
json.dump({"type": "FeatureCollection", "features": feats}, open(out, "w"), separators=(",", ":"))
print(len(feats), "features", round(os.path.getsize(out) / 1e6, 2), "MB")
