import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "stages"))
try:
    from overlays import cycling_kind, dedupe_stations  # needs osmium/pyproj (tools image)
except ImportError:  # pragma: no cover
    cycling_kind = dedupe_stations = None


@unittest.skipIf(cycling_kind is None, "run in the tools image")
class CyclingKind(unittest.TestCase):
    def test_cycleway_is_protected(self):
        self.assertEqual(cycling_kind({"highway": "cycleway"}), ("protected", "both"))
        self.assertEqual(cycling_kind({"highway": "path", "bicycle": "designated"}), ("protected", "both"))

    def test_lanes_on_roads(self):
        self.assertEqual(cycling_kind({"highway": "secondary", "cycleway:right": "lane"}), ("painted", "right"))
        self.assertEqual(cycling_kind({"highway": "primary", "cycleway": "track"}), ("protected", "both"))
        self.assertEqual(cycling_kind({"highway": "tertiary", "cycleway:left": "lane", "cycleway:right": "lane"}),
                         ("painted", "both"))
        self.assertEqual(cycling_kind({"highway": "residential", "cycleway": "shared_busway"}), ("painted", "both"))

    def test_not_cycle_infrastructure(self):
        self.assertIsNone(cycling_kind({"highway": "residential"}))
        self.assertIsNone(cycling_kind({"highway": "secondary", "cycleway": "no"}))
        self.assertIsNone(cycling_kind({"highway": "footway"}))
        self.assertIsNone(cycling_kind({"highway": "motorway", "cycleway": "lane"}))


@unittest.skipIf(dedupe_stations is None, "run in the tools image")
class Stations(unittest.TestCase):
    def test_same_station_mapped_twice_is_kept_once(self):
        def st(name, lon, lat, mode="metro"):
            return {"geometry": {"coordinates": [lon, lat]}, "properties": {"name": name, "mode": mode}}
        got = dedupe_stations([st("Loreto", 9.2163, 45.4857), st("Loreto", 9.2166, 45.4859),
                               st("Loreto", 9.2163, 45.4857, "train"), st("Loreto", 9.30, 45.49)])
        self.assertEqual(len(got), 3)


if __name__ == "__main__":
    unittest.main()
