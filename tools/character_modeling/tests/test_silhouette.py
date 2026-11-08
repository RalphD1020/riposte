"""CHARACTER-PHYSIQUE-ART-001: the side silhouette is authored as per-side corrections at
three anchors on the build axis, interpolated between them, and read by gate metrics."""
import unittest

from character_modeling import silhouette

STUDY = "heroic_profile"


class Anchors(unittest.TestCase):
    def test_every_study_has_three_anchors_with_zero_ends(self):
        ## ARRANGE / ACT / ASSERT: the shipped study is well formed; a malformed one is named.
        self.assertEqual(silhouette.anchor_problems(STUDY), [])
        self.assertEqual(len(silhouette.anchor_problems("hourglass")), 1)
        good = silhouette.ANCHORS[STUDY]
        try:
            silhouette.ANCHORS["broken"] = {0.0: {"front": ((0.5, 1.0), (0.4, 0.0))}}
            problems = silhouette.anchor_problems("broken")
        finally:
            del silhouette.ANCHORS["broken"]
        self.assertTrue(any("anchors must be" in p for p in problems))
        self.assertTrue(any("no back" in p for p in problems))
        self.assertTrue(any("increase" in p for p in problems))
        self.assertTrue(any("zero" in p for p in problems))
        self.assertEqual(set(good), {-1.0, 0.0, 1.0})


class LeanGlute(unittest.TestCase):
    def test_the_lean_glute_study_moves_only_the_lean_back(self):
        ## ARRANGE / ACT / ASSERT: a valid study; the lean's back filled under the glute and
        ## lowered at its peak; its front and every heavier build untouched.
        self.assertEqual(silhouette.anchor_problems("lean_glute"), [])
        self.assertGreater(silhouette.correction("lean_glute", -1.0, "back", 0.42), 0.5)
        self.assertLess(silhouette.correction("lean_glute", -1.0, "back", 0.47), 0.0)
        for h in (0.42, 0.47, 0.52):
            self.assertEqual(silhouette.correction("lean_glute", -1.0, "front", h), 0.0)
            for mass in (0.0, 0.5, 1.0):
                for side in silhouette.SIDES:
                    self.assertEqual(silhouette.correction("lean_glute", mass, side, h), 0.0)


class Interpolation(unittest.TestCase):
    def test_the_correction_is_each_anchor_at_its_mass_and_linear_between(self):
        ## ARRANGE: a height inside both bands.
        anchors = silhouette.ANCHORS[STUDY]
        h = 0.56
        for side in silhouette.SIDES:
            lean, ref, strong = (silhouette.at(anchors[m][side], h) for m in (-1.0, 0.0, 1.0))
            ## ACT / ASSERT: the anchors themselves, the midpoints, and held past the ends.
            self.assertAlmostEqual(silhouette.correction(STUDY, -1.0, side, h), lean)
            self.assertAlmostEqual(silhouette.correction(STUDY, 0.0, side, h), ref)
            self.assertAlmostEqual(silhouette.correction(STUDY, 1.0, side, h), strong)
            self.assertAlmostEqual(silhouette.correction(STUDY, 0.5, side, h), 0.5 * (ref + strong))
            self.assertAlmostEqual(silhouette.correction(STUDY, -0.5, side, h), 0.5 * (ref + lean))
            ## PERTURB: past the anchors the weights stay bounded (no overshoot).
            self.assertAlmostEqual(silhouette.correction(STUDY, 2.0, side, h), strong)
            self.assertAlmostEqual(silhouette.correction(STUDY, -3.0, side, h), lean)

    def test_outside_a_band_nothing_moves_and_smoothing_keeps_the_scale(self):
        ## ARRANGE / ACT / ASSERT: the head and the feet are never corrected; the smoothed
        ## correction stays within the authored range.
        for side in silhouette.SIDES:
            self.assertEqual(silhouette.correction(STUDY, 0.0, side, 0.2), 0.0)
            self.assertEqual(silhouette.correction(STUDY, 0.0, side, 0.95), 0.0)
            values = [v for _h, v in silhouette.ANCHORS[STUDY][1.0][side]]
            s = silhouette.smoothed(STUDY, 1.0, side, 0.56)
            self.assertTrue(min(values) <= s <= max(values))


class Metrics(unittest.TestCase):
    def test_metrics_read_apex_lead_pinch_shelf_and_bend(self):
        ## ARRANGE: a bust-and-hourglass profile (low chest apex, deep back, pinched waist, a
        ## shelf above the glutes) and a heroic one.
        hs = [round(0.40 + 0.02 * i, 2) for i in range(21)]
        bust_f = [12, 12, 12, 12, 12, 12, 11, 11, 12, 14, 17, 20, 21, 20, 18, 16, 14, 12, 10, 9, 8]
        bust_b = [16, 17, 18, 19, 19, 16, 13, 12, 12, 14, 17, 20, 21, 20, 18, 16, 14, 12, 10, 9, 8]
        hero_f = [12, 12, 12, 12, 12, 12.5, 12.5, 12.5, 13, 14, 16, 18, 19, 20, 20, 19.5, 18, 15, 11, 9, 8]
        hero_b = [16, 17, 18, 18, 18, 17.5, 16.5, 15, 14, 14, 15, 16, 17, 17.5, 17.5, 17, 16, 15, 13, 10, 8]
        ## ACT
        bust, hero = silhouette.metrics(hs, bust_f, bust_b), silhouette.metrics(hs, hero_f, hero_b)
        ## ASSERT: the heroic chest is deepest higher and leads the back; its waist pinches
        ## less; the drop above its glutes is gentler.
        self.assertGreater(hero["chest_apex_h"], bust["chest_apex_h"])
        self.assertGreater(hero["chest_lead"], 0.0)
        self.assertEqual(bust["chest_lead"], 0.0)
        self.assertGreater(hero["waist_ratio"], bust["waist_ratio"])
        self.assertLess(hero["glute_shelf"], bust["glute_shelf"])
        self.assertGreater(bust["bend"], 0.0)


if __name__ == "__main__":
    unittest.main()
