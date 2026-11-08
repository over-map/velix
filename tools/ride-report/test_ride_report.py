"""Tests for ride_report.py on synthetic logs: a clean ride and one with every problem the M7 review looks for.

    python3 -m unittest discover -s tools/ride-report
"""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import ride_report as rr  # noqa: E402

T0 = 1_793_000_000.0
LAT0, LON0 = 45.47, 9.20
M_PER_DEG_LAT = 111_195.0


def at(m: float) -> tuple[float, float]:
    """A point `m` metres north of the start."""
    return LAT0 + m / M_PER_DEG_LAT, LON0


def write(lines: list[dict]) -> str:
    fd, path = tempfile.mkstemp(suffix=".jsonl")
    with os.fdopen(fd, "w") as f:
        for o in lines:
            f.write(json.dumps(o) + "\n")
    return path


def ride(seconds: int = 300, speed: float = 5.0, gaps: tuple[int, ...] = (), stop: tuple[int, int] | None = None,
         sim: bool = False, hazards_along: tuple[float, ...] = (600.0,), alert: str = "on time",
         reroutes: tuple[float, ...] = (), failed_at: float | None = None, locked_from: int | None = 60,
         end: bool = True) -> list[dict]:
    out = [{"t": T0, "e": "start", "to": "Politecnico", "m": seconds * speed, "type": "city", "app": "1.0 (1)", "sim": sim,
            "voice": "all", "view": "2D", "battery": 0.9, "charging": False, "lowPower": False}]
    out.append({"t": T0, "e": "route", "m": seconds * speed, "steps": 4,
                "hazards": [{"type": "tram", "along": a, "lat": at(a)[0], "lon": at(a)[1]} for a in hazards_along]})
    out.append({"t": T0, "e": "activity", "s": "started"})
    pos = 0.0
    for i in range(seconds):
        t = T0 + i
        if i in gaps:
            continue
        moving = not (stop and stop[0] <= i < stop[1])
        if moving and i:
            pos += speed
        lat, lon = at(pos)
        out.append({"t": t, "lat": lat, "lon": lon, "acc": 4.0 + (i % 5), "alt": 120, "v": speed if moving else 0.0, "c": 0})
        for a in hazards_along:
            fire = 50 if alert == "on time" else 10
            if alert != "none" and abs((a - pos) - fire) < speed / 2:
                out.append({"t": t, "e": "hazard", "type": "tram", "d": a - pos, "lat": lat, "lon": lon, "v": speed,
                            "secs": (a - pos) / speed, "gps": "good", "spoken": True})
        if locked_from is not None and i == locked_from:
            out += [{"t": t, "e": "app", "s": "background"}, {"t": t, "e": "app", "s": "locked"}]
        if locked_from is not None and i == locked_from + 5:
            out += [{"t": t, "e": "voice", "s": "started", "text": "Turn left onto Via Pacini", "locked": True, "background": True},
                    {"t": t + 2, "e": "voice", "s": "finished", "text": "Turn left onto Via Pacini", "locked": True, "background": True}]
        if i and i % 60 == 0:
            out += [{"t": t, "e": "health", "battery": 0.9 - i / 36000, "charging": False, "thermal": "nominal", "mb": 180 + i / 10,
                     "fixes": 60, "fps": 40.0 if i == 120 else 58.0, "slow": 1}, {"t": t, "e": "activity", "s": "updates", "n": 6}]
        for r in reroutes:
            if i == int(r):
                out += [{"t": t, "e": "reroute", "s": "requested"}, {"t": t + 0.05, "e": "reroute", "s": "accepted", "ms": 50, "m": 1500}]
        if failed_at is not None and i == int(failed_at):
            out += [{"t": t, "e": "reroute", "s": "requested"},
                    {"t": t + 0.1, "e": "reroute", "s": "failed", "ms": 100, "reason": "planner: no route", "kept": True}]
    if end:
        out.append({"t": T0 + seconds, "e": "end", "s": "arrived"})
    return out


