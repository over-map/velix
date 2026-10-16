import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "stages"))
from metro_colors import assign, family  # noqa: E402


class MetroColors(unittest.TestCase):
    def test_milan_lines(self):
        # OSM colour=* of the Milan metro route relations (2026-10).
        milan = [("M1", "#EB2A28"), ("M2", "#2BA14B"), ("M3", "#FCBE00"), ("M4", "#0A56A0"), ("M5", "#9B6BB0")]
        got = {ref: fam for ref, (fam, _) in assign(milan).items()}
        self.assertEqual(got, {"M1": "red", "M2": "green", "M3": "yellow", "M4": "blue", "M5": "purple"})

    def test_second_line_of_a_family_takes_alt(self):
        got = assign([("1", "#C8102E"), ("2", "#E2001A")])
        self.assertEqual(got, {"1": ("red", False), "2": ("red", True)})

    def test_fallback_order_without_colour(self):
        got = assign([("A", None), ("B", None), ("C", None)])
        self.assertEqual([f for f, _ in got.values()], ["red", "green", "yellow"])

    def test_grey_and_brown(self):
        self.assertEqual(family("#8C9196"), "grey")
        self.assertEqual(family("#8A5A2B"), "brown")

    def test_matches_the_design_function(self):
        # Outputs of VX.metroFamily in design/p3v3/palettes.js (node, 2026-10-16).
        js = {"#C8102E": "red", "#F08A00": "orange", "#F5C400": "yellow", "#9C9A2E": "olive", "#0F9158": "green",
              "#1AA6C4": "lightblue", "#5AAEE6": "lightblue", "#1F5FB5": "blue", "#9A3A92": "purple", "#E46FA8": "pink",
              "#8A5A2B": "brown", "#8C9196": "grey", "#E2001A": "red", "#EE2E26": "red", "#FFCD00": "yellow",
              "#CF009E": "purple", "#0098D4": "lightblue", "#B36305": "brown", "#9B2E8F": "purple", "#95CDBA": "cyan",
              "#000000": "grey"}
        for hex_color, fam in js.items():
            self.assertEqual(family(hex_color), fam, hex_color)

if __name__ == "__main__":
    unittest.main()
