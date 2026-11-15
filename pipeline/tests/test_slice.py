import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "stages"))
try:
    from shapely.geometry import shape
    from slice import SLICES, extract_config, wanted  # needs shapely, pyproj, pyyaml, osmium (tools image)
except ImportError:  # pragma: no cover
    wanted = None

PIPELINE = Path(__file__).resolve().parents[1]


@unittest.skipIf(wanted is None, "run in the tools image")
class Slice(unittest.TestCase):
    def setUp(self):
        self.cat = json.loads((PIPELINE / "regions" / "europe.json").read_text())

    def test_a_leaf_is_cut_for_every_region_of_the_run_that_needs_it(self):
        everyone = {r["id"] for r in wanted("switzerland", self.cat, None)}
        self.assertIn("lombardy", everyone)
        self.assertEqual([r["id"] for r in wanted("switzerland", self.cat, {"lombardy", "luxembourg"})], ["lombardy"])
        self.assertEqual(wanted("switzerland", self.cat, {"luxembourg"}), [])

    def test_each_slice_covers_the_region_and_its_buffer(self):
        lux = next(r for r in self.cat["regions"] if r["id"] == "luxembourg")
        with tempfile.TemporaryDirectory() as d:
            cfg = extract_config("luxembourg", [lux], Path(d))
            self.assertEqual(cfg["directory"], str(SLICES))
            e = cfg["extracts"][0]
            self.assertEqual(e["output"], "luxembourg/luxembourg.osm.pbf")
            poly = shape(json.loads(Path(e["polygon"]["file_name"]).read_text())["features"][0]["geometry"])
            border = shape(lux["polygon"])
            self.assertTrue(poly.contains(border))
            self.assertGreater(poly.area, border.buffer(0.15).area)  # ≥ 15 km (10 km buffer + 5 km margin) ≈ 0.18°


@unittest.skipIf(shutil.which("openssl") is None, "needs openssl")
class Sign(unittest.TestCase):
    def test_signs_with_the_key_and_refuses_a_key_that_is_not_the_published_one(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            run = lambda *a, **k: subprocess.run(a, cwd=d, check=True, capture_output=True, **k)  # noqa: E731
            run("openssl", "genpkey", "-algorithm", "ed25519", "-out", "k.pem")
            run("openssl", "genpkey", "-algorithm", "ed25519", "-out", "other.pem")
            der = run("openssl", "pkey", "-in", "k.pem", "-pubout", "-outform", "DER").stdout
            import base64
            (d / "k.pub").write_text(base64.b64encode(der[-32:]).decode() + "\n")
            (d / "packs.json").write_text('{"schema":2}')
            env = {"PATH": os.environ["PATH"], "PACK_SIGNING_PUB": str(d / "k.pub")}
            sign = [str(PIPELINE / "stages" / "sign.sh"), "packs.json"]
            ok = subprocess.run(["bash", *sign], cwd=d, env={**env, "PACK_SIGNING_KEY": (d / "k.pem").read_text()},
                                capture_output=True)
            self.assertEqual(ok.returncode, 0, ok.stderr)
            self.assertEqual(len((d / "packs.json.sig").read_bytes()), 64)
            bad = subprocess.run(["bash", *sign], cwd=d, env={**env, "PACK_SIGNING_KEY": (d / "other.pem").read_text()},
                                 capture_output=True)
            self.assertNotEqual(bad.returncode, 0)


if __name__ == "__main__":
    unittest.main()
