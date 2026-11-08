"""CHARACTER-PHYSIQUE-ART-001: the anterior chest is its own bounded profile system: landmark
curves per build anchor, a monotone cubic between landmarks, a correction that is zero at the
band's ends and outside it, interpolated in mass without extrapolation."""
import unittest

from character_modeling import chest_profile as cp


class Studies(unittest.TestCase):
    def test_shipped_studies_are_valid_and_a_broken_one_is_named(self):
        ## ARRANGE / ACT / ASSERT
        for study in cp.STUDIES:
            self.assertEqual(cp.problems(study), [])
        self.assertEqual(len(cp.problems("pec_plate")), 1)
        try:
            cp.STUDIES["broken"] = {m: ((0.62, 99.0), (0.70, 20.0), (0.66, 18.0), (0.83, 7.0)) for m in (-1.0, 0.0, 1.0)}
            problems = cp.problems("broken")
            cp.STUDIES["partial"] = {0.0: ((0.62, 13.2), (0.84, 7.8))}
            partial = cp.problems("partial")
        finally:
            cp.STUDIES.pop("broken", None)
            cp.STUDIES.pop("partial", None)
        self.assertTrue(any("increase" in p for p in problems))
        self.assertTrue(any("span the band" in p for p in problems))
        self.assertTrue(any("equal the baseline" in p for p in problems))
        self.assertTrue(any("anchors must be" in p for p in partial))


class Curve(unittest.TestCase):
    def test_the_monotone_cubic_meets_its_landmarks_and_never_overshoots(self):
        ## ARRANGE: a profile that rises, plateaus and falls (the shape of a chest).
        points = ((0.0, 0.0), (1.0, 4.0), (2.0, 4.0), (3.0, 4.5), (4.0, 1.0))
        ## ACT
        samples = [(x / 20.0, cp.monotone(points, x / 20.0)) for x in range(81)]
        ## ASSERT: through every landmark, held past the ends, and between two landmarks
        ## never outside their range (no new apex can appear).
        for x, y in points:
            self.assertAlmostEqual(cp.monotone(points, x), y)
        self.assertEqual(cp.monotone(points, -1.0), 0.0)
        self.assertEqual(cp.monotone(points, 9.0), 1.0)
        for (x0, y0), (x1, y1) in zip(points, points[1:]):
            inner = [y for x, y in samples if x0 <= x <= x1]
            self.assertGreaterEqual(min(inner), min(y0, y1) - 1e-9)
            self.assertLessEqual(max(inner), max(y0, y1) + 1e-9)


class Correction(unittest.TestCase):
    def test_zero_outside_the_band_and_at_its_ends_and_bounded_in_mass(self):
        ## ARRANGE
        study = "heroic_chest"
        ## ACT / ASSERT: nothing moves outside the chest band, and the band's ends meet the
        ## baseline (no step at the rib-cage return or the neck).
        for mass in (-1.0, -0.5, 0.0, 0.5, 1.0):
            for h in (0.3, 0.5, 0.62, 0.84, 0.9):
                self.assertEqual(cp.correction(study, mass, h), 0.0)
            self.assertAlmostEqual(cp.smoothed(study, mass, 0.55), 0.0)
        ## PERTURB: the midpoint is the anchors' mean; past the anchors it is held.
        h = 0.76
        ref, strong = cp.correction(study, 0.0, h), cp.correction(study, 1.0, h)
        self.assertAlmostEqual(cp.correction(study, 0.5, h), 0.5 * (ref + strong))
        self.assertAlmostEqual(cp.correction(study, 3.0, h), strong)
        self.assertAlmostEqual(cp.baseline(0.0, 0.62), cp.BASELINE[0.0][0])

    def test_the_strongman_target_replaces_the_mound_with_a_plateau(self):
        ## ARRANGE: the protected baseline and the authored strongman profile.
        hs = [round(0.62 + 0.005 * i, 3) for i in range(45)]
        base = cp.metrics(hs, [cp.baseline(1.0, h) for h in hs])
        new = cp.metrics(hs, [cp.target("heroic_chest", 1.0, h) for h in hs])
        ## ASSERT: deepest higher, a longer plateau, fuller under the clavicle, a gentler
        ## roundest bend and a sharper lower turn.
        self.assertGreater(new["apex_h"], base["apex_h"])
        self.assertGreater(new["plateau"], base["plateau"])
        self.assertGreater(new["upper_fullness"], base["upper_fullness"])
        self.assertLess(new["convexity"], base["convexity"])
        self.assertGreater(new["lower_turn"], base["lower_turn"])


