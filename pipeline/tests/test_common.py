import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "stages"))
try:
    from common import cobble_class  # needs pyyaml (tools image)
except ImportError:  # pragma: no cover
    cobble_class = None


@unittest.skipIf(cobble_class is None, "run in the tools image")
class CobbleClass(unittest.TestCase):
    def test_smoothness_decides_where_tagged(self):
        self.assertEqual(cobble_class({"highway": "tertiary", "surface": "sett", "smoothness": "good"}), "smooth")
        self.assertEqual(cobble_class({"highway": "tertiary", "surface": "sett", "smoothness": "intermediate"}), "mild")
        self.assertEqual(cobble_class({"highway": "footway", "surface": "sett", "smoothness": "bad"}), "rough")

    def test_car_free_paths_are_mild_streets_rough(self):
        # Giardino Oriana Fallaci path vs Via Giuseppe Ripamonti, Milan
        self.assertEqual(cobble_class({"highway": "footway", "footway": "sidewalk", "surface": "sett"}), "mild")
        self.assertEqual(cobble_class({"highway": "tertiary", "surface": "sett"}), "rough")
        self.assertEqual(cobble_class({"highway": "pedestrian", "surface": "unhewn_cobblestone"}), "mild")

    def test_not_cobbled(self):
        self.assertIsNone(cobble_class({"highway": "footway", "surface": "paving_stones"}))
        self.assertIsNone(cobble_class({"highway": "residential"}))


if __name__ == "__main__":
    unittest.main()
