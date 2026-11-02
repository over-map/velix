import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "stages"))
from index import build  # noqa: E402


class Index(unittest.TestCase):
    def test_one_entry_per_region_by_name_with_its_manifest_url(self):
        m = lambda pack, name: {"pack": pack, "name": name, "version": "2026.11", "built": "2026-11-01",  # noqa: E731
                                "bbox": [1, 2, 3, 4], "polygon": [[[[1, 2], [3, 2], [3, 4], [1, 2]]]],
                                "coverage": {"buffer_km": 10, "bbox": [0, 1, 4, 5], "polygon": []},
                                "download_bytes": 5, "unpacked_bytes": 9}
        idx = build([("pack-veneto-2026.11", m("veneto", "Veneto")), ("pack-lombardy-2026.11.2", m("lombardy", "Lombardy"))])
        self.assertEqual([r["id"] for r in idx["regions"]], ["lombardy", "veneto"])
        self.assertEqual(idx["regions"][0]["manifest"],
                         "https://github.com/over-map/velix/releases/download/pack-lombardy-2026.11.2/manifest.json")
        self.assertEqual(idx["regions"][1]["coverage"]["buffer_km"], 10)


if __name__ == "__main__":
    unittest.main()
