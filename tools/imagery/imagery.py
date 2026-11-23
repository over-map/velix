#!/usr/bin/env python3
"""Aerial imagery for the Satellite map → App/Resources/Imagery/aerial-{sources,areas}.json.

Where a country (or a German state, a Belgian region, South Tyrol) publishes its aerial photos as a free, keyless
open-data service, the Satellite map shows them from z13 over EOX Sentinel-2 cloudless (AerialImagery.swift). Each
source is one row of SOURCES. The area it serves is the country's outline from pipeline/regions/countries.geojson, or
an OSM boundary kept in tools/imagery/admin1.geojson (`--fetch-admin1` refreshes it from Overpass, once in a while).
The app picks a tile's source by the tile's centre and drops the service's no-data (white) pixels, so an outline that
is a few hundred metres off shows EOX there instead of a white patch.

URL placeholders: {z} {x} {y}, {-y} (TMS rows, counted from the south), {bbox} (WMS: the tile in EPSG:3857 metres).

Usage:
  python3 tools/imagery/imagery.py               regenerate both files (needs shapely + pyproj)
  python3 tools/imagery/imagery.py --check       fail if either file is stale (no geo libraries needed; CI runs it)
  python3 tools/imagery/imagery.py --online      fetch a z17 tile of every source (needs the network; run before a
                                                 PR that changes SOURCES; uses swift + URLSession, as the app does)
  python3 tools/imagery/imagery.py --fetch-admin1   refresh admin1.geojson from Overpass (OSM, ODbL)
"""
import hashlib
import json
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
COUNTRIES = ROOT / "pipeline/regions/countries.geojson"
ADMIN1 = HERE / "admin1.geojson"
OUT = ROOT / "App/Resources/Imagery"

WMS13 = "SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap&STYLES=&CRS=EPSG:3857&WIDTH=256&HEIGHT=256&FORMAT=image/jpeg&BBOX={bbox}&LAYERS="
WMS11 = "SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&STYLES=&SRS=EPSG:3857&WIDTH=256&HEIGHT=256&FORMAT=image/jpeg&BBOX={bbox}&LAYERS="
DL_BY = ("Data licence Germany – attribution – 2.0", "https://www.govdata.de/dl-de/by-2-0")
DL_ZERO = ("Data licence Germany – zero – 2.0", "https://www.govdata.de/dl-de/zero-2-0")
CC_BY = ("CC BY 4.0", "https://creativecommons.org/licenses/by/4.0/")
CC0 = ("CC0 1.0", "https://creativecommons.org/publicdomain/zero/1.0/")

