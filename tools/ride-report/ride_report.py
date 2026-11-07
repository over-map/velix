#!/usr/bin/env python3
"""M7 ride report: reads Velix ride logs (Documents/rides/*.jsonl, RideLog.swift) and MetricKit diagnostics
(Documents/diagnostics/*.json) pulled from the phone, and checks the M7 acceptance criteria per ride.

    xcrun devicectl device copy from --device <id> --domain-type appDataContainer \\
        --domain-identifier io.github.over-map.velix --source Documents/rides --destination <dir>/rides
    python3 tools/ride-report/ride_report.py <dir>/rides [--diagnostics <dir>/diagnostics] [-o report.md]

Privacy (public repo): the report prints no coordinates; distances, times, counts and spoken texts only.
Standard library only.
"""
from __future__ import annotations

import argparse
import glob
import json
import math
import os
import statistics
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone

# ---- acceptance thresholds (docs/DECISIONS.md, M7 real rides) ----
ON_TIME_MIN_M, ON_TIME_MAX_M = 25.0, 75.0   # a hazard alert with this much road left
ON_TIME_MIN_S = 5.0                          # … and at least this many seconds ahead at the speed then
PASS_WITHIN_M = 15.0                         # the rider passed a hazard when a fix came this close
BURST_COUNT, BURST_WINDOW_S = 3, 60.0        # this many accepted reroutes in the window is a burst
GAP_S = 5.0                                  # a longer gap between fixes is a location gap
GOOD_ACC_M = 30.0                            # fixes used for distances


def dist(a: tuple[float, float], b: tuple[float, float]) -> float:
    r = 6371008.8
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def hms(t: float) -> str:
    return datetime.fromtimestamp(t, timezone.utc).astimezone().strftime("%H:%M:%S")


def mmss(s: float) -> str:
    s = int(round(s))
    return f"{s // 60}:{s % 60:02d}"


@dataclass
class Ride:
    name: str
    fixes: list[dict] = field(default_factory=list)
    events: list[dict] = field(default_factory=list)

    @staticmethod
    def load(path: str) -> "Ride":
        ride = Ride(os.path.basename(path).removesuffix(".jsonl"))
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    o = json.loads(line)
                except json.JSONDecodeError:
                    continue   # a line cut by a crash
                (ride.events if "e" in o else ride.fixes).append(o)
        return ride

    def of(self, kind: str) -> list[dict]:
        return [e for e in self.events if e["e"] == kind]

    @property
    def start(self) -> dict | None:
        s = self.of("start")
        return s[0] if s else None

    @property
    def simulated(self) -> bool:
        s = self.start
        if s is not None and "sim" in s:
            return bool(s["sim"])
        # Logs from before the flag: the simulator's fixes all have 5.0 m accuracy.
        accs = [f.get("acc") for f in self.fixes if f.get("acc") is not None]
        return len(accs) >= 10 and len(set(accs)) == 1 and accs[0] == 5

    @property
    def span(self) -> tuple[float, float]:
        ts = [o["t"] for o in self.fixes + self.events if "t" in o]
        return (min(ts), max(ts)) if ts else (0.0, 0.0)

    def good(self) -> list[dict]:
        return [f for f in self.fixes if 0 <= f.get("acc", -1) <= GOOD_ACC_M and not f.get("train")]

    def meters(self) -> float:
        g = self.good()
        return sum(dist((a["lat"], a["lon"]), (b["lat"], b["lon"])) for a, b in zip(g, g[1:]))

    def moving_seconds(self) -> float:
        g = self.good()
        out = 0.0
        for a, b in zip(g, g[1:]):
            dt = b["t"] - a["t"]
            if dt > 0 and dist((a["lat"], a["lon"]), (b["lat"], b["lon"])) / dt >= 1.0:
                out += dt
        return out

    def state_at(self, t: float) -> str:
        """The app's state at `t` from its lifecycle events: 'active', 'background', 'locked'."""
        locked, background = False, False
        for e in self.events:
            if e["t"] > t:
                break
            if e["e"] == "app":
                s = e.get("s")
                if s == "locked": locked = True
                elif s == "unlocked": locked = False
                elif s == "background": background = True
                elif s == "active": background = False
        return "locked" if locked else "background" if background else "active"