class RideReportTests(unittest.TestCase):
    def run_checks(self, lines, crashes=()):
        r = rr.Ride.load(write(lines))
        return r, {title: (rr.check_crash(r, list(crashes)) if fn is None else fn(r)) for title, fn in rr.CHECKS}

    def test_a_clean_ride_passes(self):
        r, c = self.run_checks(ride(reroutes=(100,), failed_at=200))
        self.assertFalse(r.simulated)
        self.assertAlmostEqual(r.meters(), 299 * 5, delta=5)
        for title in ("No crash", "Hazards on time", "No reroute bursts", "No location gaps", "Failed reroute keeps the route",
                      "Voice with the phone locked", "Live Activity"):
            self.assertTrue(c[title][0], f"{title}: {c[title][1]} {c[title][2]}")
        self.assertIn("1/1 on time", c["Hazards on time"][1])
        self.assertTrue(any("%/h" in h for h in rr.health(r)))

    def test_every_problem_is_caught(self):
        lines = ride(gaps=tuple(range(150, 160)), stop=(140, 220), hazards_along=(600.0, 900.0), alert="none",
                     reroutes=(100, 110, 120), end=False)
        r, c = self.run_checks(lines)
        self.assertFalse(c["No crash"][0])                       # no end, no terminate
        self.assertFalse(c["Hazards on time"][0])
        self.assertIn("missed", c["Hazards on time"][1])
        self.assertFalse(c["No reroute bursts"][0])
        self.assertTrue(any("BURST 3" in d for d in c["No reroute bursts"][2]))
        self.assertFalse(c["No location gaps"][0])
        self.assertTrue(any("stopped" in d and "locked" in d for d in c["No location gaps"][2]))

    def test_late_alert_and_a_crash_report(self):
        lines = ride(alert="late")
        b = T0 + 10
        r, c = self.run_checks(lines, crashes=[(b, b + 1, "x.json (crashDiagnostics)")])
        self.assertFalse(c["Hazards on time"][0])
        self.assertIn("1 late", c["Hazards on time"][1])
        self.assertFalse(c["No crash"][0])

    def test_simulated_rides_are_recognised(self):
        self.assertTrue(rr.Ride.load(write(ride(sim=True))).simulated)
        old = [{"t": T0, "e": "start", "to": "Villa Reale", "m": 1000}] + [
            {"t": T0 + i, "lat": at(i * 5)[0], "lon": LON0, "acc": 5, "v": 5} for i in range(30)]
        self.assertTrue(rr.Ride.load(write(old)).simulated)       # before the flag: constant 5 m accuracy

    def test_the_report_prints_no_coordinates(self):
        path = write(ride())
        fd, out = tempfile.mkstemp(suffix=".md")
        os.close(fd)
        rr.main([path, "-o", out])
        with open(out, encoding="utf-8") as f:
            text = f.read()
        self.assertIn("## Summary", text)
        self.assertNotIn("45.47", text)
        self.assertNotIn("9.2", text.replace("9.2 km", ""))

    def test_map_fps_leaves_out_the_start_and_locked_minutes(self):
        # Health at 60 (the start), 120 (40 fps, on screen), 180 and 240 (58); locked from 200 drops 240.
        r = rr.Ride.load(write(ride(seconds=300, locked_from=200)))
        self.assertEqual(rr.map_fps(r), "map 49 fps median, worst minute 40 fps, 2 slow frame(s) over 2 min on screen")
        self.assertIsNone(rr.map_fps(rr.Ride.load(write(ride(seconds=100)))))

    def test_launch_summary(self):
        lines = [{"t": T0, "app": "1.0 (9)", "prewarmed": False, "rootMs": 900, "mapMs": 1400, "phases": {"history": 120.5}},
                 {"t": T0 + 60, "app": "1.0 (9)", "prewarmed": False, "rootMs": 700, "phases": {"history": 80}},
                 {"t": T0 + 120, "app": "1.0 (9)", "prewarmed": True, "rootMs": 9000, "phases": {"history": 1}}]
        text = rr.launches(write(lines))
        self.assertIn("2 launch(es), 1 prewarmed left out", text)
        self.assertIn("| First screen (from process start) | 800 | 900 | 2 |", text)
        self.assertIn("| First full map frame | 1400 | 1400 | 1 |", text)
        self.assertIn("|   history | 100 | 120 | 2 |", text)


class BatteryStepsTests(unittest.TestCase):
    def _ride(self, levels):
        events = [{"t": 0, "e": "start", "type": "city", "sim": False, "to": "X", "m": 1000, "app": "1", "voice": "all",
                   "view": "2D", "battery": levels[0], "charging": False, "lowPower": False}]
        events += [{"t": i * 60, "e": "health", "battery": b, "charging": False, "thermal": "nominal", "mb": 300, "fixes": 60,
                    "cpu": 90 if i == 0 else 30 + i % 3 * 10}
                   for i, b in enumerate(levels)]
        return rr.Ride("r", events=events)

    def test_one_step_gives_no_rate(self):
        # 100 % held for 56 min, then one 5 % step: not 5 %/h.
        out = rr.health(self._ride([1.0] * 56 + [0.95] * 7))
        self.assertTrue(any("1 step(s): too few for a rate" in h for h in out), out)

    def test_rate_between_the_first_and_the_last_step(self):
        # Steps at minute 10 (→ 0.90) and minute 40 (→ 0.85): 5 % in 30 min.
        out = rr.health(self._ride([0.95] * 10 + [0.90] * 30 + [0.85] * 10))
        self.assertTrue(any("(10 %/h between the first and the last step)" in h for h in out), out)

    def test_cpu_median_leaves_out_the_first_line(self):
        out = rr.health(self._ride([0.9] * 10))
        self.assertIn("CPU 40 % of a core median, 50 % worst minute", out)


if __name__ == "__main__":
    unittest.main()