# id, area (ISO 3166-1 / -2), name, url, attribution (as the agency asks for it), licence, test point (lat, lon).
# Checked 23 Nov 2026: each served a z17 tile with no key. Not here: Italy (AGEA: download only), Denmark, Sweden,
# Finland (key or account), Norway (restricted), GB, IE, IS, LV, LT, HU, RO, BG, GR, CY, MT (no open service).
# City-states and regions come first: a tile takes the first area that holds its centre.
SOURCES = [
    ("de-be", "DE-BE", "Berlin", "https://gdi.berlin.de/services/wms/truedop_2024?" + WMS13 + "truedop_2024",
     "© Geoportal Berlin / TrueDOP 2024", DL_ZERO, (52.52, 13.405)),
    ("de-hb", "DE-HB", "Bremen", "https://geodienste.bremen.de/wms_dop20_2023?" + WMS13 + "DOP20_2023_HB,DOP20_2023_BHV",
     "© Landesamt GeoInformation Bremen", CC_BY, (53.0793, 8.8017)),
    ("de-hh", "DE-HH", "Hamburg", "https://geodienste.hamburg.de/wms_dop_zeitreihe_unbelaubt?" + WMS13 + "dop_zeitreihe_unbelaubt",
     "© Freie und Hansestadt Hamburg, LGV", DL_BY, (53.5511, 9.9937)),
    ("be-bru", "BE-BRU", "Brussels", "https://geoservices-grid.irisnet.be/geoserver/urbisgrid/ows?" + WMS13 + "Ortho",
     "© urbis.brussels (paradigm.brussels)", CC_BY, (50.8467, 4.3525)),
    ("be-vlg", "BE-VLG", "Flanders",
     "https://geo.api.vlaanderen.be/OMWRGBMRVL/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=omwrgbmrvl&STYLE="
     "&FORMAT=image/png&tileMatrixSet=GoogleMapsVL&tileMatrix={z}&tileRow={y}&tileCol={x}",
     "© Digitaal Vlaanderen", CC_BY, (51.0543, 3.7174)),
    ("be-wal", "BE-WAL", "Wallonia",
     "https://geoservices.wallonie.be/arcgis/services/IMAGERIE/ORTHO_LAST/MapServer/WmsServer?" + WMS13 + "0",
     "© Service public de Wallonie (SPW)", CC_BY, (50.4674, 4.8718)),
    ("it-bz", "IT-BZ", "South Tyrol",
     "https://geoservices.buergernetz.bz.it/mapproxy/p_bz-Orthoimagery/wms?" + WMS13 + "Aerial-2023-RGB",
     "© Autonome Provinz Bozen – Südtirol", CC0, (46.4983, 11.3548)),
    ("de-by", "DE-BY", "Bavaria", "https://geoservices.bayern.de/od/wms/dop/v1/dop20?" + WMS11 + "by_dop20c",
     "© Bayerische Vermessungsverwaltung", CC_BY, (48.1372, 11.5756)),
    ("de-bw", "DE-BW", "Baden-Württemberg",
     "https://owsproxy.lgl-bw.de/owsproxy/ows/WMS_LGL-BW_ATKIS_DOP_20_C?" + WMS13 + "IMAGES_DOP_20_RGB",
     "© LGL, www.lgl-bw.de", DL_BY, (48.7758, 9.1829)),
    ("de-bb", "DE-BB", "Brandenburg", "https://isk.geobasis-bb.de/mapproxy/dop20c/service/wms?" + WMS13 + "bebb_dop20c",
     "© GeoBasis-DE/LGB", DL_BY, (52.3906, 13.0645)),
    ("de-he", "DE-HE", "Hesse",
     "https://www.gds-srv.hessen.de/cgi-bin/lika-services/ogc-free-images.ows?" + WMS13 + "he_dop20_rgb",
     "© HVBG", DL_ZERO, (50.1109, 8.6821)),
    ("de-mv", "DE-MV", "Mecklenburg-Vorpommern", "https://www.geodaten-mv.de/dienste/adv_dop?" + WMS13 + "mv_dop",
     "© GeoBasis-DE/M-V", CC_BY, (54.0924, 12.0991)),
    ("de-ni", "DE-NI", "Lower Saxony", "https://opendata.lgln.niedersachsen.de/doorman/noauth/dop_wms?" + WMS13 + "ni_dop20",
     "© LGLN", CC_BY, (52.3759, 9.732)),
    ("de-nw", "DE-NW", "North Rhine-Westphalia", "https://www.wms.nrw.de/geobasis/wms_nw_dop?" + WMS13 + "nw_dop_rgb",
     "© Geobasis NRW", DL_ZERO, (51.2277, 6.7735)),
    ("de-rp", "DE-RP", "Rhineland-Palatinate", "https://geo4.service24.rlp.de/wms/rp_dop20.fcgi?" + WMS13 + "rp_dop20",
     "© GeoBasis-DE/LVermGeoRP", DL_BY, (49.9929, 8.2473)),
    ("de-sl", "DE-SL", "Saarland", "https://geoportal.saarland.de/freewms/truedop?" + WMS13 + "sl_dop20_rgb",
     "© GeoBasis DE/LVGL-SL", DL_BY, (49.2402, 6.9969)),
    ("de-sn", "DE-SN", "Saxony", "https://geodienste.sachsen.de/wms_geosn_dop-rgb/guest?" + WMS13 + "sn_dop_020",
     "© GeoSN", DL_BY, (51.0504, 13.7373)),
    ("de-st", "DE-ST", "Saxony-Anhalt",
     "https://www.geodatenportal.sachsen-anhalt.de/wss/service/ST_LVermGeo_DOP_WMS_OpenData/guest?" + WMS13 + "lsa_lvermgeo_dop20_2",
     "© GeoBasis-DE/LVermGeo ST", DL_BY, (52.1205, 11.6276)),
    ("de-sh", "DE-SH", "Schleswig-Holstein", "https://dienste.gdi-sh.de/WMS_SH_DOP20col_OpenGBD?" + WMS13 + "sh_dop20_rgb",
     "© GeoBasis-DE/LVermGeo SH", CC_BY, (54.3233, 10.1228)),
    ("de-th", "DE-TH", "Thuringia", "https://www.geoproxy.geoportal-th.de/geoproxy/services/DOP?" + WMS13 + "th_dop",
     "© GDI-Th", DL_BY, (50.9787, 11.0328)),
    ("at", "AT", "Austria", "https://mapsneu.wien.gv.at/basemap/bmaporthofoto30cm/normal/google3857/{z}/{y}/{x}.jpeg",
     "basemap.at", CC_BY, (48.2082, 16.3738)),
    ("ch", "CH", "Switzerland", "https://wmts.geo.admin.ch/1.0.0/ch.swisstopo.swissimage/default/current/3857/{z}/{x}/{y}.jpeg",
     "© swisstopo", ("swisstopo open data (free use, attribution)", "https://www.swisstopo.admin.ch/en/terms-of-use-free-geodata-and-geoservices"),
     (46.948, 7.4474)),
    ("cz", "CZ", "Czechia", "https://ags.cuzk.cz/arcgis1/rest/services/ORTOFOTO_WM/MapServer/tile/{z}/{y}/{x}",
     "© ČÚZK", CC_BY, (50.0755, 14.4378)),
    ("ee", "EE", "Estonia", "https://tiles.maaamet.ee/tm/tms/1.0.0/foto@GMC/{z}/{x}/{-y}.png",
     "© Maa- ja Ruumiamet", ("Maa- ja Ruumiamet open data licence", "https://maaruum.ee/en/open-data-licence"), (59.437, 24.7536)),
    ("es", "ES", "Spain", "https://tms-pnoa-ma.idee.es/1.0.0/pnoa-ma/{z}/{x}/{-y}.jpeg",
     "PNOA cedido por © Instituto Geográfico Nacional", CC_BY, (40.4168, -3.7038)),
    ("fr", "FR", "France",
     "https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=ORTHOIMAGERY.ORTHOPHOTOS&STYLE=normal"
     "&TILEMATRIXSET=PM&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/jpeg",
     "© IGN", ("Licence Ouverte Etalab 2.0", "https://www.etalab.gouv.fr/licence-ouverte-open-licence/"), (48.8566, 2.3522)),
    ("hr", "HR", "Croatia",
     "https://geoportal.dgu.hr/services/inspire/orthophoto_2023_2024/ows?" + WMS13 + "OI.OrthoimageCoverage",
     "© Državna geodetska uprava", ("Open licence of the Republic of Croatia", "https://data.gov.hr/otvorena-dozvola"), (45.815, 15.9819)),
    ("lu", "LU", "Luxembourg", "https://wmts1.geoportail.lu/opendata/wmts/ortho_latest/GLOBAL_WEBMERCATOR_4_V3/{z}/{x}/{y}.jpeg",
     "© Administration du cadastre et de la topographie (ACT)", CC0, (49.6116, 6.1319)),
    ("nl", "NL", "Netherlands", "https://service.pdok.nl/hwh/luchtfotorgb/wmts/v1_0/Actueel_orthoHR/EPSG:3857/{z}/{x}/{y}.jpeg",
     "Beeldmateriaal.nl / PDOK", CC_BY, (52.3676, 4.9041)),
    ("pl", "PL", "Poland",
     "https://mapy.geoportal.gov.pl/wss/service/PZGIK/ORTO/WMS/HighResolution?" + WMS13 + "Raster",
     "© GUGiK", ("Free reuse (Polish Geodetic and Cartographic Law, art. 40a)", "https://www.geoportal.gov.pl/en/regulations"),
     (52.2297, 21.0122)),
    ("pt", "PT", "Portugal", "https://cartografia.dgterritorio.gov.pt/wms/ortos2025?" + WMS13 + "Ortos2025-RGB",
     "© Direção-Geral do Território", CC_BY, (38.7223, -9.1393)),
    ("si", "SI", "Slovenia", "https://ipi.eprostor.gov.si/wms-si-gurs-dts/wms?" + WMS13 + "SI.GURS.ZPDZ:DOF025",
     "© GURS", CC_BY, (46.0569, 14.5058)),
    ("sk", "SK", "Slovakia", "https://zbgisws.skgeodesy.sk/zbgis_ortofoto_wms/service.svc/get?" + WMS11 + "1",
     "© ÚGKK SR", CC_BY, (48.1486, 17.1077)),
]

