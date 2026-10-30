"""Stage 7b: the track between consecutive stops → table `hops` in out/<region>/transit.sqlite

GTFS from Trenord and ATM has no shapes, so the map had only straight lines between stops. Each pair of consecutive
stops on a run gets the shortest path on the OSM rail network (railway=rail / light_rail / narrow_gauge for trains,
railway=subway for the metro), from the track node nearest each stop. Pairs with no plausible path get no row: the app
then draws no line while riding, and the stops joined in overviews."""
import heapq
import math
import sqlite3
from collections import defaultdict

import osmium

from common import load_config, log, out_dir, write_json
from hazards import encode_polyline6

TRACKS = {"rail": {"rail", "light_rail", "narrow_gauge"}, "metro": {"subway", "light_rail"}}
# Yards and sidings are track too, but a train between two stations runs on the main line.
SERVICE_COST = {"yard": 4.0, "siding": 3.0, "spur": 2.0, "crossover": 1.0}
SNAP = 400.0        # a stop's coordinate is the station building or a platform: the track is this close
DETOUR = 1.6        # longer than this × the straight distance (+ 800 m) is a wrong turn, not the line
CELL = 0.005        # snapping grid (≈ 400–550 m)


def dist(a, b) -> float:
    """Metres between (lon, lat) points (equirectangular: fine at this scale)."""
    x = (b[0] - a[0]) * 111_320 * math.cos(math.radians((a[1] + b[1]) / 2))
    y = (b[1] - a[1]) * 110_574
    return math.hypot(x, y)


class Tracks(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.coords: dict[int, tuple[float, float]] = {}
        self.adj: dict[str, dict[int, list[tuple[int, float]]]] = {m: defaultdict(list) for m in TRACKS}

    def way(self, w):
        kind = w.tags.get("railway")
        modes = [m for m, kinds in TRACKS.items() if kind in kinds]
        if not modes:
            return
        try:
            nodes = [(n.ref, (n.lon, n.lat)) for n in w.nodes]
        except osmium.InvalidLocationError:
            return
        factor = SERVICE_COST.get(w.tags.get("service", ""), 1.0)
        for ref, ll in nodes:
            self.coords[ref] = ll
        for (a, pa), (b, pb) in zip(nodes, nodes[1:]):
            d = dist(pa, pb) * factor
            for m in modes:
                self.adj[m][a].append((b, d))
                self.adj[m][b].append((a, d))


def grid(nodes, coords):
    g = defaultdict(list)
    for n in nodes:
        lon, lat = coords[n]
        g[(int(lon / CELL), int(lat / CELL))].append(n)
    return g


def snap(p, g, coords):
    cx, cy = int(p[0] / CELL), int(p[1] / CELL)
    best, best_d = None, SNAP
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for n in g.get((cx + dx, cy + dy), ()):
                d = dist(p, coords[n])
                if d < best_d:
                    best, best_d = n, d
    return best


def paths(adj, source, targets: dict[int, float]):
    """Dijkstra from `source` until every target is reached or past its cost limit: {target: [nodes]}."""
    limit = max(targets.values())
    cost, prev, out = {source: 0.0}, {}, {}
    heap = [(0.0, source)]
    left = set(targets)
    while heap and left:
        c, n = heapq.heappop(heap)
        if c > cost.get(n, math.inf) or c > limit:
            continue
        if n in left:
            left.discard(n)
            if c <= targets[n]:
                path = [n]
                while path[-1] != source:
                    path.append(prev[path[-1]])
                out[n] = path[::-1]
        for m, w in adj.get(n, ()):
            nc = c + w
            if nc < cost.get(m, math.inf):
                cost[m], prev[m] = nc, n
                heapq.heappush(heap, (nc, m))
    return out


def main():
    cfg = load_config()
    out = out_dir(cfg)
    db = sqlite3.connect(out / "transit.sqlite")
    stops = {sid: (lon, lat) for sid, lon, lat in db.execute("SELECT id, lon, lat FROM stops")}
    # Consecutive stops of every run, with the run's mode.
    pairs: dict[str, set[tuple[str, str]]] = defaultdict(set)
    last: dict[str, tuple[str, str]] = {}
    for trip, stop, mode in db.execute("""
            SELECT st.trip, st.stop, r.mode FROM stop_times st JOIN trips t ON t.id = st.trip JOIN routes r ON r.id = t.route
            ORDER BY st.trip, st.seq"""):
        if trip in last and last[trip][0] != stop:
            pairs[mode].add((last[trip][0], stop))
        last = {trip: (stop, mode)}
    log(f"{sum(len(p) for p in pairs.values())} stop pairs: " + ", ".join(f"{m} {len(p)}" for m, p in pairs.items()))

    tracks = Tracks()
    tracks.apply_file(str(out / "region.osm.pbf"), locations=True, idx="flex_mem")
    log(f"track nodes {len(tracks.coords)}: " + ", ".join(f"{m} {len(a)}" for m, a in tracks.adj.items()))

    db.execute("DROP TABLE IF EXISTS hops")
    db.execute("""CREATE TABLE hops (from_stop TEXT NOT NULL, to_stop TEXT NOT NULL, meters REAL NOT NULL,
                                     polyline TEXT NOT NULL, PRIMARY KEY (from_stop, to_stop))""")
    counts = {}
    for mode, todo in pairs.items():
        adj = tracks.adj[mode]
        g = grid(adj.keys(), tracks.coords)
        snapped = {s: snap(stops[s], g, tracks.coords) for pair in todo for s in pair if s in stops}
        by_origin = defaultdict(list)
        for a, b in todo:
            if snapped.get(a) and snapped.get(b):
                by_origin[a].append(b)
        found = 0
        for a, bs in by_origin.items():
            limits = {}
            for b in bs:
                straight = dist(stops[a], stops[b])
                limits[snapped[b]] = max(limits.get(snapped[b], 0), DETOUR * straight + 800)
            routes = paths(adj, snapped[a], limits)
            for b in bs:
                nodes = routes.get(snapped[b])
                if not nodes or len(nodes) < 2:
                    continue
                line = [stops[a]] + [tracks.coords[n] for n in nodes] + [stops[b]]
                meters = sum(dist(p, q) for p, q in zip(line, line[1:]))
                db.execute("INSERT OR REPLACE INTO hops VALUES (?,?,?,?)", (a, b, round(meters, 1), encode_polyline6(line)))
                found += 1
        counts[mode] = {"pairs": len(todo), "snapped": len(by_origin), "paths": found}
        log(f"{mode}: {counts[mode]}")
    db.execute("INSERT OR REPLACE INTO meta VALUES ('hops', '1')")
    db.commit()
    db.execute("VACUUM")
    db.close()
    write_json(out / "transit_paths.counts.json", counts)


if __name__ == "__main__":
    main()
