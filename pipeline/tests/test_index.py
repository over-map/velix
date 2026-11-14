import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "stages"))
from index import MIRRORS, build, dumps  # noqa: E402

try:
    from coverage import index_outline  # needs shapely, pyproj (tools image)
    from shapely.geometry import shape
except ImportError:  # pragma: no cover
    index_outline = None


def manifest(pack, name, **extra):
    return {"pack": pack, "name": name, "version": "2026.11", "built": "2026-11-01", "country": "IT",
            "bbox": [1, 2, 3, 4], "polygon": [[[[1, 2], [3, 2], [3, 4], [1, 2]]]], "outline": [[[[1, 2], [3, 4], [1, 2]]]],
            "coverage": {"buffer_km": 10, "bbox": [0, 1, 4, 5], "polygon": [[[[0, 1], [4, 1], [4, 5], [0, 1]]]]},
            "download_bytes": 5, "unpacked_bytes": 9, **extra}


class Index(unittest.TestCase):
    def test_schema_2_one_entry_per_region_by_name_with_mirrors_and_manifest_url(self):
        idx = build([("pack-veneto-2026.11", manifest("veneto", "Veneto")),
                     ("pack-lombardy-2026.11.2", manifest("lombardy", "Lombardy"))])
        self.assertEqual(idx["schema"], 2)
        self.assertEqual(idx["mirrors"], ["https://github.com/over-map/velix/releases/download/"])
        self.assertEqual([r["id"] for r in idx["regions"]], ["lombardy", "veneto"])
        self.assertEqual(idx["regions"][0]["manifest"], f"{MIRRORS[0]}pack-lombardy-2026.11.2/manifest.json")
        self.assertEqual(idx["regions"][0]["country"], "IT")

    def test_the_outline_replaces_the_border_and_the_coverage_stays_in_the_manifest(self):
        r = build([("t", manifest("lombardy", "Lombardy"))])["regions"][0]
        self.assertEqual(r["polygon"], [[[[1, 2], [3, 4], [1, 2]]]])
        self.assertNotIn("coverage", r)
        old = manifest("veneto", "Veneto")
        del old["outline"]          # a manifest from before M11 PR 3
        self.assertEqual(build([("t", old)])["regions"][0]["polygon"], old["polygon"])

    def test_regions_not_rebuilt_keep_their_previous_entry(self):
        previous = {"schema": 1, "regions": [
            {"id": "veneto", "name": "Veneto", "tag": "pack-veneto-2026.10", "version": "2026.10", "built": "2026-10-01",
             "bbox": [1, 2, 3, 4], "polygon": [], "coverage": {"buffer_km": 10}, "download_bytes": 1, "unpacked_bytes": 2,
             "manifest": "x"},
            {"id": "lombardy", "name": "Lombardy", "tag": "pack-lombardy-2026.10", "version": "2026.10",
             "built": "2026-10-01", "bbox": [1, 2, 3, 4], "polygon": [], "download_bytes": 1, "unpacked_bytes": 2}]}
        idx = build([("pack-lombardy-2026.11", manifest("lombardy", "Lombardy"))], previous)
        by = {r["id"]: r for r in idx["regions"]}
        self.assertEqual(by["lombardy"]["tag"], "pack-lombardy-2026.11")
        self.assertEqual(by["veneto"]["tag"], "pack-veneto-2026.10")      # its build failed this month
        self.assertNotIn("coverage", by["veneto"])
        self.assertEqual(by["veneto"]["manifest"], f"{MIRRORS[0]}pack-veneto-2026.10/manifest.json")

    @unittest.skipIf(index_outline is None, "run in the tools image")
    def test_every_catalogue_region_fits_an_index_under_400_kb(self):
        cat = json.loads((Path(__file__).resolve().parents[1] / "regions" / "europe.json").read_text())
        pairs = [(f"pack-{r['id']}-2026.12", manifest(r["id"], r["name"], outline=index_outline(shape(r["polygon"])),
                                                       bbox=[-31.27, 34.56, 34.6, 81.0]))
                 for r in cat["regions"]]
        size = len(dumps(build(pairs)).encode())
        self.assertLess(size, 400_000, f"{size / 1000:.0f} KB")


if __name__ == "__main__":
    unittest.main()