TOLERANCE_M = 300      # outline simplification
DECIMALS = 4           # ≈ 10 m


def sources_json() -> str:
    rows = [{"id": i, "area": a, "name": n, "url": u, "attribution": att, "licence": lic[0], "licenceURL": lic[1],
             "test": list(t)} for i, a, n, u, att, lic, t in SOURCES]
    return json.dumps({"minZoom": 13, "maxZoom": 18, "sources": rows}, ensure_ascii=False, indent=1) + "\n"


def inputs_digest() -> str:
    h = hashlib.sha256()
    for p in (COUNTRIES, ADMIN1):
        h.update(p.read_bytes())
    h.update(json.dumps(sorted({s[1] for s in SOURCES})).encode())
    h.update(f"{TOLERANCE_M}/{DECIMALS}".encode())
    return h.hexdigest()[:16]


def areas_json() -> str:
    from shapely.geometry import shape, mapping
    from shapely.ops import transform
    import pyproj
    to_m = pyproj.Transformer.from_crs(4326, 3035, always_xy=True).transform
    to_deg = pyproj.Transformer.from_crs(3035, 4326, always_xy=True).transform
    geoms = {f["properties"]["iso"]: f["geometry"] for f in json.loads(COUNTRIES.read_text())["features"]}
    geoms |= {f["properties"]["iso"]: f["geometry"] for f in json.loads(ADMIN1.read_text())["features"]}
    out = {}
    for area in dict.fromkeys(s[1] for s in SOURCES):
        g = transform(to_m, shape(geoms[area])).simplify(TOLERANCE_M)
        g = transform(to_deg, g)
        polys = [g] if g.geom_type == "Polygon" else list(g.geoms)
        out[area] = [[[[round(x, DECIMALS), round(y, DECIMALS)] for x, y in ring.coords]
                      for ring in [p.exterior, *p.interiors]] for p in polys if p.area > 0]
    return json.dumps({"digest": inputs_digest(), "areas": out}, separators=(",", ":")) + "\n"