# ---- checks: each returns (ok: bool | None, summary, details[]) ; None = not measured ----

def check_crash(ride: Ride, crashes: list[tuple[float, float, str]]) -> tuple[bool | None, str, list[str]]:
    begin, end = ride.span
    hits = [name for (b, e, name) in crashes if b <= end + 600 and e >= begin - 60]
    ended = [e.get("s") for e in ride.of("end")]
    terminated = any(e.get("s") == "terminate" for e in ride.of("app"))
    details = [f"crash report: {n}" for n in hits]
    if hits:
        return False, f"{len(hits)} crash report(s) in the ride's time", details
    if not ended or ended[-1] == "leg":
        why = "app terminated" if terminated else "log stops without an end (crash or killed by iOS?)"
        return (None if terminated else False), why, details
    return True, f"ended ({ended[-1]})", details


def planned_hazards(ride: Ride) -> list[dict]:
    """Every hazard on every route ridden (start and reroutes), once each."""
    seen, out = set(), []
    for r in ride.of("route"):
        for h in r.get("hazards", []):
            key = (h["type"], round(h["lat"], 4), round(h["lon"], 4))
            if key not in seen:
                seen.add(key)
                out.append(h)
    return out


def check_hazards(ride: Ride) -> tuple[bool | None, str, list[str]]:
    planned = planned_hazards(ride)
    if not ride.of("route"):
        return None, "no route events (log from before 6 Nov)", []
    good = ride.good()
    alerts = ride.of("hazard")
    used: set[int] = set()
    on_time = short = missed = passed = 0
    details = []
    for h in planned:
        hp = (h["lat"], h["lon"])
        near = [(dist((f["lat"], f["lon"]), hp), f) for f in good]
        close = [(d, f) for d, f in near if d <= PASS_WITHIN_M]
        if not close:
            continue   # not on the way any more (rerouted, or the ride ended first)
        passed += 1
        tp = min(close, key=lambda x: x[0])[1]["t"]
        best = None
        for i, a in enumerate(alerts):
            if i in used or a["type"] != h["type"] or a["t"] > tp + 2 or a["t"] < tp - 180:
                continue
            # the alert's distance left should match how far the rider was from this hazard then
            if abs(dist((a["lat"], a["lon"]), hp) - a["d"]) <= max(40.0, 0.5 * a["d"]):
                best = (i, a)
                break
        label = f"{h['type']} at {h['along']:.0f} m along"
        if best is None:
            missed += 1
            details.append(f"MISSED {label}: passed at {hms(tp)} with no alert")
            continue
        used.add(best[0])
        a = best[1]
        secs = a.get("secs") if a.get("secs") is not None else (a["d"] / a["v"] if a.get("v", 0) > 0.5 else None)
        ok = ON_TIME_MIN_M <= a["d"] <= ON_TIME_MAX_M and (secs is None or secs >= ON_TIME_MIN_S)
        on_time += ok
        short += not ok
        when = f"{a['d']:.0f} m" + (f", {secs:.0f} s" if secs is not None else "") + f" ahead ({a.get('gps', '?')} GPS)"
        details.append(f"{'on time' if ok else 'LATE'} {label}: {when}" + ("" if a.get("spoken", True) else ", not spoken (voice mode)"))
    extra = len(alerts) - len(used)
    if extra:
        details.append(f"{extra} alert(s) for hazards not passed (rerouted away, or ended first)")
    if not planned:
        return None, "no hazard alerts on the route (none are announced since 29 Oct: HazardType.onRoute)", details
    if passed == 0:
        return None, f"{len(planned)} alerting hazards on the route, none passed", details
    return missed == 0 and short == 0, f"{on_time}/{passed} on time, {short} late, {missed} missed", details


