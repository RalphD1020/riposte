"""FACE-EYE-001: the anime eye's structure on Wolf's eye profile, in its own design space:
the graphic aperture, the iris clipped to it as a drawing is, the lash line riding the upper
edge, every preset, blend, gaze extreme and the blink."""
import json
import pathlib
import unittest

from character_modeling import expressions, eye_assembly

ROOT = pathlib.Path(__file__).resolve().parents[3]
MANIFEST = ROOT / "art-src" / "blender" / "characters" / "wolf" / "wolf.assembly.json"


def wolf_eye():
    return json.loads(MANIFEST.read_text(encoding="utf-8"))["identity"]["face"]["marks"]["Eye"]


def states():
    """Every preset at 0.5 and 1 on each side, alone and with each gaze extreme, and blinks."""
    out = [("rest", "L", {}), ("blink", "L", {eye_assembly.BLINK: 1.0}), ("half blink", "R", {eye_assembly.BLINK: 0.5})]
    for name in expressions.EXPRESSIONS:
        for side in ("L", "R"):
            for gaze in (None, (1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)):
                for scale in (0.5, 1.0):
                    weights = {c: w * scale for c, w in expressions.weights(name, side, gaze=gaze).items()}
                    out.append(("%s x%.1f gaze %s" % (name, scale, gaze), side, weights))
    return out


