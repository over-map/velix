"""Stage 6: train + metro timetables for the bike + transit suggestion → out/<region>/transit.sqlite

- Keeps only the configured route types per feed (Trenord rail, ATM metro); no surface buses or trams.
- Keeps stops inside the region polygon (and their parent stations), stop_times at those stops.
- Service window: N days from the OSM extract date (deterministic for a given set of inputs).
- A feed whose service ends inside the window is extended by repeating its last full week, flagged `projected`
  (ATM publishes about two weeks of metro timetable at a time).
- Bikes on board, universal order of evidence (the app applies it per trip):
    1. the feed's own trips.txt `bikes_allowed` (1 = yes, 2 = no), stored in trips.bikes_allowed (0 = not given);
    2. curated rules from the region's `bike_rules` file (by feed and route), for feeds without the field;
    3. otherwise `check`: the rider is told to check with the operator.
"""
import csv
import datetime as dt
import io
import json
import sqlite3
import urllib.request
import zipfile
from collections import defaultdict

import yaml
from shapely.geometry import Point, shape
from shapely.prepared import prep

from common import PIPELINE, cache_dir, load_config, log, out_dir, write_json

UA = "velix-region-pack/1.0 (+https://github.com/over-map/velix)"


def rows(z: zipfile.ZipFile, name: str):
    if name not in z.namelist():
        return
    with z.open(name) as f:
        yield from csv.DictReader(io.TextIOWrapper(f, "utf-8-sig"))


def seconds(hms: str) -> int:
    h, m, s = (int(x) for x in hms.strip().split(":"))
    return h * 3600 + m * 60 + s


def ymd(s: str) -> dt.date:
    return dt.date(int(s[:4]), int(s[4:6]), int(s[6:8]))


def fetch(feed: dict) -> zipfile.ZipFile:
    path = cache_dir() / "gtfs" / f"{feed['id']}.zip"
    path.parent.mkdir(exist_ok=True)
    fresh = path.exists() and (dt.datetime.now().timestamp() - path.stat().st_mtime) < 20 * 3600
    if not fresh:
        log(f"download {feed['id']}")
        req = urllib.request.Request(feed["url"], headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=300) as r, open(path.with_suffix(".part"), "wb") as f:
            while chunk := r.read(1 << 20):
                f.write(chunk)
        path.with_suffix(".part").rename(path)
    return zipfile.ZipFile(path)


def active_dates(z: zipfile.ZipFile, services: set[str]) -> dict[str, set[dt.date]]:
    """service_id → dates it runs (calendar.txt + calendar_dates.txt)."""
    dates: dict[str, set[dt.date]] = defaultdict(set)
    days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    for r in rows(z, "calendar.txt"):
        sid = r["service_id"]
        if sid not in services:
            continue
        d, end = ymd(r["start_date"]), ymd(r["end_date"])
        while d <= end:
            if r[days[d.weekday()]] == "1":
                dates[sid].add(d)
            d += dt.timedelta(days=1)
    for r in rows(z, "calendar_dates.txt"):
        sid = r["service_id"]
        if sid not in services:
            continue
        d = ymd(r["date"])
        (dates[sid].add if r["exception_type"] == "1" else dates[sid].discard)(d)
    return dates


def window_dates(dates: dict[str, set[dt.date]], start: dt.date, days: int):
    """(service_id, date, projected) rows for [start, start+days). Repeats the feed's last full week if it ends early."""
    end = start + dt.timedelta(days=days)
    last = max((d for ds in dates.values() for d in ds), default=start)
    out = [(sid, d, 0) for sid, ds in dates.items() for d in ds if start <= d < end]
    if last < end - dt.timedelta(days=1):
        template_start = last - dt.timedelta(days=6)
        by_weekday: dict[int, list[str]] = defaultdict(list)
        for sid, ds in dates.items():
            for d in ds:
                if template_start <= d <= last:
                    by_weekday[d.weekday()].append(sid)
        d = max(last + dt.timedelta(days=1), start)
        while d < end:
            out += [(sid, d, 1) for sid in by_weekday.get(d.weekday(), [])]
            d += dt.timedelta(days=1)
    return sorted(out), last


