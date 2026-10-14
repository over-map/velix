"""Stage 9b: smoke tests on the built pack (M3 adds the real golden route tests)."""
import datetime as dt
import json
import sqlite3
import sys

from common import load_config, log, out_dir

# trip id → (min km, max km) with the City profile
TRIPS = {
    "porta-venezia-politecnico": (1.8, 3.5),
    "duomo-bicocca": (5, 9),
    "darsena-politecnico": (5, 9),
    "porta-venezia-san-siro": (6, 11),
    "rho-fiera-san-donato": (20, 33),
    "duomo-bergamo-citta-alta": (45, 70),
}
MIN_HAZARDS = {"tram": 500, "along": 200, "cobbles": 1000, "steps": 1000, "gap": 1000, "lane": 1000, "dismount": 1000,
               "door": 1}


def near(db, table, lat, lon, metres, where="1"):
    d = metres / 111_000
    return db.execute(
        f"SELECT count(*) FROM {table} t JOIN {table}_rtree r ON r.id = t.id "
        f"WHERE r.min_lon <= ? AND r.max_lon >= ? AND r.min_lat <= ? AND r.max_lat >= ? AND {where}",
        (lon + d, lon - d, lat + d, lat - d)).fetchone()[0]


def main() -> int:
    cfg = load_config()
    out = out_dir(cfg)
    fails = []

    def check(ok, msg):
        log(("ok   " if ok else "FAIL ") + msg)
        if not ok:
            fails.append(msg)

    for trip, (lo, hi) in TRIPS.items():
        r = json.loads((out / "smoke" / f"{trip}.json").read_text())
        km = r.get("trip", {}).get("summary", {}).get("length")
        check(km is not None and lo <= km <= hi, f"route {trip}: {km} km (expected {lo}–{hi})")

    hz = sqlite3.connect(out / "hazards.sqlite")
    counts = dict(hz.execute("SELECT type, count(*) FROM hazards GROUP BY type"))
    for kind, minimum in MIN_HAZARDS.items():
        check(counts.get(kind, 0) >= minimum, f"hazards {kind}: {counts.get(kind, 0)} (≥ {minimum})")
    check(near(hz, "hazards", 45.4746, 9.2050, 400, "t.type IN ('tram','along')") > 0,
          "tram rails near Porta Venezia")
    check(near(hz, "hazards", 45.4720, 9.1870, 150, "t.type = 'cobbles'") > 0, "cobbles in Brera (Via Fiori Chiari)")

    rt = sqlite3.connect(out / "routes.sqlite")
    ev = [r[0] for r in rt.execute("SELECT DISTINCT eurovelo FROM routes WHERE eurovelo IS NOT NULL")]
    check(5 in ev, f"EuroVelo 5 present (found EV {sorted(ev)})")
    check(rt.execute("SELECT count(*) FROM routes").fetchone()[0] >= 100, "≥ 100 cycle routes")

    tr = sqlite3.connect(out / "transit.sqlite")
    start_date = dt.date.fromisoformat(tr.execute("SELECT value FROM meta WHERE key='window_start'").fetchone()[0])
    start = int(start_date.strftime("%Y%m%d"))
    week_end = int((start_date + dt.timedelta(days=7)).strftime("%Y%m%d"))
    pair = tr.execute("""
        SELECT count(DISTINCT a.trip) FROM stop_times a
        JOIN stops sa ON sa.id = a.stop JOIN stop_times b ON b.trip = a.trip AND b.seq > a.seq
        JOIN stops sb ON sb.id = b.stop JOIN trips t ON t.id = a.trip
        JOIN service_dates d ON d.service = t.service AND d.date BETWEEN ? AND ?
        WHERE sa.name LIKE 'Milano Centrale%' AND sb.name LIKE 'Monza%'""", (start, week_end)).fetchone()[0]
    check(pair > 0, f"trains Milano Centrale → Monza in the first week: {pair}")
    m1 = tr.execute("""SELECT count(DISTINCT st.stop) FROM stop_times st JOIN trips t ON t.id = st.trip
                       JOIN routes r ON r.id = t.route WHERE r.id = 'atm:M1'""").fetchone()[0]
    check(m1 >= 30, f"metro M1 stops: {m1}")
    month_in = int((start_date + dt.timedelta(days=30)).strftime("%Y%m%d"))
    later = tr.execute("SELECT count(*) FROM service_dates WHERE service LIKE 'atm:%' AND date >= ?",
                       (month_in,)).fetchone()[0]
    check(later > 0, f"metro service still covered a month in: {later} service-days")
    rules = dict(tr.execute("SELECT operator, count(*) FROM bike_rules GROUP BY operator"))
    check(rules.get("atm", 0) > 0 and rules.get("trenord", 0) > 0, f"bike rules per operator: {rules}")

    log(f"{len(fails)} failures")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
