"""The region catalogue's rules (stages/regions.py), on synthetic areas: grouping, tiny merges, names, ids."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "stages"))
try:
    from shapely.geometry import box
    from regions import (MB, Region, Unit, assign_ids, clean, combine, group, group_by_leaf, keep_others, merge_tiny, name_of,
                         pick_level, region_timezone, slug, weighted)
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

    def test_areas_group_only_inside_their_leaf(self):
        # Paris's areas and a whole neighbouring leaf: the leaf stays alone even though it touches and would fit.
        units = strip(3, [100, 60, 50], leaf="ile-de-france")
        units.append(Unit("picardie", "Picardie", "XX", 40 * MB, box(3, 0, 4, 1)))
        g = group_by_leaf(units, 260 * MB)
        self.assertEqual(sorted(sorted(u.key for u in r.members) for r in g),
                         [["ile-de-france/a0", "ile-de-france/a1", "ile-de-france/a2"], ["picardie"]])

    def test_grouping_is_deterministic(self):
        a = [[u.key for u in r.members] for r in group(strip(6, [50] * 6), 260 * MB)]
        b = [[u.key for u in r.members] for r in group(list(reversed(strip(6, [50] * 6))), 260 * MB)]
        self.assertEqual(sorted(map(sorted, a)), sorted(map(sorted, b)))


@unittest.skipIf(box is None, "run in the tools image")
class Weights(unittest.TestCase):
    """Packs of large, sparse leaves measure far above their extract (Norrbotten 481 MB for 260, 23 Nov 2026)."""
    rules = {"weight": {"sweden": 1.9}}

    def test_a_weighted_leaf_and_its_areas_count_heavier(self):
        self.assertEqual(weighted("sweden", 100 * MB, self.rules), 190 * MB)
        self.assertEqual(weighted("sweden/norrbottens-lan", 100 * MB, self.rules), 190 * MB)
        self.assertEqual(weighted("finland/lappi", 100 * MB, self.rules), 100 * MB)
        self.assertEqual(weighted("sweden", 100 * MB, {}), 100 * MB)

    def test_weighted_areas_make_smaller_groups(self):
        sizes = [weighted("sweden/a", int(s * MB), self.rules) / MB for s in [100, 90, 80, 70]]
        g = group(strip(4, sizes, leaf="sweden"), 260 * MB)
        self.assertEqual(len(g), 4)                          # unweighted, they make two groups

    def test_the_bundled_rules_weigh_the_north_and_leave_out_svalbard(self):
        import yaml
        rules = yaml.safe_load((Path(__file__).resolve().parents[1] / "regions" / "rules.yml").read_text())
        self.assertGreater(rules["weight"]["sweden"], 1.8)
        self.assertIn("svalbard-janmayen", rules["exclude"])


class PartialCatalogue(unittest.TestCase):
    old = [{"id": "lapland", "country": "FI", "members": ["finland/lappi"]},
           {"id": "norrbotten", "country": "SE", "members": ["sweden/norrbottens-lan"]},
           {"id": "lombardy", "country": "IT", "members": ["nord-ovest/lombardia"]},
           {"id": "svalbard", "country": "NO", "members": ["svalbard-janmayen"]}]

    def test_other_countries_stay_as_they_were(self):
        new = [{"id": "norrbotten-county", "country": "SE"}, {"id": "vasterbotten", "country": "SE"}]
        self.assertEqual([r["id"] for r in keep_others(new, self.old, {"svalbard-janmayen"})],
                         ["lapland", "lombardy", "norrbotten-county", "vasterbotten"])   # Svalbard: now excluded

    def test_a_new_id_equal_to_a_kept_one_fails(self):
        with self.assertRaises(SystemExit):
            keep_others([{"id": "lombardy", "country": "SE"}], self.old)


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
        self.assertEqual(name_of(r, {"Area 1 and around": "The Areas"}), "The Areas")

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
        self.assertEqual(slug("Østfold"), "ostfold")
        self.assertEqual(slug("Województwo łódzkie"), "wojewodztwo-lodzkie")
        self.assertEqual(slug("Αττική"), "")                  # hence the English name or OSM id in unit keys

    def test_geofabrik_html_names(self):
        self.assertEqual(clean("Sørlandet<br />(Southern Norway)"), "Southern Norway")
        self.assertEqual(clean("Województwo pomorskie<br />(Pomeranian Voivodeship)"), "Pomeranian Voivodeship")
        self.assertEqual(clean("Bayern"), "Bayern")


@unittest.skipIf(box is None, "run in the tools image")
class Levels(unittest.TestCase):
    def test_the_first_level_that_covers_the_leaf_wins(self):
        self.assertEqual(pick_level({4: [("a", 100)], 6: [("b", 50), ("c", 40)], 8: [("d", 45), ("e", 45)]}, 100), 6)
        self.assertIsNone(pick_level({4: [("a", 30), ("b", 20)]}, 100))

    def test_two_levels_together_cover_a_leaf_across_two_countries(self):
        # Ireland's counties at one level, Northern Ireland's districts at another; neither alone holds 80 %.
        found = {6: [("Cork", box(0, 0, 1, 1), 40), ("Dublin", box(1, 0, 2, 1), 30)],
                 8: [("Belfast", box(0, 2, 1, 3), 15), ("Derry", box(1, 2, 2, 3), 10), ("Cork city", box(0, 0, 0.5, 0.5), 5)]}
        self.assertIsNone(pick_level({lv: [(n, b) for n, _, b in a] for lv, a in found.items()}, 100))
        self.assertEqual(combine(found, 100), [(6, 0), (6, 1), (8, 0), (8, 1)])   # Cork city lies inside Cork
        self.assertIsNone(combine({6: found[6]}, 100))


@unittest.skipIf(box is None, "run in the tools image")
class TimeZones(unittest.TestCase):
    def test_a_region_whose_centre_is_sea_gets_its_land_zone(self):
        from timezonefinder import TimezoneFinder
        islands = box(8.1, 38.9, 9.8, 41.3).union(box(12.4, 36.6, 15.7, 38.3)).convex_hull   # Sardinia + Sicily
        tf = TimezoneFinder()
        c = islands.centroid
        self.assertIsNone(tf.timezone_at_land(lng=c.x, lat=c.y))                              # the centre is sea
        self.assertEqual(region_timezone(tf, islands), "Europe/Rome")


if __name__ == "__main__":
    unittest.main()


class CountryCodes(unittest.TestCase):
    def test_every_country_in_scope_has_a_two_letter_code(self):
        import re
        try:
            import yaml
        except ImportError:  # pragma: no cover
            self.skipTest("needs PyYAML (tools image)")
        rules = yaml.safe_load((Path(__file__).resolve().parents[1] / "regions" / "rules.yml").read_text())
        iso = rules["geofabrik_iso"]
        for c in rules["countries"]:
            self.assertIn(c, iso, c)
        for c, code in iso.items():     # a bare NO in YAML is False (Norway)
            self.assertTrue(isinstance(code, str) and re.fullmatch("[A-Z]{2}", code), f"{c}: {code!r}")

    def test_index_code_read_as_list_string_or_missing(self):
        from regions import iso_of
        rules = {"geofabrik_iso": {"ireland-and-northern-ireland": "IE"}}
        cid = "ireland-and-northern-ireland"
        for props in ({cid: {"iso3166-1:alpha2": ["IE"]}}, {cid: {"iso3166-1:alpha2": "IE"}}, {cid: {}}, {}):
            self.assertEqual(iso_of(cid, props, rules), "IE", props)
