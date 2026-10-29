import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "stages"))
try:
    from routes import climb, mix_class, profile  # needs osmium/shapely (tools image)
    from shapely.geometry import LineString
except ImportError:  # pragma: no cover
    climb = mix_class = profile = None


@unittest.skipIf(mix_class is None, "run in the tools image")
class Mix(unittest.TestCase):
    def test_car_free(self):
        self.assertEqual(mix_class({"highway": "cycleway"}), "car_free")
        self.assertEqual(mix_class({"highway": "path", "surface": "asphalt"}), "car_free")
        self.assertEqual(mix_class({"highway": "primary", "cycleway:right": "track"}), "road")
        self.assertEqual(mix_class({"highway": "secondary", "cycleway": "track"}), "car_free")

    def test_quiet_and_road(self):
        self.assertEqual(mix_class({"highway": "residential"}), "quiet")
        self.assertEqual(mix_class({"highway": "track", "tracktype": "grade1"}), "quiet")
        self.assertEqual(mix_class({"highway": "tertiary"}), "road")
        self.assertEqual(mix_class({"highway": "secondary", "cycleway:right": "lane"}), "road")

    def test_unpaved_wins(self):
        self.assertEqual(mix_class({"highway": "cycleway", "surface": "gravel"}), "unpaved")
        self.assertEqual(mix_class({"highway": "track"}), "unpaved")
        self.assertEqual(mix_class({"highway": "path"}), "unpaved")
        self.assertEqual(mix_class({"highway": "path", "bicycle": "designated"}), "car_free")


@unittest.skipIf(climb is None, "run in the tools image")
class Climb(unittest.TestCase):
    def test_small_changes_are_noise(self):
        self.assertEqual(climb([100, 101, 100, 101, 100]), 0)
        self.assertEqual(climb([100, 103, 106, 104, 110]), 12)
        self.assertEqual(climb([110, 104, 106, 103, 100]), 2)

    def test_profile_every_30_m(self):
        # ≈ 290 m north along a meridian: 10 samples, heights from the callback.
        line = LineString([(9.0, 45.0), (9.0, 45.0 + 290 / 110_574)])
        heights = profile([line], lambda lon, lat: (lat - 45.0) * 110_574)
        self.assertEqual(len(heights), 10)
        self.assertAlmostEqual(heights[3], 90, delta=0.5)


if __name__ == "__main__":
    unittest.main()
