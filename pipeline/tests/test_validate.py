import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "stages"))
from validate import budget_errors, parts  # noqa: E402

MB = 1_000_000


def manifest(basemap_mb, other_mb, **budgets):
    files = [{"role": "basemap", "bytes": basemap_mb * MB}, {"role": "routing_tiles", "bytes": other_mb * MB},
             {"role": "overlays", "bytes": 3 * MB}]
    return {"files": files, "download_bytes": sum(f["bytes"] for f in files),
            "budget_bytes": 300 * MB, "map_budget_bytes": 300 * MB, **budgets}


class Budget(unittest.TestCase):
    # Filippo, 24 Nov: the map is an optional download; each part has its own 300 MB budget.
    def test_the_map_part_is_the_basemap_and_routing_is_everything_else(self):
        self.assertEqual(parts(manifest(154, 138)), {"routing": 141 * MB, "map": 154 * MB})

    def test_each_part_fits_its_own_budget_even_when_the_sum_does_not(self):
        self.assertEqual(budget_errors(manifest(250, 200)), [])

    def test_a_part_over_its_budget_is_named(self):
        self.assertEqual(budget_errors(manifest(301, 10)), ["map over budget: 301.0 MB > 300 MB"])
        self.assertEqual(budget_errors(manifest(10, 298)), ["routing over budget: 301.0 MB > 300 MB"])

    def test_a_manifest_without_a_map_budget_keeps_the_whole_pack_budget(self):
        m = manifest(154, 138)
        del m["map_budget_bytes"]
        self.assertEqual(budget_errors(m), [])
        m["budget_bytes"] = 280 * MB
        self.assertEqual(budget_errors(m), ["over budget: 295.0 MB > 280 MB"])


class Schema(unittest.TestCase):
    def test_the_schema_expects_exactly_the_files_package_writes(self):
        # M11 PR 4b dropped transit.sqlite: the schema's minItems 7 failed every pack until it followed.
        import json
        try:
            from package import FILES
        except ImportError:  # pragma: no cover
            self.skipTest("run in the tools image")
        from validate import ROLES
        schema = json.loads((Path(__file__).resolve().parents[1] / "schema" / "manifest.schema.json").read_text())
        files = schema["properties"]["files"]
        self.assertEqual(files["minItems"], len(FILES))
        self.assertEqual(set(files["items"]["properties"]["role"]["enum"]), ROLES)
        self.assertEqual({role for _, role in FILES}, ROLES)


if __name__ == "__main__":
    unittest.main()
