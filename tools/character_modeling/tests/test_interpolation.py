"""CHARACTER-VARIATION-001: every mapping between the modifiers' bounds is continuous,
bounded by its anchors or stations, and exact at them; the build axis rides with the keys
(linear between anchors); station data is a monotone cubic; the face follows the head."""
import json
import unittest
from pathlib import Path

from character_modeling import chest_profile, interpolation, silhouette, variation

CONFIGURATION = Path(__file__).resolve().parents[3] / "art-src" / "blender" / "characters" / "male_base.v2.configuration.json"
STEPS = [i / 50.0 - 1.0 for i in range(101)]


def document():
    return json.loads(CONFIGURATION.read_text(encoding="utf-8"))


def _steps(values):
    return [abs(b - a) for a, b in zip(values, values[1:])]


class Schemes(unittest.TestCase):
    def test_linear_anchors_is_exact_at_the_anchors_and_held_past_them(self):
        ## ARRANGE: three anchor values.
        values = {-1.0: 2.0, 0.0: 0.0, 1.0: 5.0}
        ## ACT / ASSERT: exact at the anchors, halfway at the midpoints, held outside.
        for m, v in values.items():
            self.assertEqual(interpolation.linear_anchors(values, m), v)
        self.assertAlmostEqual(interpolation.linear_anchors(values, -0.5), 1.0)
        self.assertAlmostEqual(interpolation.linear_anchors(values, 0.5), 2.5)
        ## PERTURB: beyond the bounds the anchors hold (no extrapolation).
        self.assertEqual(interpolation.linear_anchors(values, 3.0), 5.0)
        self.assertEqual(interpolation.linear_anchors(values, -3.0), 2.0)

    def test_the_monotone_cubic_never_leaves_its_neighbours_and_has_no_corner(self):
        ## ARRANGE: stations with uneven slopes (the corner a polyline would have).
        points = [(-1.0, -0.45), (-0.75, -0.3), (-0.4, -0.15), (0.0, 0.0), (0.4, 0.25), (0.75, 0.5), (1.0, 0.8)]
        xs = [i / 400.0 - 1.0 for i in range(801)]
        ## ACT
        ys = [interpolation.monotone(points, x) for x in xs]
        ## ASSERT: exact at stations, inside each pair's range, monotone, no slope jump.
        for x, v in points:
            self.assertAlmostEqual(interpolation.monotone(points, x), v)
        for (x0, v0), (x1, v1) in zip(points, points[1:]):
            inside = [y for x, y in zip(xs, ys) if x0 <= x <= x1]
            self.assertGreaterEqual(min(inside), min(v0, v1) - 1e-12)
            self.assertLessEqual(max(inside), max(v0, v1) + 1e-12)
        self.assertEqual(ys, sorted(ys))
        slopes = [(b - a) * 400.0 for a, b in zip(ys, ys[1:])]
        self.assertLess(max(_steps(slopes)), 0.05, "the slope changes smoothly")


class BuildAxis(unittest.TestCase):
    def test_every_build_mapping_is_continuous_and_rides_with_the_keys(self):
        ## ARRANGE: the build-axis mappings sampled from the lean to the strongman bound.
        curves = {
            "chest": [chest_profile.target("lean_master_v2", m, 0.72) for m in STEPS],
            "silhouette": [silhouette.correction("heroic_profile", m, "back", 0.56) for m in STEPS],
            "girth": [variation.girth_factor(m, "leg", 0.20, strong=True) for m in STEPS],
            "response": [variation.physique_response(m)["upper_back_depth"][3] for m in STEPS],
        }
        for name, values in curves.items():
            ## ASSERT: no jump (a step no larger than the steepest anchor segment allows).
            span = max(values) - min(values)
            self.assertLess(max(_steps(values)), span / 50.0 * 1.01 + 1e-12, name)
        ## ASSERT: the midpoints sit exactly between their anchors, as the keys do.
        for m, lo, hi in ((-0.5, -1.0, 0.0), (0.5, 0.0, 1.0)):
            for name, f in (("chest", lambda x: chest_profile.target("lean_master_v2", x, 0.72)),
                            ("girth", lambda x: variation.girth_factor(x, "leg", 0.20, strong=True))):
                self.assertAlmostEqual(f(m), 0.5 * (f(lo) + f(hi)), msg=name)

    def test_the_head_profile_is_smooth_through_the_configurations(self):
        ## ARRANGE: the head physique profiles at the named configurations' masses.
        doc = document()
        profiles, configurations = doc["head_profiles"], doc["configurations"]
        ## ACT: the jaw sampled across the build axis.
        jaw = [variation.head_physique_profile(profiles, configurations, m).get("jaw_width", 0.0) for m in STEPS]
        ## ASSERT: exact at every configuration, monotone, no corner at a station.
        for name, values in configurations.items():
            got = variation.head_physique_profile(profiles, configurations, values.get("mass", 0.0)).get("jaw_width", 0.0)
            self.assertAlmostEqual(got, profiles[name].get("jaw_width", 0.0), places=9, msg=name)
        self.assertEqual(jaw, sorted(jaw))
        slopes = [(b - a) * 50.0 for a, b in zip(jaw, jaw[1:])]
        self.assertLess(max(_steps(slopes)), 0.12, "no kink at a station")


class FaceFollowsTheHead(unittest.TestCase):
    def _resolved(self, h, f, m):
        return variation.resolve({"body": {"height_m": h, "frame_build": f, "muscularity": m}}, document())

    def test_the_reference_face_is_the_locked_one(self):
        ## ARRANGE / ACT: the reference's response.
        response = variation.face_response(self._resolved(1.8, 1.0, 1.0))
        ## ASSERT: identity everywhere, so its marks are unchanged.
        self.assertEqual(response, {"eye_scale": 1.0, "brow_thickness": 1.0, "brow_projection": 1.0, "depth_scale": 1.0})
        marks = {"Eye": {"width": 0.45, "height": 0.13, "depth": {"white_m": 0.0004}}, "Brow": {"height": 0.04, "depth_m": 0.006, "proud_m": 0.004, "settle_m": 0.002}}
        self.assertEqual(variation.responded_marks(marks, response), marks)

    def test_features_follow_head_size_and_build_continuously_and_within_bounds(self):
        ## ARRANGE: heights across the bound and builds across the axis.
        heights = [1.6 + i * 0.01 for i in range(41)]
        tall = [variation.face_response(self._resolved(h, 1.0, 1.0)) for h in heights]
        ## ASSERT: depths follow the head's relative size (smaller on taller bodies, whose
        ## root scale would otherwise over-grow them); the eye's share of the head falls
        ## gently as the head grows; both monotone and continuous.
        depth = [r["depth_scale"] for r in tall]
        eye = [r["eye_scale"] for r in tall]
        self.assertEqual(depth, sorted(depth, reverse=True))
        self.assertEqual(eye, sorted(eye, reverse=True))
        self.assertLess(max(_steps(eye)), 0.002)
        self.assertTrue(0.97 < eye[-1] < 1.0 < eye[0] < 1.03)
        ## PERTURB: muscularity raises the brow's mass, linear between its anchors.
        lean, strong = (variation.face_response(self._resolved(1.8, f, m)) for f, m in ((0.85, 0.8), (1.15, 1.25)))
        self.assertEqual((lean["brow_thickness"], strong["brow_thickness"]), (0.94, 1.12))
        self.assertEqual((lean["brow_projection"], strong["brow_projection"]), (0.95, 1.15))


if __name__ == "__main__":
    unittest.main()
