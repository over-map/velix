"""Stage 9b: smoke tests on the built pack. Expectations per region: config `smoke` and config/smoke_trips/<region>.txt
(the golden route tests run on Lombardy in CI)."""
import datetime as dt
import json
import sqlite3
import sys

from common import PIPELINE, load_config, log, out_dir

# Every pack: these basemap layers have data.
LAYERS = ("transportation", "building", "landcover", "water", "poi", "transportation_name", "place")


def near(db, table, lat, lon, metres, where="1"):
    d = metres / 111_000
    return db.execute(
        f"SELECT count(*) FROM {table} t JOIN {table}_rtree r ON r.id = t.id "
        f"WHERE r.min_lon <= ? AND r.max_lon >= ? AND r.min_lat <= ? AND r.max_lat >= ? AND {where}",
        (lon + d, lon - d, lat + d, lat - d)).fetchone()[0]


def trips(region: str) -> dict[str, tuple[float, float]]:
    """trip id → (min km, max km) with the City profile, from config/smoke_trips/<region>.txt (id|from|to|min|max)."""
    out = {}
    for line in (PIPELINE / "config" / "smoke_trips" / f"{region}.txt").read_text().splitlines():
        if line.strip():
            trip, _, _, lo, hi = line.split("|")
            out[trip] = (float(lo), float(hi))
    return out


def main() -> int:
    cfg = load_config()
    out = out_dir(cfg)
    sm = cfg.get("smoke", {})
    fails = []

    def check(ok, msg):
        log(("ok   " if ok else "FAIL ") + msg)
        if not ok:
            fails.append(msg)

    for trip, (lo, hi) in trips(cfg["region"]["id"]).items():
        r = json.loads((out / "smoke" / f"{trip}.json").read_text())
        km = r.get("trip", {}).get("summary", {}).get("length")
        check(km is not None and lo <= km <= hi, f"route {trip}: {km} km (expected {lo}–{hi})")

    hz = sqlite3.connect(out / "hazards.sqlite")
    counts = dict(hz.execute("SELECT type, count(*) FROM hazards GROUP BY type"))
    for kind, minimum in sm.get("hazards", {}).items():
        check(counts.get(kind, 0) >= minimum, f"hazards {kind}: {counts.get(kind, 0)} (≥ {minimum})")
    for n in sm.get("hazards_near", []):
        types = ",".join(f"'{t}'" for t in n["types"])
        check(near(hz, "hazards", n["lat"], n["lon"], n["m"], f"t.type IN ({types})") > 0, n["what"])
    lit = hz.execute("SELECT count(*) FROM ways WHERE lit = 1").fetchone()[0]
    check(lit >= sm.get("lit_ways", 1), f"lit ways: {lit} (≥ {sm.get('lit_ways', 1)})")
    check(hz.execute("SELECT value FROM meta WHERE key='schema'").fetchone()[0] == "2", "hazards schema 2")

    bm = json.loads((out / "basemap.counts.json").read_text())
    check(bm["tiles"] >= sm.get("basemap_tiles", 1), f"basemap tiles: {bm['tiles']} (≥ {sm.get('basemap_tiles', 1)})")
    for layer in LAYERS:
        check(bm["layer_mb"].get(layer, 0) > 0.5, f"basemap layer {layer}: {bm['layer_mb'].get(layer, 0)} MB")
    ov = json.loads((out / "overlays.counts.json").read_text())
    check(ov["velix_cycling"] >= sm.get("cycle_ways", 1), f"cycle infrastructure ways: {ov['velix_cycling']} (≥ {sm.get('cycle_ways', 1)})")
    check(ov["velix_stations"] >= sm.get("stations", 0), f"stations: {ov['velix_stations']} (≥ {sm.get('stations', 0)})")
    for network, want in sm.get("metro_families", {}).items():
        got = {k.split("/")[1]: v["family"] for k, v in ov["metro_lines"].items() if k.startswith(f"{network}/")}
        check(got == want, f"{network} metro families: {got}")

    rt = sqlite3.connect(out / "routes.sqlite")
    ev = [r[0] for r in rt.execute("SELECT DISTINCT eurovelo FROM routes WHERE eurovelo IS NOT NULL")]
    for n in sm.get("eurovelo", []):
        check(n in ev, f"EuroVelo {n} present (found EV {sorted(ev)})")
    n_routes = rt.execute("SELECT count(*) FROM routes").fetchone()[0]
    check(n_routes >= sm.get("routes", 1), f"cycle routes: {n_routes} (≥ {sm.get('routes', 1)})")

    tr = sqlite3.connect(out / "transit.sqlite")
    cols = {r[1] for r in tr.execute("PRAGMA table_info(trips)")}
    check("bikes_allowed" in cols, "trips carry the GTFS bikes_allowed flag column")
    if cfg["transit"]["feeds"]:
        start_date = dt.date.fromisoformat(tr.execute("SELECT value FROM meta WHERE key='window_start'").fetchone()[0])
        start = int(start_date.strftime("%Y%m%d"))
        week_end = int((start_date + dt.timedelta(days=7)).strftime("%Y%m%d"))
        for t in sm.get("trains", []):
            pair = tr.execute("""
                SELECT count(DISTINCT a.trip) FROM stop_times a
                JOIN stops sa ON sa.id = a.stop JOIN stop_times b ON b.trip = a.trip AND b.seq > a.seq
                JOIN stops sb ON sb.id = b.stop JOIN trips t ON t.id = a.trip
                JOIN service_dates d ON d.service = t.service AND d.date BETWEEN ? AND ?
                WHERE sa.name LIKE ? AND sb.name LIKE ?""", (start, week_end, t["from"] + "%", t["to"] + "%")).fetchone()[0]
            check(pair > 0, f"trains {t['from']} → {t['to']} in the first week: {pair}")
        for route, minimum in sm.get("metro_stops", {}).items():
            n = tr.execute("""SELECT count(DISTINCT st.stop) FROM stop_times st JOIN trips t ON t.id = st.trip
                              WHERE t.route = ?""", (route,)).fetchone()[0]
            check(n >= minimum, f"metro {route} stops: {n} (≥ {minimum})")
        if feed := sm.get("metro_feed"):
            month_in = int((start_date + dt.timedelta(days=30)).strftime("%Y%m%d"))
            later = tr.execute("SELECT count(*) FROM service_dates WHERE service LIKE ? AND date >= ?",
                               (f"{feed}:%", month_in)).fetchone()[0]
            check(later > 0, f"metro service still covered a month in: {later} service-days")
        rules = dict(tr.execute("SELECT operator, count(*) FROM bike_rules GROUP BY operator"))
        check(all(rules.get(o, 0) > 0 for o in sm.get("bike_rule_operators", [])), f"bike rules per operator: {rules}")

    # City area (M8 "destination outside the city" trigger).
    from shapely.geometry import Point, shape
    city = shape(json.loads((out / "city.geojson").read_text())["features"][0]["geometry"])
    if "city_in" in sm:
        check(city.contains(Point(*sm["city_in"])) and not city.contains(Point(*sm["city_out"])),
              f"city area holds {sm['city_in']}, not {sm['city_out']}")

    log(f"{len(fails)} failures")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