def check_bursts(ride: Ride) -> tuple[bool | None, str, list[str]]:
    rr = ride.of("reroute")
    accepted = [e["t"] for e in rr if e.get("s") == "accepted"]
    held = sum(1 for e in rr if e.get("s") == "held")
    bursts = []
    for i, t in enumerate(accepted):
        n = sum(1 for u in accepted[i:] if u - t <= BURST_WINDOW_S)
        if n >= BURST_COUNT:
            bursts.append(f"BURST {n} reroutes in {BURST_WINDOW_S:.0f} s from {hms(t)}")
    ms = [e["ms"] for e in rr if e.get("s") == "accepted" and "ms" in e]
    details = list(dict.fromkeys(bursts))
    if ms:
        details.append(f"reroute time: median {statistics.median(ms):.0f} ms, max {max(ms):.0f} ms")
    summary = f"{len(accepted)} accepted, {sum(1 for e in rr if e.get('s') == 'requested')} requested, {held} held by the back-off"
    return (not bursts), summary, details


def check_gaps(ride: Ride) -> tuple[bool | None, str, list[str]]:
    fx = [f for f in ride.fixes if not f.get("train")]
    gaps = []
    for a, b in zip(fx, fx[1:]):
        dt = b["t"] - a["t"]
        if dt > GAP_S:
            stopped = a.get("v", -1) < 1 and b.get("v", -1) < 1
            gaps.append(f"GAP {dt:.0f} s at {hms(a['t'])} ({'stopped' if stopped else 'moving'}, "
                        f"{a.get('v', -1):.1f} → {b.get('v', -1):.1f} m/s, app {ride.state_at(a['t'])})")
    stops = 0
    run = 0.0
    for a, b in zip(fx, fx[1:]):
        if a.get("v", -1) < 1 and b.get("v", -1) < 1:
            run += b["t"] - a["t"]
        else:
            stops += run >= 60
            run = 0.0
    return not gaps, f"{len(gaps)} gaps over {GAP_S:.0f} s; {stops} stops of a minute or more", gaps


def check_failed(ride: Ride) -> tuple[bool | None, str, list[str]]:
    rr = ride.of("reroute")
    failed = [e for e in rr if e.get("s") == "failed"]
    if not failed:
        return None, "no failed reroute (nothing to check)", []
    details, ok = [], True
    for f in failed:
        t = f["t"]
        later = [e for e in rr if e["t"] > t and e.get("s") == "accepted"]
        fixes_after = [x for x in ride.fixes if t < x["t"] <= t + 30]
        ended_soon = any(t < e["t"] <= t + 5 for e in ride.of("end"))
        kept = bool(f.get("kept")) and fixes_after and not ended_soon
        ok &= bool(kept)
        nxt = f"next accepted after {later[0]['t'] - t:.0f} s" if later else "no later reroute"
        details.append(f"{'kept' if kept else 'LOST'} route after failure at {hms(t)} ({f.get('reason', '?')}); {nxt}")
    return ok, f"{len(failed)} failed, the old route kept in {sum(d.startswith('kept') for d in details)}", details


def check_voice(ride: Ride) -> tuple[bool | None, str, list[str]]:
    v = ride.of("voice")
    if not v:
        return None, "no voice events (log from before 6 Nov)", []
    started = [e for e in v if e.get("s") == "started"]
    finished = {(e["text"]) for e in v if e.get("s") == "finished"}
    cancelled = {(e["text"]) for e in v if e.get("s") == "cancelled"}
    locked = [e for e in started if e.get("locked")]
    locked_done = [e for e in locked if e["text"] in finished]
    unfinished = [e for e in started if e["text"] not in finished and e["text"] not in cancelled]
    errors = [e for e in v if e.get("s") == "error"]
    details = [f"not finished: “{e['text']}” at {hms(e['t'])}" for e in unfinished[:10]]
    details += [f"ERROR {e['text']}" for e in errors]
    details += [f"locked: “{e['text']}”" for e in locked_done[:5]]
    summary = f"{len(started)} prompt(s), {len(locked)} with the phone locked ({len(locked_done)} finished), {len(errors)} errors"
    if not locked:
        return None, summary + " (the phone was never locked)", details
    return bool(locked_done) and not errors, summary, details


