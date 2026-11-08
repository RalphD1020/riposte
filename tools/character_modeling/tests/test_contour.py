"""HEAD-CONTOUR-001: the lower face's contour measures. Each test states its fixture
(ARRANGE), the drift (PERTURB), the code under test (ACT) and the contract (ASSERT)."""

import math
import unittest

from character_modeling import contour


def arc(radius, degrees, n=40):
    return [(radius * math.cos(math.radians(degrees * i / n)), radius * math.sin(math.radians(degrees * i / n)))
            for i in range(n + 1)]


class ContourTest(unittest.TestCase):
    def test_a_designed_curve_is_neither_a_kink_nor_a_ripple(self):
        ## ARRANGE: a 90 degree turn of 20 mm radius (the chin turning under, designed).
        measures = contour.analyse(arc(0.020, 90.0))
        ## ASSERT: it turns everywhere a little (2 mm / 20 mm), never in one step.
        self.assertEqual(measures["kinks"], [])
        self.assertEqual(measures["reversals"], [])
        self.assertAlmostEqual(measures["sharpest_deg"], math.degrees(contour.STEP_M / 0.020), delta=0.6)
        self.assertEqual(contour.problems("midline", measures), [])

    def test_a_facet_corner_is_a_kink_at_its_arc_length(self):
        ## ARRANGE: two straight runs meeting at a 35 degree corner 30 mm along (two planar
        ## panels meeting at one vertex).
        bend = math.radians(35.0)
        line = [(0.0, 0.0), (0.030, 0.0), (0.030 + 0.030 * math.cos(bend), 0.030 * math.sin(bend))]
        ## ACT
        measures = contour.analyse(line)
        ## ASSERT: one kink, where the corner is, of the corner's angle.
        self.assertEqual(len(measures["kinks"]), 1)
        self.assertAlmostEqual(measures["kinks"][0][0], 0.030, delta=contour.STEP_M)
        self.assertAlmostEqual(measures["kinks"][0][1], 35.0, delta=0.5)
        self.assertIn("midline kink at 30 mm (35.0 deg)", contour.problems("midline", measures))

    def test_a_ripple_reverses_and_the_count_is_bounded(self):
        ## ARRANGE: a run dipping and bumping (a dip behind the chin, a step).
        line = [(i * 0.002, 0.0015 * math.sin(i * 0.9)) for i in range(30)]
        ## ACT
        measures = contour.analyse(line)
        ## ASSERT: reversals counted; more than the band allows is a problem.
        self.assertGreater(len(measures["reversals"]), contour.HEAD_CONTOUR["border"]["reversals"])
        self.assertTrue(any("reverses" in p for p in contour.problems("border", measures)))

    def test_resampling_is_independent_of_tessellation(self):
        ## ARRANGE: the same arc at two tessellations.
        coarse, fine = contour.analyse(arc(0.03, 60.0, 12)), contour.analyse(arc(0.03, 60.0, 200))
        ## ASSERT: the same length within a step; neither has a kink worth the name.
        self.assertAlmostEqual(coarse["length_m"], fine["length_m"], delta=contour.STEP_M)
        self.assertAlmostEqual(fine["length_m"], 0.03 * math.radians(60.0), delta=0.0005)
        self.assertEqual(fine["kinks"], [])
        self.assertEqual(contour.resample([(0.0, 0.0)]), [(0.0, 0.0)])

    def test_a_sharp_single_step_turn_fails_its_band(self):
        ## ARRANGE: a profile whose sharpest step exceeds the border's band (no kink: the
        ## neighbours turn as much).
        measures = {"kinks": [], "reversals": [], "sharpest_deg": contour.HEAD_CONTOUR["border"]["sharpest_deg"] + 1.0}
        ## ASSERT
        self.assertEqual(len(contour.problems("border", measures)), 1)


if __name__ == "__main__":
    unittest.main()