class AnimeEye(unittest.TestCase):

    def test_wolf_profile_is_buildable_and_a_broken_one_is_not(self):
        ## ARRANGE
        profile = wolf_eye()
        ## PERTURB: no lash line; an edge short of the outer corner; layers out of order.
        no_line = {k: v for k, v in profile.items() if k != "line"}
        short = dict(profile, upper=profile["upper"][:-1])
        stacked = dict(profile, depth=dict(profile["depth"], line_m=0.0))
        ## ACT / ASSERT
        self.assertEqual(eye_assembly.profile_problems(profile), [])
        self.assertEqual(eye_assembly.profile_problems(no_line), ["eye profile lacks line"])
        self.assertTrue(any("from x -0.5 to 0.5" in p for p in eye_assembly.profile_problems(short)))
        self.assertTrue(any("layer depths" in p for p in eye_assembly.profile_problems(stacked)))

    def test_every_preset_blend_gaze_and_blink_is_structurally_sound(self):
        ## ARRANGE
        profile = wolf_eye()
        self.assertGreater(len(states()), 40, "fixture: the state matrix")
        ## ACT
        found = [p for label, side, weights in states() for p in eye_assembly.state_problems(profile, weights, side, label + " ")]
        ## ASSERT: the aperture open (closed for the blink), the pupil readable.
        self.assertEqual(found, [])

    def test_the_iris_is_clipped_to_the_aperture_in_every_state(self):
        ## ARRANGE
        profile = wolf_eye()
        for label, side, weights in states():
            ## ACT
            shape = eye_assembly.iris_shape(profile, side, weights)
            points = shape["iris"] + shape["rim"] + shape["pupil"] + shape["catchlight"]
            ## ASSERT: never outside the drawing (within the clip's inset).
            for x, y in points:
                lo = eye_assembly.edge(profile, "lower", x, weights)
                hi = eye_assembly.edge(profile, "upper", x, weights)
                self.assertTrue(-0.5 - 1e-9 <= x <= 0.5 + 1e-9 and lo - 1e-6 <= y <= max(hi, lo) + 1e-6, (label, side, x, y))

    def test_the_drawing_clips_a_tall_iris_like_anime_does(self):
        ## ARRANGE
        profile = wolf_eye()
        ## ACT
        rest = eye_assembly.iris_shape(profile, "L")
        top = max(y for _x, y in rest["iris"])
        ## ASSERT: the iris is taller than the opening, its top cut by the upper edge (the
        ## lash line sits there); the pupil mostly shows at rest.
        self.assertGreater(profile["iris"]["height"], max(eye_assembly.edge(profile, "upper", x) - eye_assembly.edge(profile, "lower", x)
                                                        for x in eye_assembly.columns()))
        self.assertLess(top, profile["iris"]["centre"][1] + 0.5 * profile["iris"]["height"])
        self.assertGreater(eye_assembly.pupil_visible(profile, "L"), 0.8)

    def test_the_checks_catch_a_closed_eye_and_a_hidden_pupil(self):
        ## ARRANGE
        profile = wolf_eye()
        ## PERTURB: the upper edge crushed onto the lower; the iris pushed up under the line.
        crushed = {"lid_upper_close": 1.0, "lid_upper_inner_down": 1.0, "lid_lower_raise": 1.0, "gaze_down": 1.0}
        high = dict(profile, iris=dict(profile["iris"], centre=[0.0, 0.62]))
        ## ACT
        closed = eye_assembly.state_problems(profile, crushed, "L")
        hidden = eye_assembly.state_problems(high, {}, "L")
        ## ASSERT
        self.assertTrue(any("aperture" in p for p in closed), closed)
        self.assertTrue(any("pupil shows" in p for p in hidden), hidden)

    def test_a_blink_closes_onto_the_lower_edge_and_keeps_a_thin_line(self):
        ## ARRANGE
        profile = wolf_eye()
        closed = {eye_assembly.BLINK: 1.0}
        ## ACT
        open_line = eye_assembly.lash_line(profile)["upper"]
        shut_line = eye_assembly.lash_line(profile, closed)["upper"]
        ## ASSERT: the upper edge meets the lower; the lash line thins to a line, never a smear.
        for x in eye_assembly.columns():
            self.assertAlmostEqual(eye_assembly.edge(profile, "upper", x, closed),
                                   eye_assembly.edge(profile, "lower", x, closed) + eye_assembly.BLINK_GAP, places=9)
        for (x, lo, hi), (_x, lo2, hi2) in zip(open_line, shut_line):
            self.assertAlmostEqual(hi2 - lo2 - profile["line"]["overlap"],
                                   (hi - lo - profile["line"]["overlap"]) * eye_assembly.BLINK_LINE_SHARE, places=9)

    def test_corners_hold_and_gaze_moves_both_irises_the_same_way(self):
        ## ARRANGE
        profile = wolf_eye()
        ## ACT / ASSERT: the drawing's corners never move under an edge channel.
        for edge_name in ("upper", "lower"):
            for channel in eye_assembly.APERTURE_CHANNELS:
                if channel == eye_assembly.BLINK and edge_name == "upper":
                    continue
                for x in (-0.5, 0.5):
                    self.assertAlmostEqual(eye_assembly.channel_delta(profile, edge_name, channel, x), 0.0, places=12)
        rest_l, rest_r = (eye_assembly.iris_centre(profile, s) for s in ("L", "R"))
        left_l = eye_assembly.iris_centre(profile, "L", {"gaze_left": 1.0})
        left_r = eye_assembly.iris_centre(profile, "R", {"gaze_left": 1.0})
        self.assertGreater(left_l[0], rest_l[0])
        self.assertLess(left_r[0], rest_r[0])

    def test_a_profile_sets_its_own_gaze_travel(self):
        ## ARRANGE: Wolf's eye with no travel of its own, and with a shorter one.
        profile = wolf_eye()
        self.assertNotIn("gaze", profile["iris"], "fixture: the default travel")
        short = dict(profile, iris=dict(profile["iris"], gaze={"x": 0.08, "up": 0.05, "down": 0.04}))
        cx, cy = profile["iris"]["centre"]
        ## ACT
        default = eye_assembly.iris_centre(profile, "L", {"gaze_left": 1.0, "gaze_up": 1.0})
        own = eye_assembly.iris_centre(short, "L", {"gaze_left": 1.0, "gaze_down": 1.0})
        ## ASSERT: the default constants, or the profile's own travel per direction.
        self.assertAlmostEqual(default[0], cx + eye_assembly.GAZE_X)
        self.assertAlmostEqual(default[1], cy + eye_assembly.GAZE_UP)
        self.assertAlmostEqual(own[0], cx + 0.08)
        self.assertAlmostEqual(own[1], cy - 0.04)

    def test_a_masked_eye_keeps_its_iris_and_pupil_round_in_every_state(self):
        ## ARRANGE: Wolf's eye with mask occlusion (a mask depth between catchlight and line).
        profile = wolf_eye()
        depth = dict(profile["depth"], mask_m=0.5 * (profile["depth"]["catchlight_m"] + profile["depth"]["line_m"]))
        masked = dict(profile, occlusion=eye_assembly.MASK, depth=depth)
        self.assertEqual(eye_assembly.profile_problems(masked), [])
        iris = masked["iris"]
        for label, side, weights in states():
            ## ACT
            shape = eye_assembly.iris_shape(masked, side, weights)
            cx, cy = eye_assembly.iris_centre(masked, side, weights)
            strip = eye_assembly.mask_strip(masked, weights)
            ## ASSERT: every ring point is on its ellipse (never clipped, never squashed); the
            ## mask's inner edges are the aperture's edges (the white's, by default); the
            ## pupil's visible share is the sampled area inside the aperture.
            for ring, (sx, sy) in (("iris", (1.0, 1.0)), ("pupil", (iris["pupil"], iris["pupil"] * iris.get("pupil_aspect", 1.0)))):
                for x, y in shape[ring]:
                    r = ((x - cx) / (0.5 * iris["width"] * sx)) ** 2 + ((y - cy) / (0.5 * iris["height"] * sy)) ** 2
                    self.assertAlmostEqual(r, 1.0, places=9, msg="%s %s" % (label, ring))
            for (x, lo, hi), (_x, top, _t), (_x2, low, _b) in zip(eye_assembly.white_strip(masked, weights), strip["upper"], strip["lower"]):
                self.assertAlmostEqual(top, hi)
                self.assertAlmostEqual(low, lo)
            seen = eye_assembly.pupil_visible(masked, side, weights)
            self.assertTrue(0.0 <= seen <= 1.0)
        ## PERTURB: a closed eye shows no pupil; a bad occlusion or mask depth is named.
        self.assertEqual(eye_assembly.pupil_visible(masked, "L", {eye_assembly.BLINK: 1.0}), 0.0)
        self.assertGreater(eye_assembly.pupil_visible(masked, "L", {}), 0.9)
        self.assertEqual(len(eye_assembly.profile_problems(dict(masked, occlusion="erase"))), 1)
        self.assertEqual(len(eye_assembly.profile_problems(dict(masked, depth=profile["depth"]))), 1)

    def test_a_backing_white_is_fixed_under_the_mask_in_every_state(self):
        ## ARRANGE: the masked eye with a fixed white (a moving white chords across the
        ## recessed panel in front of the iris between its keys).
        profile = wolf_eye()
        depth = dict(profile["depth"], mask_m=0.5 * (profile["depth"]["catchlight_m"] + profile["depth"]["line_m"]))
        masked = dict(profile, occlusion=eye_assembly.MASK, depth=depth)
        backed = dict(masked, white=eye_assembly.BACKING)
        self.assertEqual(eye_assembly.profile_problems(backed), [])
        backing = eye_assembly.white_strip(backed)
        for label, _side, weights in states():
            ## ACT
            strip = eye_assembly.mask_strip(backed, weights)
            ## ASSERT: the same backing in every state, holding the aperture, inside the mask's
            ## outer bounds (so the mask covers all of it the aperture does not show).
            self.assertEqual(eye_assembly.white_strip(backed, weights), backing, label)
            for (x, lo, hi), (_x, top, far_top), (_x2, low, far_low) in zip(backing, strip["upper"], strip["lower"]):
                self.assertLessEqual(lo, low + 1e-12, label)
                self.assertGreaterEqual(hi, min(top, eye_assembly.MASK_TOP) - 1e-12, label)
                self.assertTrue(far_low <= lo and hi <= far_top, label)
        ## ASSERT: only the fixed white drops its keys.
        self.assertEqual(eye_assembly.component_keys(backed, "eye"), ())
        self.assertEqual(eye_assembly.component_keys(masked, "eye"), eye_assembly.COMPONENT_KEYS["eye"])
        self.assertEqual(eye_assembly.component_keys(backed, "mask"), eye_assembly.COMPONENT_KEYS["mask"])
        ## PERTURB: an unknown white, or a backing without the mask to shape it.
        self.assertEqual(len(eye_assembly.profile_problems(dict(backed, white="sheet"))), 1)
        self.assertEqual(len(eye_assembly.profile_problems(dict(profile, white=eye_assembly.BACKING))), 1)
        self.assertFalse(eye_assembly.fixed_white(dict(profile, white=eye_assembly.BACKING)))

    def test_a_profile_can_keep_its_clipped_iris_further_inside(self):
        ## ARRANGE: a large iris (clipped at the corners) at a gaze into the inner corner.
        profile = wolf_eye()
        big = dict(profile, iris=dict(profile["iris"], width=0.6, height=0.9))
        inset = dict(big, iris=dict(big["iris"], clip_inset=0.05, lower_clip_inset=0.08))
        weights = {"gaze_right": 1.0, "gaze_down": 1.0}
        ## ACT
        loose = eye_assembly.iris_shape(big, "L", weights)["iris"]
        tight = eye_assembly.iris_shape(inset, "L", weights)["iris"]

        def margin(points, p):
            return min(min(eye_assembly.edge(p, "upper", x, weights) - y, y - eye_assembly.edge(p, "lower", x, weights))
                       for x, y in points if -0.5 < x < 0.5)
        ## ASSERT: the inset iris stays further from the aperture's edges, still inside it.
        self.assertGreater(margin(tight, inset), margin(loose, big))
        self.assertGreater(margin(tight, inset), 0.0)

    def test_components_carry_only_shared_channels(self):
        keyed = {c for keys in eye_assembly.COMPONENT_KEYS.values() for c in keys}
        self.assertEqual(keyed, set(eye_assembly.CHANNELS))
        self.assertEqual(set(eye_assembly.COMPONENTS), set(eye_assembly.MATERIALS))


if __name__ == "__main__":
    unittest.main()
