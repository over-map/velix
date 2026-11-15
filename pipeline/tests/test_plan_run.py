import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "stages"))
from plan_run import SAMPLE, catalogue, group_of, plan  # noqa: E402


class PlanRun(unittest.TestCase):
    def test_all_builds_every_region_and_downloads_each_leaf_once(self):
        cat = catalogue()
        p = plan("all", cat)
        self.assertEqual(len(p["regions"]), len(cat["regions"]))
        leaves = [leaf for g in p["groups"] for leaf in g["leaves"]]
        self.assertEqual(len(leaves), len(set(leaves)))
        self.assertEqual(set(leaves), {s for r in cat["regions"] for s in r["sources"]})
        self.assertLessEqual(len(p["groups"]), 256)

    def test_sample_and_lists(self):
        self.assertEqual(plan("sample")["regions"], SAMPLE)
        p = plan("luxembourg")
        self.assertEqual(p["regions"], ["luxembourg"])
        self.assertIn({"group": "luxembourg", "leaves": ["luxembourg"]}, p["groups"])
        with self.assertRaises(SystemExit):
            plan("atlantis")

    def test_group_is_the_country_folder(self):
        self.assertEqual(group_of("https://download.geofabrik.de/europe/france/alsace-latest.osm.pbf"), "france")
        self.assertEqual(group_of("https://download.geofabrik.de/europe/malta-latest.osm.pbf"), "malta")


if __name__ == "__main__":
    unittest.main()
