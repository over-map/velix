import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "stages"))
try:
    from common import PIPELINE, load_config, merge  # needs pyyaml (tools image)
    from coverage import grow, manifest_polygon        # needs shapely, pyproj
    from shapely.geometry import Point, box
except ImportError:  # pragma: no cover
    load_config = None

REGIONS = sorted(p.stem for p in (Path(__file__).resolve().parents[1] / "config").glob("*.yml") if not p.stem.startswith("_")
                 and p.stem != "bikes_allowed_rules")


@unittest.skipIf(load_config is None, "run in the tools image")
class RegionConfigs(unittest.TestCase):
    def test_merge_is_key_by_key(self):
        self.assertEqual(merge({"a": {"x": 1, "y": 2}, "b": [1]}, {"a": {"y": 3}, "b": [2]}), {"a": {"x": 1, "y": 3}, "b": [2]})

    def test_every_region_has_what_the_stages_read(self):
        self.assertEqual(REGIONS, ["emilia-romagna", "lombardy", "piemonte", "trentino-alto-adige", "veneto"])
        for r in REGIONS:
            c = load_config(r)
            self.assertEqual(c["region"]["id"], r)
            for k in ("osm_relation", "city_area_relation", "timezone", "name"):
                self.assertIn(k, c["region"], r)
            self.assertTrue(c["osm"]["url"].endswith("italy-latest.osm.pbf"), r)
            self.assertEqual(c["pack"]["budget_mb"], 320, r)
            self.assertGreaterEqual(c["coverage"]["buffer_km"], 0, r)
            self.assertTrue((PIPELINE / "config" / "smoke_trips" / f"{r}.txt").exists(), r)

    def test_lombardy_keeps_its_feeds_and_others_inherit_none(self):
        self.assertEqual([f["id"] for f in load_config("lombardy")["transit"]["feeds"]], ["trenord", "atm"])
        self.assertEqual(load_config("veneto")["transit"]["feeds"], [])
        self.assertEqual(load_config("veneto")["transit"]["days"], 60)


@unittest.skipIf(load_config is None, "run in the tools image")
class Coverage(unittest.TestCase):
    def test_buffer_reaches_the_distance_past_the_border(self):
        square = box(9.0, 45.0, 9.2, 45.2)
        grown = grow(square, 10)
        self.assertTrue(grown.contains(Point(9.2 + 0.12, 45.1)))       # ≈ 9.4 km east of the edge
        self.assertFalse(grown.contains(Point(9.2 + 0.14, 45.1)))      # ≈ 11 km

    def test_manifest_polygon_is_a_multipolygon_of_closed_rings(self):
        rings = manifest_polygon(box(9.0, 45.0, 9.2, 45.2), 250)
        self.assertEqual(len(rings), 1)
        outer = rings[0][0]
        self.assertEqual(outer[0], outer[-1])
        self.assertTrue(all(len(p) == 2 for p in outer))


if __name__ == "__main__":
    unittest.main()