def fetch_admin1():
    """German states, the three Belgian regions and South Tyrol from OSM (Overpass), as GeoJSON."""
    from shapely.geometry import LineString, mapping
    from shapely.ops import polygonize, unary_union
    codes = sorted({s[1] for s in SOURCES if "-" in s[1]})
    # Kept as it goes (Overpass is often busy): a rerun fetches only what is missing; delete the file to refresh all.
    feats = json.loads(ADMIN1.read_text())["features"] if ADMIN1.exists() else []
    have = {f["properties"]["iso"] for f in feats}
    for code in codes:
        if code in have:
            continue
        q = (f'[out:json][timeout:300];relation["boundary"="administrative"]["ISO3166-2"="{code}"];out geom;')
        req = urllib.request.Request("https://overpass-api.de/api/interpreter",
                                     data=urllib.parse.urlencode({"data": q}).encode(),
                                     headers={"User-Agent": "Velix-build (github.com/over-map/velix)"})
        for attempt in range(8):
            try:
                with urllib.request.urlopen(req, timeout=400) as r:
                    rel = [e for e in json.load(r)["elements"] if e["type"] == "relation"][0]
                break
            except Exception as e:  # Overpass answers 429/502/504 when busy
                print(f"{code}: {e!r}, retrying", file=sys.stderr)
                time.sleep(30 * (attempt + 1))
        else:
            sys.exit(f"{code}: Overpass failed")
        lines = {"outer": [], "inner": []}
        for m in rel["members"]:
            if m["type"] == "way" and m.get("role") in lines and m.get("geometry"):
                lines[m["role"]].append(LineString([(p["lon"], p["lat"]) for p in m["geometry"]]))
        outer = unary_union(list(polygonize(lines["outer"])))
        inner = unary_union(list(polygonize(lines["inner"]))) if lines["inner"] else None
        g = outer.difference(inner) if inner is not None else outer
        # Kept to ≈ 50 m: the app's file is simplified further.
        g = g.simplify(0.0005)
        feats.append({"type": "Feature", "properties": {"iso": code, "name": rel["tags"].get("name"), "osm": rel["id"]},
                      "geometry": mapping(g)})
        print(f"{code}: {rel['tags'].get('name')} ({rel['id']})", file=sys.stderr)
        feats.sort(key=lambda f: f["properties"]["iso"])
        doc = {"type": "FeatureCollection", "attribution": "© OpenStreetMap contributors (ODbL)", "features": feats}
        ADMIN1.write_text(json.dumps(doc, separators=(",", ":")) + "\n")
        time.sleep(5)


def main():
    args = set(sys.argv[1:])
    if "--fetch-admin1" in args:
        return fetch_admin1()
    if "--online" in args:
        return subprocess.run(["swift", str(HERE / "online.swift"), str(OUT / "aerial-sources.json")], check=True)
    src, areas = OUT / "aerial-sources.json", OUT / "aerial-areas.json"
    if "--check" in args:
        stale = []
        if not src.exists() or src.read_text() != sources_json():
            stale.append("aerial-sources.json")
        if not areas.exists() or json.loads(areas.read_text()).get("digest") != inputs_digest():
            stale.append("aerial-areas.json")
        if stale:
            sys.exit(f"Out of date: {', '.join(stale)}. Run python3 tools/imagery/imagery.py")
        return
    OUT.mkdir(parents=True, exist_ok=True)
    src.write_text(sources_json())
    areas.write_text(areas_json())
    print(f"aerial-sources.json: {len(SOURCES)} sources; aerial-areas.json: {areas.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