def check_activity(ride: Ride) -> tuple[bool | None, str, list[str]]:
    a = ride.of("activity")
    if not a:
        return None, "no Live Activity events (log from before 6 Nov)", []
    started = [e["s"] for e in a if e["s"] != "updates"]
    updates = [e for e in a if e["s"] == "updates"]
    locked_updates = sum(e.get("n", 0) for e in updates if ride.state_at(e["t"] - 30) == "locked")
    total = sum(e.get("n", 0) for e in updates)
    ok = "started" in started and total > 0
    return ok, f"{', '.join(started)}; {total} updates, {locked_updates} while locked", []


def health(ride: Ride) -> list[str]:
    h = ride.of("health")
    if not h:
        return ["no health events (log from before 6 Nov)"]
    out = []
    unplugged = [e for e in h if not e.get("charging") and e.get("battery", -1) >= 0]
    if len(unplugged) >= 2 and unplugged[-1]["t"] > unplugged[0]["t"]:
        hours = (unplugged[-1]["t"] - unplugged[0]["t"]) / 3600
        drop = (unplugged[0]["battery"] - unplugged[-1]["battery"]) * 100
        out.append(f"battery {unplugged[0]['battery'] * 100:.0f} → {unplugged[-1]['battery'] * 100:.0f} % unplugged "
                   f"({drop / hours:.0f} %/h)" if hours > 0 else "battery: not enough time")
    elif h and h[0].get("charging"):
        out.append("battery: charging during the ride")
    mb = [e.get("mb", -1) for e in h if e.get("mb", -1) > 0]
    if mb:
        out.append(f"memory peak {max(mb):.0f} MB")
    order = ["nominal", "fair", "serious", "critical"]
    th = [e.get("thermal", "nominal") for e in h]
    out.append(f"thermal peak {max(th, key=lambda x: order.index(x) if x in order else 0)}")
    warnings = [e for e in ride.of("app") if e.get("s") == "memoryWarning"]
    if warnings:
        out.append(f"{len(warnings)} memory warning(s)")
    return out


def map_fps(ride: Ride) -> str | None:
    """Frames the map drew a second, per minute on screen (M10). The first health line (ride start) covers the time
    before the ride, and a locked or background minute draws nothing, so both are left out."""
    h = [e for e in ride.of("health") if "fps" in e][1:]
    on_screen = [e for e in h if ride.state_at(e["t"] - 30) == "active"]
    if not on_screen:
        return None
    fps = sorted(e["fps"] for e in on_screen)
    slow = sum(e.get("slow", 0) for e in on_screen)
    return (f"map {statistics.median(fps):.0f} fps median, worst minute {fps[0]:.0f} fps, "
            f"{slow} slow frame(s) over {len(on_screen)} min on screen")


def launches(path: str) -> str:
    """Launch times from `Documents/diagnostics/launch.jsonl` (PerfLog): median and worst per phase, prewarmed left out."""
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    cold = [r for r in rows if not r.get("prewarmed")]
    if not cold:
        return f"# Velix launches\n\nNo launches in {os.path.basename(path)} ({len(rows)} prewarmed).\n"
    def line(name: str, values: list[float]) -> str:
        return f"| {name} | {statistics.median(values):.0f} | {max(values):.0f} | {len(values)} |"
    out = [f"# Velix launches\n\n{len(cold)} launch(es), {len(rows) - len(cold)} prewarmed left out; "
           f"apps {', '.join(sorted({r.get('app', '?') for r in cold}))}.\n",
           "| Step | Median ms | Worst ms | Launches |", "|---|---|---|---|"]
    out.append(line("First screen (from process start)", [r["rootMs"] for r in cold]))
    maps = [r["mapMs"] for r in cold if "mapMs" in r]
    if maps:
        out.append(line("First full map frame", maps))
    for name in sorted({k for r in cold for k in r.get("phases", {})}):
        out.append(line(f"  {name}", [r["phases"][name] for r in cold if name in r.get("phases", {})]))
    return "\n".join(out) + "\n"