def main():
    cfg = load_config()
    out = out_dir(cfg)
    region = prep(shape(json.loads((out / "region.geojson").read_text())["features"][0]["geometry"]))
    osm_date = json.loads((out / "sources" / "osm.json").read_text())["date"][:10]
    start = dt.date.fromisoformat(osm_date)
    days = cfg["transit"]["days"]
    rules = yaml.safe_load((PIPELINE / "config" / cfg["transit"]["bike_rules"]).read_text())

    path = out / "transit.sqlite"
    if path.exists():
        path.unlink()
    db = sqlite3.connect(path)
    db.executescript("""
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE feeds (id TEXT PRIMARY KEY, name TEXT, licence TEXT, attribution TEXT,
                            last_service_date TEXT, projected_from TEXT);
        CREATE TABLE routes (id TEXT PRIMARY KEY, feed TEXT NOT NULL, short_name TEXT, long_name TEXT,
                             mode TEXT NOT NULL, color TEXT);                          -- mode: rail | metro
        CREATE TABLE stops (id TEXT PRIMARY KEY, feed TEXT NOT NULL, name TEXT NOT NULL, lat REAL, lon REAL,
                            parent TEXT, is_station INTEGER NOT NULL);
        CREATE TABLE trips (id TEXT PRIMARY KEY, feed TEXT NOT NULL, route TEXT NOT NULL, service TEXT NOT NULL,
                            headsign TEXT, short_name TEXT, direction INTEGER,
                            bikes_allowed INTEGER NOT NULL);  -- GTFS: 1 yes, 2 no, 0 not given (then bike_rules)
        CREATE TABLE stop_times (trip TEXT NOT NULL, seq INTEGER NOT NULL, stop TEXT NOT NULL,
                                 arr INTEGER NOT NULL, dep INTEGER NOT NULL);           -- seconds after local midnight
        CREATE TABLE service_dates (service TEXT NOT NULL, date INTEGER NOT NULL, projected INTEGER NOT NULL);
        CREATE TABLE bike_rules (id INTEGER PRIMARY KEY, operator TEXT NOT NULL, routes TEXT NOT NULL,
                                 weekdays TEXT NOT NULL, start INTEGER NOT NULL, "end" INTEGER NOT NULL,
                                 status TEXT NOT NULL, carriage TEXT, note TEXT, source TEXT NOT NULL,
                                 checked TEXT NOT NULL);
    """)
    summary = {}
    for feed in cfg["transit"]["feeds"]:
        fid = feed["id"]
        z = fetch(feed)
        types = {str(t) for t in feed["route_types"]}
        routes = {r["route_id"]: r for r in rows(z, "routes.txt") if r["route_type"] in types}
        trips = {r["trip_id"]: r for r in rows(z, "trips.txt") if r["route_id"] in routes}
        stops_all = {r["stop_id"]: r for r in rows(z, "stops.txt")}
        inside = {sid for sid, s in stops_all.items()
                  if s.get("stop_lat") and region.contains(Point(float(s["stop_lon"]), float(s["stop_lat"])))}
        times, used_stops = [], set()
        for r in rows(z, "stop_times.txt"):
            if r["trip_id"] in trips and r["stop_id"] in inside:
                times.append((f"{fid}:{r['trip_id']}", int(r["stop_sequence"]), f"{fid}:{r['stop_id']}",
                              seconds(r["arrival_time"] or r["departure_time"]),
                              seconds(r["departure_time"] or r["arrival_time"])))
                used_stops.add(r["stop_id"])
        trips_with_times = {t[0] for t in times}
        parents = {stops_all[s].get("parent_station") for s in used_stops} - {"", None}
        services = {trips[t.split(":", 1)[1]]["service_id"] for t in trips_with_times}
        dates, last = window_dates(active_dates(z, services), start, days)
        projected = any(p for _, _, p in dates)
        mode = "metro" if types & {"1", "401", "402"} else "rail"

        db.execute("INSERT INTO feeds VALUES (?,?,?,?,?,?)", (
            fid, feed["name"], feed["licence"], feed["attribution"], last.isoformat(),
            (last - dt.timedelta(days=6)).isoformat() if projected else None))
        db.executemany("INSERT INTO routes VALUES (?,?,?,?,?,?)", sorted(
            (f"{fid}:{rid}", fid, r.get("route_short_name", ""), r.get("route_long_name", ""), mode,
             r.get("route_color", "")) for rid, r in routes.items()))
        db.executemany("INSERT INTO stops VALUES (?,?,?,?,?,?,?)", sorted(
            (f"{fid}:{sid}", fid, s["stop_name"], round(float(s["stop_lat"]), 6), round(float(s["stop_lon"]), 6),
             f"{fid}:{s['parent_station']}" if s.get("parent_station") else None,
             1 if s.get("location_type") == "1" else 0)
            for sid, s in stops_all.items() if sid in used_stops or sid in parents))
        db.executemany("INSERT INTO trips VALUES (?,?,?,?,?,?,?,?)", sorted(
            (f"{fid}:{tid}", fid, f"{fid}:{t['route_id']}", f"{fid}:{t['service_id']}", t.get("trip_headsign", ""),
             t.get("trip_short_name", ""), int(t["direction_id"]) if t.get("direction_id") else None,
             int(t["bikes_allowed"]) if t.get("bikes_allowed") in {"1", "2"} else 0)
            for tid, t in trips.items() if f"{fid}:{tid}" in trips_with_times))
        db.executemany("INSERT INTO stop_times VALUES (?,?,?,?,?)", sorted(times))
        db.executemany("INSERT INTO service_dates VALUES (?,?,?)",
                       [(f"{fid}:{sid}", int(d.strftime("%Y%m%d")), p) for sid, d, p in dates])
        flagged = sum(1 for tid, t in trips.items() if f"{fid}:{tid}" in trips_with_times and t.get("bikes_allowed") in {"1", "2"})
        summary[fid] = {"routes": len(routes), "trips": len(trips_with_times), "trips_with_bike_flag": flagged,
                        "stops": len(used_stops),
                        "stop_times": len(times), "last_service_date": last.isoformat(), "projected": projected}
        log(f"{fid}: {summary[fid]}")

    for i, r in enumerate(rules, start=1):
        h0, m0 = (int(x) for x in r["from"].split(":"))
        h1, m1 = (int(x) for x in r["until"].split(":"))
        db.execute("INSERT INTO bike_rules VALUES (?,?,?,?,?,?,?,?,?,?,?)", (
            i, r["operator"], json.dumps(r["routes"]), r["weekdays"], h0 * 3600 + m0 * 60, h1 * 3600 + m1 * 60,
            r["status"], r.get("carriage"), r.get("note"), r["source"], str(r["checked"])))
    db.executescript("""
        CREATE INDEX stop_times_stop_dep ON stop_times(stop, dep);
        CREATE INDEX stop_times_trip_seq ON stop_times(trip, seq);
        CREATE INDEX service_dates_date ON service_dates(date, service);
        CREATE INDEX stops_parent ON stops(parent);
    """)
    db.executemany("INSERT INTO meta VALUES (?,?)", [
        ("schema", "1"), ("region", cfg["region"]["id"]), ("window_start", start.isoformat()), ("window_days", str(days)),
        ("timezone", cfg["region"]["timezone"]),
        ("bikes_precedence", "trips.bikes_allowed > bike_rules > check")])
    db.commit()
    db.execute("VACUUM")
    db.close()
    write_json(out / "transit.counts.json", summary)
    (out / "sources").mkdir(exist_ok=True)
    for feed in cfg["transit"]["feeds"]:
        write_json(out / "sources" / f"transit-{feed['id']}.json", {
            "id": f"transit-{feed['id']}", "name": feed["name"], "url": feed["url"],
            "date": dt.date.fromtimestamp((cache_dir() / "gtfs" / f"{feed['id']}.zip").stat().st_mtime).isoformat(),
            "service_until": summary[feed["id"]]["last_service_date"], "licence": feed["licence"],
            "attribution": feed["attribution"]})


if __name__ == "__main__":
    main()
