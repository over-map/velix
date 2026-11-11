import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "stages"))
try:
    from common import PIPELINE, load_config, merge, utm_epsg  # needs pyyaml (tools image)
    from coverage import grow, manifest_polygon        # needs shapely, pyproj
    from country_admin import country_tags, parts, relation_id
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
            self.assertTrue(c["osm"].get("sources") or c["osm"]["url"].endswith("italy-latest.osm.pbf"), r)
            self.assertEqual(c["pack"]["budget_mb"], 320, r)
            self.assertGreaterEqual(c["coverage"]["buffer_km"], 0, r)
            self.assertTrue((PIPELINE / "config" / "smoke_trips" / f"{r}.txt").exists(), r)

    def test_every_region_takes_trenitalia_from_the_nap(self):
        self.assertEqual([f["id"] for f in load_config("lombardy")["transit"]["feeds"]], ["trenitalia", "trenord", "atm", "brescia"])
        for r in REGIONS:
            feeds = load_config(r)["transit"]["feeds"]
            self.assertEqual(feeds[0]["nap"], {"dataset": 1077621, "asset": "TRENITALIA"}, r)
            self.assertTrue(all(f["format"] == "netex" and f["operator"] for f in feeds), r)
        self.assertEqual(load_config("veneto")["transit"]["days"], 60)


@unittest.skipIf(load_config is None, "run in the tools image")
class Europe(unittest.TestCase):
    def test_utm_zone_follows_the_region(self):
        self.assertEqual(utm_epsg(-9.14, 38.72), 32629)    # Lisbon
        self.assertEqual(utm_epsg(9.19, 45.46), 32632)     # Milan
        self.assertEqual(utm_epsg(24.94, 60.17), 32635)    # Helsinki

    def test_buffer_is_metres_far_from_northern_italy(self):
        grown = grow(box(24.9, 60.1, 25.0, 60.2), 10)      # Helsinki: ≈ 10 km east is ≈ 0.18° of longitude
        self.assertTrue(grown.contains(Point(25.0 + 0.16, 60.15)))
        self.assertFalse(grown.contains(Point(25.0 + 0.20, 60.15)))

    def test_a_coverage_across_a_border_is_split_between_the_countries(self):
        it = {"type": "Feature", "properties": {"iso": "IT", "name": "Italy"}, "geometry": box(8, 44, 10, 46).__geo_interface__}
        ch = {"type": "Feature", "properties": {"iso": "CH", "name": "Switzerland"},
              "geometry": box(8, 45.95, 10, 47).__geo_interface__}           # overlaps Italy's by 0.05°
        got = parts(box(9, 45.5, 9.5, 46.2), [ch, it])
        self.assertEqual([iso for iso, _, _ in got], ["IT", "CH"])         # the larger share first
        self.assertAlmostEqual(sum(g.area for _, _, g in got), 0.5 * 0.7, places=6)   # no overlap, nothing lost
        self.assertNotEqual(relation_id("IT"), relation_id("CH"))

    def test_france_and_the_uk_are_written_the_way_valhalla_reads_them(self):
        self.assertEqual(country_tags("IT", "Italia", "Italy")["admin_level"], "2")
        fr = country_tags("FR", "France", "France")
        self.assertEqual((fr["admin_level"], fr["name:en"]), ("3", "Metropolitan France"))   # admin.lua → France, FR
        self.assertEqual(country_tags("GB", "United Kingdom", "United Kingdom")["admin_level"], "3")

    def test_every_catalogue_region_loads_with_its_sources(self):
        cat = PIPELINE / "regions" / "europe.json"
        if not cat.exists():
            self.skipTest("no catalogue yet")
        import json
        for r in json.loads(cat.read_text())["regions"]:
            c = load_config(r["id"])
            self.assertEqual(c["region"]["name"], r["name"] if not (PIPELINE / "config" / f"{r['id']}.yml").exists()
                             else c["region"]["name"])
            self.assertTrue(c["osm"]["sources"] and all(u.startswith("https://download.geofabrik.de/") for u in c["osm"]["sources"]))
            self.assertTrue(c["region"]["timezone"].startswith(("Europe/", "Atlantic/", "Arctic/")) or c["region"]["timezone"] == "Asia/Nicosia", r["id"])
            self.assertLessEqual(r["forecast_mb"], 320, r["id"])


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