class LeanMaster(unittest.TestCase):
    def test_every_build_shares_the_lean_contour_scaled_in_depth(self):
        ## ARRANGE: the lean_master anchors' depths above their rib-cage return.
        anchors = cp.STUDIES["lean_master"]
        hs = [h for h, _v in anchors[-1.0]][1:-3]
        rise = {m: [v - anchors[m][0][1] for _h, v in anchors[m][1:-3]] for m in anchors}
        ## ACT / ASSERT: each build's rise is the lean rise times one depth factor (the same
        ## shape, more muscle), larger with mass, the lean smaller than its protected
        ## baseline, and the strongman deepest yet no deeper than its baseline's mound.
        shape = {m: [v / max(r) for v in r] for m, r in rise.items()}
        for m in (0.0, 1.0):
            self.assertLess(max(abs(a - b) for a, b in zip(shape[m], shape[-1.0])), 0.1, "build %+.0f keeps the lean shape" % m)
        self.assertLess(max(rise[-1.0]), max(rise[0.0]))
        self.assertLess(max(rise[0.0]), max(rise[1.0]))
        self.assertLess(max(v for _h, v in anchors[-1.0]), max(cp.BASELINE[-1.0]))
        self.assertLessEqual(max(v for _h, v in anchors[1.0]), max(cp.BASELINE[1.0]))
        self.assertEqual(cp.problems("lean_master"), [])
        self.assertTrue(hs)


def _flips(values, step):
    """Sign changes of the second difference (|d2| above a small floor): a lump adds two."""
    d2 = [values[i + 1] - 2 * values[i] + values[i - 1] for i in range(1, len(values) - 1)]
    signs = [1 if d > 1e-4 else -1 for d in d2 if abs(d) > 1e-4]
    return sum(1 for a, b in zip(signs, signs[1:]) if a != b)


class Fit(unittest.TestCase):
    def test_the_fitted_profile_loses_the_landmark_kinks_and_keeps_its_dimensions(self):
        ## ARRANGE: the shipped study's reference and strongman profiles on a fine grid.
        study, step = "lean_master_v2", 0.0025
        lo, hi = cp.band(study)
        hs = [lo + 0.02 + i * step for i in range(int((hi - lo - 0.04) / step))]
        for mass in (0.0, 1.0):
            raw = [cp.target(study, mass, h) for h in hs]
            ## ACT
            fit = [cp.smoothed_target(study, mass, h) for h in hs]
            ## ASSERT: fewer curvature reversals (the two-step lower pectoral is gone); the
            ## deepest point within 1 mm and 0.01 h; every height inside the fitted span
            ## (the band less the builder's 0.03 fade at each end) within 3 mm.
            self.assertLess(_flips(fit, step), _flips(raw, step), "build %+.0f" % mass)
            self.assertLess(abs(max(fit) - max(raw)), 0.1)
            self.assertLessEqual(abs(hs[fit.index(max(fit))] - hs[raw.index(max(raw))]), 0.01)
            inner = [i for i, h in enumerate(hs) if lo + 0.03 <= h <= hi - 0.03]
            self.assertLess(max(abs(fit[i] - raw[i]) for i in inner), 0.3)
        ## PERTURB: no smoothing is the authored profile exactly.
        self.assertAlmostEqual(cp.smoothed_target(study, 0.0, 0.7, sigma=1e-6), cp.target(study, 0.0, 0.7))


if __name__ == "__main__":
    unittest.main()
