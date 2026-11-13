"""NeTEx (Italian profile, levels 1+) → a GTFS-shaped zip that stages/transit.py reads like any other feed.

Italy publishes every operator's timetable as NeTEx on its National Access Point (NAP MMTIS, cciss.it/nap): Trenitalia
nationally, Trenord, ATM, GTT… through the regional access points (Filippo, 2 Nov: national sources, not per-city
feeds). A feed in the region config says where:

    - id: trenord
      format: netex
      nap: {dataset: 5486, asset: TRENORD}    # the dataset's asset whose name holds this text
      modes: [rail]

Only the journeys of `modes` are kept (a city file is mostly buses). Streams the XML: GTT's is ≈ 1 GB.
Stops: a ScheduledStopPoint with its own location, else the Quay or StopPlace it is assigned to; the StopPlace is the
parent station. Days: DayTypeAssignment → UicOperatingPeriod bits, a dated OperatingPeriod with the DayType's
weekdays, or a single Date."""
import csv
import datetime as dt
import gzip
import io
import re
import http.client
import time
import urllib.request
import xml.etree.ElementTree as ET
import zipfile
from collections import defaultdict

NS = "{http://www.netex.org.uk/netex}"
ROUTE_TYPE = {"rail": 2, "metro": 1, "tram": 0, "bus": 3, "funicular": 7, "cableway": 6}
WEEKDAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
NAP = "https://www.cciss.it/nap/mmtis/public"


def nap_asset_url(dataset: int, asset: str) -> str:
    """The download URL of the dataset's asset whose name contains `asset` (asset ids change when a file is replaced)."""
    req = urllib.request.Request(f"{NAP}/en/catalog/Dataset/{dataset}", headers={"User-Agent": "Velix pipeline"})
    # The NAP cuts responses off mid-way, the dataset page too (Lombardy, CI 12 Nov): retried like the downloads.
    for attempt in range(1, 9):
        try:
            html = urllib.request.urlopen(req, timeout=60).read().decode("utf-8", "replace")
            break
        except (OSError, http.client.HTTPException) as e:
            if attempt == 8:
                raise
            print(f"[transit] NAP dataset {dataset} page failed ({e!r}), retrying ({attempt}/7)", flush=True)
            time.sleep(min(120, 30 * attempt))
    found = [(i, n) for i, n in re.findall(r'catalog/Asset/(\d+)">([^<]+)<', html) if asset.lower() in n.lower()]
    if len(found) != 1:
        raise RuntimeError(f"NAP dataset {dataset}: {len(found)} assets match {asset!r}: {found}")
    return f"{NAP}/api/v1/download/blob/Asset/{found[0][0]}/resource"


def _t(el, path):
    x = el.find(path)
    return x.text.strip() if x is not None and x.text else ""


def _ref(el, path):
    x = el.find(path)
    return x.get("ref") if x is not None else None


SMALL = {"di", "da", "de", "del", "della", "dei", "delle", "la", "il", "le", "e", "in", "sul", "sulla", "al", "alla"}


def nice(name: str) -> str:
    """Names in capitals ("TORINO PORTA NUOVA", "P.TA VENEZIA") in title case, keeping short abbreviations ("FS")."""
    if not name or name != name.upper() or not any(c.isalpha() for c in name):
        return name
    out = []
    for i, w in enumerate(name.split(" ")):
        lw = w.lower()
        if i > 0 and lw in SMALL:
            out.append(lw)
        elif len(w) <= 2 and w.isalpha():
            out.append(w)
        else:
            out.append("-".join(p[:1].upper() + p[1:].lower() for p in w.split("-")))
    return " ".join(out)


def _date(s: str) -> dt.date:
    return dt.date.fromisoformat(s[:10])


def _secs(clock: str, offset: str) -> int:
    """Seconds after midnight of an xsd:time, `offset` days later. The clock is local time; a zone suffix
    (TPER, 2 Nov: `08:15:00+01:00`) and fractional seconds are dropped."""
    h, m, s = (int(x) for x in re.match(r"(\d+):(\d+):(\d+)", clock.strip()).groups())
    return (int(offset or 0) * 24 + h) * 3600 + m * 60 + s


def _gtfs_time(sec: int) -> str:
    return f"{sec // 3600:02d}:{sec % 3600 // 60:02d}:{sec % 60:02d}"


def route_key(short: str, renames: dict[str, str]) -> tuple[str, int | None]:
    """A line's public name and direction: ATM's "M1 A" / "M1 R" are one M1 each way, Trenitalia's "0083_REG" is REG,
    and the feed's renames apply (GTT's METRO is M1)."""
    s = re.sub(r"^\d+_", "", short.strip())
    d = None
    m = re.match(r"^(.*\S) ([AR])$", s)
    if m:
        s, d = m.group(1), 0 if m.group(2) == "A" else 1
    return renames.get(s, s), d