def load_crashes(directory: str | None) -> list[tuple[float, float, str]]:
    out = []
    if not directory:
        return out
    for path in sorted(glob.glob(os.path.join(directory, "*.json"))):
        try:
            with open(path, encoding="utf-8") as f:
                p = json.load(f)
        except (OSError, json.JSONDecodeError):
            continue
        if not p.get("crashDiagnostics") and not p.get("hangDiagnostics"):
            continue
        name = os.path.basename(path)
        try:   # CrashReports.swift: <begin ISO, no colons>-<end epoch>.json
            begin = datetime.strptime(name[:17], "%Y-%m-%dT%H%M%S").replace(tzinfo=timezone.utc).timestamp()
            end = float(name[18:].removesuffix(".json"))
        except ValueError:
            continue
        kinds = [k for k in ("crashDiagnostics", "hangDiagnostics") if p.get(k)]
        out.append((begin, end, f"{name} ({', '.join(kinds)})"))
    return out


CHECKS = [("No crash", None), ("Hazards on time", check_hazards), ("No reroute bursts", check_bursts),
          ("No location gaps", check_gaps), ("Failed reroute keeps the route", check_failed),
          ("Voice with the phone locked", check_voice), ("Live Activity", check_activity)]


def mark(ok: bool | None) -> str:
    return "—" if ok is None else "✅" if ok else "❌"


def report(rides: list[Ride], crashes: list[tuple[float, float, str]]) -> str:
    rows, sections = [], []
    for r in rides:
        s = r.start or {}
        b, e = r.span
        head = (f"### {r.name}: to {s.get('to', '?')}, {r.meters() / 1000:.1f} km, {mmss(e - b)} "
                f"({mmss(r.moving_seconds())} moving), {s.get('type', '?')}, app {s.get('app', '?')}")
        lines = [head, ""]
        cells = []
        for title, fn in CHECKS:
            ok, summary, details = check_crash(r, crashes) if fn is None else fn(r)
            cells.append(mark(ok))
            lines.append(f"- {mark(ok)} **{title}**: {summary}")
            lines += [f"  - {d}" for d in details]
        lines.append(f"- **Battery, memory, heat**: {'; '.join(health(r))}")
        if fps := map_fps(r):
            lines.append(f"- **Map**: {fps}")
        sections.append("\n".join(lines))
        rows.append(f"| {r.name} | {r.meters() / 1000:.1f} km | {mmss(e - b)} | " + " | ".join(cells) + " |")
    table = ["| Ride | Distance | Time | " + " | ".join(t for t, _ in CHECKS) + " |",
             "|---|---|---|" + "---|" * len(CHECKS)] + rows
    return "\n".join(["## Summary", "", *table, "", "✅ met · ❌ failed · — not measured on this ride", "",
                      "## Rides", "", "\n\n".join(sections), ""])


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("paths", nargs="*", help="ride logs (.jsonl) or folders of them")
    ap.add_argument("--launch", help="summarise launch times instead (Documents/diagnostics/launch.jsonl)")
    ap.add_argument("--diagnostics", help="folder of MetricKit payloads (Documents/diagnostics)")
    ap.add_argument("--include-simulated", action="store_true", help="also report simulated rides")
    ap.add_argument("--min-km", type=float, default=0.5, help="skip shorter rides (tries, aborted starts)")
    ap.add_argument("-o", "--output", help="write the markdown here (default: stdout)")
    a = ap.parse_args(argv)
    if a.launch:
        return emit(launches(a.launch), a.output)
    if not a.paths:
        ap.error("give ride logs, or --launch")
    files = []
    for p in a.paths:
        files += sorted(glob.glob(os.path.join(p, "*.jsonl"))) if os.path.isdir(p) else [p]
    rides, skipped_sim, skipped_short = [], 0, 0
    for f in files:
        r = Ride.load(f)
        if r.simulated and not a.include_simulated:
            skipped_sim += 1
        elif r.meters() < a.min_km * 1000:
            skipped_short += 1
        else:
            rides.append(r)
    out = (f"# Velix ride report\n\n{len(rides)} ride(s); skipped {skipped_sim} simulated and {skipped_short} "
           f"under {a.min_km:g} km.\n\n") + (report(rides, load_crashes(a.diagnostics)) if rides else "No rides to report.\n")
    return emit(out, a.output)


def emit(text: str, output: str | None) -> int:
    if output:
        with open(output, "w", encoding="utf-8") as f:
            f.write(text)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
