"""The region catalogue's rules (stages/regions.py), on synthetic areas: grouping, tiny merges, names, ids."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "stages"))
try:
    from shapely.geometry import box
    from regions import MB, Region, Unit, assign_ids, group, merge_tiny, name_of, pick_level, slug
except ImportError:  # pragma: no cover
    box = None


def strip(n, sizes_mb, country="XX", leaf="leaf"):
    """n unit squares in a row (each touches the next), sizes in MB, as admin areas of one split leaf."""
    return [Unit(f"{leaf}/a{i}", f"Area {i}", country, int(s * MB), box(i, 0, i + 1, 1)) for i, s in enumerate(sizes_mb)]


@unittest.skipIf(box is None, "run in the tools image")
class Grouping(unittest.TestCase):
    def test_neighbours_fill_up_to_the_limit(self):
        g = group(strip(5, [100, 90, 80, 70, 60]), 260 * MB)
        sizes = sorted(round(r.size / MB) for r in g)
        self.assertEqual(sizes, [190, 210])                  # a0 + a1 (a2 would pass 260), then a2 + a3 + a4
        self.assertTrue(all(r.size <= 260 * MB for r in g))

    def test_only_neighbours_join(self):
        far = strip(2, [100, 100])
        far[1].geom = box(10, 0, 11, 1)                      # not touching a0
        self.assertEqual(len(group(far, 260 * MB)), 2)

    def test_pinned_areas_stay_alone(self):
        units = strip(3, [200, 30, 30])
        units[0].pinned = {"id": "lombardy", "name": "Lombardy"}
        g = group(units, 260 * MB)
        self.assertEqual([len(r.members) for r in sorted(g, key=lambda r: -r.size)], [1, 2])

    def test_grouping_is_deterministic(self):
        a = [[u.key for u in r.members] for r in group(strip(6, [50] * 6), 260 * MB)]
        b = [[u.key for u in r.members] for r in group(list(reversed(strip(6, [50] * 6))), 260 * MB)]
        self.assertEqual(sorted(map(sorted, a)), sorted(map(sorted, b)))


@unittest.skipIf(box is None, "run in the tools image")
class TinyRegions(unittest.TestCase):
    def test_a_tiny_region_joins_its_smallest_neighbour_of_the_same_country(self):
        big, mid, tiny = (Region([u]) for u in strip(3, [200, 120, 10]))
        out = merge_tiny([big, mid, tiny], 40 * MB, 260 * MB)
        self.assertEqual(sorted(round(r.size / MB) for r in out), [130, 200])

    def test_not_across_countries_and_not_into_a_pinned_one(self):
        units = strip(2, [100, 10])
        units[0].country = "YY"
        self.assertEqual(len(merge_tiny([Region([u]) for u in units], 40 * MB, 260 * MB)), 2)
        units = strip(2, [100, 10])
        units[0].pinned = {"id": "p", "name": "P"}
        self.assertEqual(len(merge_tiny([Region([u]) for u in units], 40 * MB, 260 * MB)), 2)

    def test_it_stays_alone_when_the_sum_would_not_fit(self):
        self.assertEqual(len(merge_tiny([Region([u]) for u in strip(2, [250, 20])], 40 * MB, 260 * MB)), 2)


@unittest.skipIf(box is None, "run in the tools image")
class Names(unittest.TestCase):
    def test_a_leaf_keeps_its_name_with_the_english_override(self):
        r = Region([Unit("bayern", "Bayern", "DE", 200 * MB, box(0, 0, 1, 1))])
        self.assertEqual(name_of(r, {"Bayern": "Bavaria"}), "Bavaria")

    def test_a_group_of_areas_is_named_after_the_largest(self):
        r = Region(strip(3, [30, 90, 40]))
        self.assertEqual(name_of(r, {}), "Area 1 and around")
        self.assertEqual(name_of(Region(strip(1, [90])), {}), "Area 0")

    def test_ids_are_slugs_and_get_the_country_when_two_share_a_name(self):
        a = Region([Unit("nl/limburg", "Limburg", "NL", 100 * MB, box(0, 0, 1, 1))])
        b = Region([Unit("be/limburg", "Limburg", "BE", 100 * MB, box(5, 0, 6, 1))])
        c = Region([Unit("ile-de-france", "Ile-de-France", "FR", 100 * MB, box(9, 0, 10, 1))])
        ids = sorted(i for i, _, _ in assign_ids([a, b, c], {"Ile-de-France": "Île-de-France"}))
        self.assertEqual(ids, ["ile-de-france", "limburg-be", "limburg-nl"])

    def test_pinned_regions_keep_their_id_and_name(self):
        u = Unit("nord-ovest/lombardia", "Lombardy", "IT", 297 * MB, box(0, 0, 1, 1), {"id": "lombardy", "name": "Lombardy"})
        self.assertEqual(assign_ids([Region([u])], {})[0][:2], ("lombardy", "Lombardy"))

    def test_slug(self):
        self.assertEqual(slug("Provence-Alpes-Côte d'Azur"), "provence-alpes-cote-d-azur")
        self.assertEqual(slug("Trentino-Alto Adige/Südtirol"), "trentino-alto-adige-sudtirol")


@unittest.skipIf(box is None, "run in the tools image")
class Levels(unittest.TestCase):
    def test_the_first_level_that_covers_the_leaf_wins(self):
        self.assertEqual(pick_level({4: [("a", 100)], 6: [("b", 50), ("c", 40)], 8: [("d", 45), ("e", 45)]}, 100), 6)
        self.assertIsNone(pick_level({4: [("a", 30), ("b", 20)]}, 100))


if __name__ == "__main__":
    unittest.main()