def convert(xml_stream, modes: set[str], renames: dict[str, str] | None = None, keep: list[str] | None = None) -> bytes:
    """Read one NeTEx publication, return a GTFS zip (routes, trips, stops, stop_times, calendar_dates). `keep`: only
    these line names (after `route_key`), e.g. Trenitalia's regional and Intercity categories."""
    renames = renames or {}
    lines, line_of_route, pattern_line, spjp_ssp = {}, {}, {}, {}
    ssp, assign, quays, places = {}, {}, {}, {}
    day_weekdays, assignments, uic, periods = {}, defaultdict(list), {}, {}
    journeys = []
    for _, el in ET.iterparse(xml_stream, events=("end",)):
        tag = el.tag[len(NS):] if el.tag.startswith(NS) else el.tag
        if tag == "Line":
            lines[el.get("id")] = {"name": _t(el, f"{NS}Name"), "short": _t(el, f"{NS}PublicCode") or _t(el, f"{NS}ShortName"),
                                   "mode": _t(el, f"{NS}TransportMode"),
                                   "color": _t(el, f"{NS}Presentation/{NS}Colour")}
            el.clear()
        elif tag == "Route":
            line_of_route[el.get("id")] = _ref(el, f"{NS}LineRef")
        elif tag == "ServiceJourneyPattern":
            pattern_line[el.get("id")] = (_ref(el, f"{NS}RouteView/{NS}LineRef") or
                                          line_of_route.get(_ref(el, f"{NS}RouteRef")))
            for p in el.iter(f"{NS}StopPointInJourneyPattern"):
                spjp_ssp[p.get("id")] = _ref(p, f"{NS}ScheduledStopPointRef")
            el.clear()
        elif tag == "ScheduledStopPoint":
            lon, lat = _t(el, f"{NS}Location/{NS}Longitude"), _t(el, f"{NS}Location/{NS}Latitude")
            ssp[el.get("id")] = (nice(_t(el, f"{NS}Name")), float(lat) if lat else None, float(lon) if lon else None)
            el.clear()
        elif tag == "PassengerStopAssignment":
            s = _ref(el, f"{NS}ScheduledStopPointRef")
            assign[s] = (_ref(el, f"{NS}QuayRef"), _ref(el, f"{NS}StopPlaceRef"))
            el.clear()
        elif tag == "Quay":
            lon, lat = _t(el, f"{NS}Centroid/{NS}Location/{NS}Longitude"), _t(el, f"{NS}Centroid/{NS}Location/{NS}Latitude")
            quays[el.get("id")] = (nice(_t(el, f"{NS}Name")), float(lat) if lat else None, float(lon) if lon else None)
        elif tag == "StopPlace":
            lon, lat = _t(el, f"{NS}Centroid/{NS}Location/{NS}Longitude"), _t(el, f"{NS}Centroid/{NS}Location/{NS}Latitude")
            places[el.get("id")] = (nice(_t(el, f"{NS}Name")), float(lat) if lat else None, float(lon) if lon else None,
                                    [q.get("id") for q in el.iter(f"{NS}Quay")])
            el.clear()
        elif tag == "DayType":
            days = _t(el, f"{NS}properties/{NS}PropertyOfDay/{NS}DaysOfWeek").split()
            day_weekdays[el.get("id")] = {WEEKDAYS.index(d) for d in days if d in WEEKDAYS} or set(range(7))
            el.clear()
        elif tag == "DayTypeAssignment":
            if _t(el, f"{NS}isAvailable") != "false":
                assignments[_ref(el, f"{NS}DayTypeRef")].append((_ref(el, f"{NS}OperatingPeriodRef") or
                                                                _ref(el, f"{NS}UicOperatingPeriodRef"), _t(el, f"{NS}Date")))
            el.clear()
        elif tag == "UicOperatingPeriod":
            uic[el.get("id")] = (_date(_t(el, f"{NS}FromDate")), _t(el, f"{NS}ValidDayBits"))
            el.clear()
        elif tag == "OperatingPeriod":
            periods[el.get("id")] = (_date(_t(el, f"{NS}FromDate")), _date(_t(el, f"{NS}ToDate")))
            el.clear()
        elif tag == "ServiceJourney":
            pattern = _ref(el, f"{NS}ServiceJourneyPatternRef")
            line = _ref(el, f"{NS}LineRef") or pattern_line.get(pattern)
            mode = _t(el, f"{NS}TransportMode") or lines.get(line, {}).get("mode", "")
            if mode in modes and line:
                times = []
                for p in el.iter(f"{NS}TimetabledPassingTime"):
                    arr = _t(p, f"{NS}ArrivalTime") or _t(p, f"{NS}DepartureTime")
                    dep = _t(p, f"{NS}DepartureTime") or arr
                    stop = spjp_ssp.get(_ref(p, f"{NS}StopPointInJourneyPatternRef"))
                    if stop and arr:
                        times.append((stop, _secs(arr, _t(p, f"{NS}ArrivalDayOffset") if _t(p, f"{NS}ArrivalTime") else _t(p, f"{NS}DepartureDayOffset")),
                                      _secs(dep, _t(p, f"{NS}DepartureDayOffset") if _t(p, f"{NS}DepartureTime") else _t(p, f"{NS}ArrivalDayOffset"))))
                if len(times) > 1:
                    journeys.append({"id": el.get("id"), "line": line, "mode": mode,
                                     "number": _t(el, f"{NS}PublicCode") or _t(el, f"{NS}Name") or _t(el, f"{NS}PrivateCode"),
                                     "days": tuple(sorted(r.get("ref") for r in el.iter(f"{NS}DayTypeRef"))), "times": times})
            el.clear()

    def day_dates(day: str) -> set[dt.date]:
        out = set()
        for period, date in assignments.get(day, []):
            if date:
                out.add(_date(date))
            elif period in uic:
                start, bits = uic[period]
                out |= {start + dt.timedelta(days=i) for i, b in enumerate(bits) if b == "1"}
            elif period in periods:
                a, b = periods[period]
                wd = day_weekdays.get(day, set(range(7)))
                out |= {a + dt.timedelta(days=i) for i in range((b - a).days + 1) if (a + dt.timedelta(days=i)).weekday() in wd}
        return out

    def stop_row(s):
        """(stop_id, name, lat, lon, parent) for a ScheduledStopPoint, positioned by itself or its Quay / StopPlace."""
        name, lat, lon = ssp.get(s, ("", None, None))
        quay, place = assign.get(s, (None, None))
        if quay and not place:
            place = next((p for p, v in places.items() if quay in v[3]), None)
        if lat is None and quay in quays:
            _, lat, lon = quays[quay]
        if lat is None and place in places:
            _, lat, lon, _ = places[place]
        return s, name or (places[place][0] if place in places else ""), lat, lon, place

    services, used_stops, used_lines = {}, {}, {}
    trips, stop_times = [], []
    for j in journeys:
        short, direction = route_key(lines[j["line"]]["short"], renames)
        if keep and short not in keep:
            continue
        if j["days"] not in services:
            services[j["days"]] = (f"s{len(services) + 1}", set().union(*(day_dates(d) for d in j["days"])) if j["days"] else set())
        sid, dates = services[j["days"]]
        if not dates:
            continue
        rows = [stop_row(s) for s, _, _ in j["times"]]
        if any(r[2] is None for r in rows):
            continue
        for r in rows:
            used_stops[r[0]] = r
        rid = short or j["line"]          # both directions of a line are one route
        used_lines.setdefault(rid, j["line"])
        last = rows[-1][1]
        trips.append((rid, sid, j["id"], last, j["number"], "" if direction is None else direction))
        stop_times += [(j["id"], _gtfs_time(a), _gtfs_time(d), s, i + 1) for i, (s, a, d) in enumerate(j["times"])]

    parents = {r[4] for r in used_stops.values() if r[4] in places}
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        def write(name, header, rows):
            s = io.StringIO()
            w = csv.writer(s, lineterminator="\n")
            w.writerow(header)
            w.writerows(rows)
            z.writestr(name, s.getvalue())
        write("routes.txt", ["route_id", "route_short_name", "route_long_name", "route_type", "route_color"],
              [(rid, route_key(lines[lid]["short"], renames)[0], lines[lid]["name"], ROUTE_TYPE.get(lines[lid]["mode"], 3),
                lines[lid]["color"].lstrip("#")) for rid, lid in sorted(used_lines.items())])
        write("trips.txt", ["route_id", "service_id", "trip_id", "trip_headsign", "trip_short_name", "direction_id"], trips)
        write("stops.txt", ["stop_id", "stop_name", "stop_lat", "stop_lon", "location_type", "parent_station"],
              [(s, n, f"{la:.6f}", f"{lo:.6f}", 0, p if p in parents else "") for s, n, la, lo, p in used_stops.values()] +
              [(p, places[p][0], f"{places[p][1]:.6f}", f"{places[p][2]:.6f}", 1, "") for p in sorted(parents)
               if places[p][1] is not None])
        write("stop_times.txt", ["trip_id", "arrival_time", "departure_time", "stop_id", "stop_sequence"], stop_times)
        write("calendar_dates.txt", ["service_id", "date", "exception_type"],
              [(sid, d.strftime("%Y%m%d"), 1) for sid, dates in services.values() for d in sorted(dates)])
    return buf.getvalue()


def open_netex(path):
    """A NeTEx file as a binary stream: gzip, a zip holding one XML, or plain XML."""
    with open(path, "rb") as f:
        head = f.read(4)
    if head[:2] == b"\x1f\x8b":
        return gzip.open(path, "rb")
    if head == b"PK\x03\x04":
        z = zipfile.ZipFile(path)
        return z.open(next(n for n in z.namelist() if n.lower().endswith(".xml")))
    return open(path, "rb")
