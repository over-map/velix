import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "stages"))
try:
    from prepare_routing import stairs_closed_to_bikes, walkable_not_rideable  # needs osmium (tools image)
except ImportError:  # pragma: no cover
    walkable_not_rideable = None


@unittest.skipIf(walkable_not_rideable is None, "run in the tools image")
class WalkStretches(unittest.TestCase):
    def test_crossings_and_footpaths_are_walked(self):
        self.assertTrue(walkable_not_rideable({"highway": "footway", "footway": "crossing"}))
        self.assertTrue(walkable_not_rideable({"highway": "footway"}))
        self.assertTrue(walkable_not_rideable({"highway": "pedestrian"}))
        self.assertTrue(walkable_not_rideable({"highway": "footway", "bicycle": "no"}))

    def test_private_street_open_on_foot_is_walked(self):
        # Via Gaetano Pini, Milan: access=private, foot=yes
        self.assertTrue(walkable_not_rideable({"highway": "service", "access": "private", "foot": "yes"}))

    def test_sidewalks_areas_and_rideable_ways_are_left_alone(self):
        self.assertFalse(walkable_not_rideable({"highway": "footway", "footway": "sidewalk"}))
        self.assertFalse(walkable_not_rideable({"highway": "pedestrian", "area": "yes"}))
        self.assertFalse(walkable_not_rideable({"highway": "footway", "bicycle": "yes"}))
        self.assertFalse(walkable_not_rideable({"highway": "cycleway"}))
        self.assertFalse(walkable_not_rideable({"highway": "residential"}))

    def test_closed_on_foot_too_is_left_alone(self):
        self.assertFalse(walkable_not_rideable({"highway": "footway", "foot": "no"}))
        self.assertFalse(walkable_not_rideable({"highway": "footway", "access": "no"}))
        self.assertFalse(walkable_not_rideable({"highway": "service", "access": "private"}))

    def test_metro_passages_are_left_alone(self):
        self.assertFalse(walkable_not_rideable({"highway": "footway", "indoor": "yes", "layer": "-1"}))
        self.assertFalse(walkable_not_rideable({"highway": "footway", "location": "underground"}))
        self.assertFalse(walkable_not_rideable({"highway": "footway", "tunnel": "yes"}))
        self.assertFalse(walkable_not_rideable({"highway": "footway", "fee": "yes"}))
        self.assertFalse(walkable_not_rideable({"highway": "footway", "layer": "-2"}))
        self.assertTrue(walkable_not_rideable({"highway": "footway", "layer": "1", "bridge": "yes"}))

    def test_stairs_without_a_ramp_close_to_bikes(self):
        self.assertTrue(stairs_closed_to_bikes({"highway": "steps"}))
        self.assertTrue(stairs_closed_to_bikes({"highway": "steps", "ramp": "no"}))
        self.assertFalse(stairs_closed_to_bikes({"highway": "steps", "ramp:bicycle": "yes"}))
        self.assertFalse(stairs_closed_to_bikes({"highway": "steps", "bicycle": "yes"}))
        self.assertFalse(stairs_closed_to_bikes({"highway": "footway"}))


if __name__ == "__main__":
    unittest.main()
