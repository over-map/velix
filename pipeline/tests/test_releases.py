import sys
import unittest
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "stages"))
from releases import load_pages, next_tag, prune  # noqa: E402


class Releases(unittest.TestCase):
    def test_paginated_listing_reads_every_page(self):
        pages = "".join(f'[{{"tag_name": "pack-r{i}-2026.11"}}]\n' for i in range(250))
        self.assertEqual(len(load_pages(pages)), 250)          # the old `gh release list --limit 200` stopped at 200

    def test_tag_counts_up_when_the_month_already_has_one(self):
        self.assertEqual(next_tag("lombardy", "2026.12", set()), "pack-lombardy-2026.12")
        self.assertEqual(next_tag("lombardy", "2026.12", {"pack-lombardy-2026.12", "pack-lombardy-2026.12.2"}),
                         "pack-lombardy-2026.12.3")

    def test_prune_old_packs_never_what_the_index_points_to(self):
        rel = lambda tag, day: {"tag_name": tag, "created_at": f"{day}T03:00:00Z"}  # noqa: E731
        releases = [rel("pack-lombardy-2026.09", "2026-09-02"), rel("pack-veneto-2026.09", "2026-09-02"),
                    rel("pack-lombardy-2026.11", "2026-11-02"), rel("pack-index", "2026-10-01"),
                    rel("pipeline-sources", "2026-08-01"), rel("pack-lombardy-2026.10", "2026-10-02")]
        index = {"regions": [{"tag": "pack-lombardy-2026.11"}, {"tag": "pack-veneto-2026.09"}]}
        self.assertEqual(prune(releases, index, date(2026, 12, 2)), ["pack-lombardy-2026.09"])
        self.assertEqual(prune(releases, index, date(2027, 1, 2)), ["pack-lombardy-2026.09", "pack-lombardy-2026.10"])


if __name__ == "__main__":
    unittest.main()
