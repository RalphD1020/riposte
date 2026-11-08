"""FACE-EXPRESSION-001: one preset set for every character, combinations of the shared
eye-assembly channels per side; neutral is the rest geometry, dead shows the X."""
import json
import pathlib
import re
import unittest

from character_modeling import expressions, eye_assembly

ROOT = pathlib.Path(__file__).resolve().parents[3]
CHARACTERS = ROOT / "art-src" / "blender" / "characters"
ASPECT = 0.2765 / 0.1084


def marks_of(manifest):
    return json.loads(manifest.read_text(encoding="utf-8"))["identity"]["face"]["marks"]


class SharedExpressions(unittest.TestCase):

    def test_the_set_is_neutral_dead_and_the_keyed_presets(self):
        ## ARRANGE / ACT
        names = list(expressions.EXPRESSIONS)
        ## ASSERT: neutral first (the rest geometry, no channel), dead shows the X and moves
        ## nothing, the keyed presets are channel combinations of the shared channels only.
        self.assertEqual(names[0], expressions.NEUTRAL)
        self.assertEqual(expressions.weights(expressions.NEUTRAL, "L"), {})
        self.assertEqual(expressions.PRESETS[expressions.DEAD]["eyes"], "x")
        self.assertEqual(expressions.weights(expressions.DEAD, "R"), {})
        self.assertEqual(expressions.KEYED, ("confident", "aggressive", "alert"))
        self.assertEqual(expressions.problems(), [])

    def test_presets_are_asymmetric_and_gaze_and_blink_add_channels(self):
        ## ARRANGE
        name = "aggressive"
        ## ACT
        left, right = expressions.weights(name, "L"), expressions.weights(name, "R")
        looking = expressions.weights(name, "L", gaze=(0.5, -0.4), blink=0.5)
        ## ASSERT: the sides differ (designed asymmetry, not a mirror); a gaze and a blink add
        ## their channels to the preset's.
        self.assertNotEqual(left, right)
        self.assertEqual(set(left), set(right))
        self.assertEqual(looking["gaze_left"], 0.5)
        self.assertAlmostEqual(looking["gaze_down"], 0.2)
        self.assertEqual(looking[eye_assembly.BLINK], 0.5)
        closed = expressions.weights(name, "L", gaze=(0.5, -0.4), blink=1.0)
        self.assertEqual(closed["gaze_down"], 0.0)
        self.assertEqual(closed["gaze_left"], 0.5)
        with self.assertRaises(KeyError):
            expressions.weights("smirk", "L")

    def test_a_blink_closes_from_rest_under_every_preset(self):
        ## ARRANGE: Wolf's eye and every keyed preset (each lowers or raises a lid).
        eye = marks_of(CHARACTERS / "wolf" / "wolf.assembly.json")["Eye"]
        lids = set(eye_assembly.UPPER_CHANNELS + eye_assembly.LOWER_CHANNELS)
        self.assertTrue(all(lids & set(expressions.PRESETS[n]["L"]) for n in expressions.KEYED), "fixture: presets move lids")
        for name in expressions.KEYED:
            for side in ("L", "R"):
                ## ACT
                closed = expressions.weights(name, side, blink=1.0)
                half = expressions.weights(name, side, blink=0.5)
                ## ASSERT: the lid channels fade with the blink (half at a half blink, gone
                ## when closed), the brows keep the expression, and the closed eye is one
                ## clean line (no edge crossing the other).
                for channel, w in expressions.PRESETS[name][side].items():
                    expected = 0.0 if channel in lids else w
                    self.assertAlmostEqual(closed[channel], expected)
                    self.assertAlmostEqual(half[channel], 0.5 * w if channel in lids else w)
                self.assertEqual(eye_assembly.state_problems(eye, closed, side), [])

    def test_an_unknown_channel_or_weight_is_a_problem(self):
        ## ARRANGE
        saved = expressions.PRESETS["alert"]["L"]
        try:
            ## PERTURB
            expressions.PRESETS["alert"]["L"] = dict(saved, brow_wiggle=0.5, lid_upper_open=1.4)
            ## ACT
            found = expressions.problems()
        finally:
            expressions.PRESETS["alert"]["L"] = saved
        ## ASSERT
        self.assertEqual(len(found), 2, found)

    def test_godot_shows_exactly_the_shared_set(self):
        ## ARRANGE: the presentation's mirror of the set (no compiler reads across).
        source = (ROOT / "game" / "src" / "presentation" / "entities" / "face_presentation.gd").read_text(encoding="utf-8")
        names = dict(re.findall(r'^const (\w+) := &"(\w+)"$', source, re.MULTILINE))
        listed = re.search(r"^const EXPRESSIONS: Array\[StringName\] = \[([^\]]*)\]", source, re.MULTILINE).group(1)
        keyed = re.search(r"^const KEYED: Array\[StringName\] = \[([^\]]*)\]", source, re.MULTILINE).group(1)
        ## ACT
        shown = [names[n.strip()] for n in listed.split(",")]
        blended = tuple(names[n.strip()] for n in keyed.split(","))
        ## ASSERT: the same names in the same order, the same blend shapes.
        self.assertEqual(shown, list(expressions.EXPRESSIONS))
        self.assertEqual(blended, expressions.KEYED)

    def test_godot_mirrors_every_preset_weight_and_gaze(self):
        ## ARRANGE: the presentation's PRESETS table (no compiler reads across).
        source = (ROOT / "game" / "src" / "presentation" / "entities" / "face_presentation.gd").read_text(encoding="utf-8")
        names = dict(re.findall(r'^const (\w+) := &"(\w+)"$', source, re.MULTILINE))
        table = re.search(r"^const PRESETS := \{\n(.*?)\n\}", source, re.MULTILINE | re.DOTALL).group(1)
        ## ACT
        mirrored = {}
        for const, body in re.findall(r"^\t(\w+): \{\n(.*?)\n\t\},", table, re.MULTILINE | re.DOTALL):
            sides = {s: dict((k, float(v)) for k, v in re.findall(r'"(\w+)": ([-\d.]+)', w))
                     for s, w in re.findall(r'"([LR])": \{([^}]*)\}', body)}
            gaze = tuple(float(x) for x in re.search(r'"gaze": Vector2\(([-\d.]+), ([-\d.]+)\)', body).groups())
            mirrored[names[const]] = dict(sides, gaze=gaze)
        ## ASSERT: every keyed preset, per side and its gaze, exactly the shared table.
        self.assertEqual(set(mirrored), set(expressions.KEYED))
        for name, preset in mirrored.items():
            for side in ("L", "R"):
                self.assertEqual(preset[side], expressions.PRESETS[name][side], (name, side))
            self.assertEqual(preset["gaze"], tuple(expressions.PRESETS[name]["gaze"]), name)

    def test_no_character_carries_its_own_expressions(self):
        ## ARRANGE: every character manifest.
        manifests = sorted(CHARACTERS.glob("*/*.assembly.json"))
        self.assertTrue(manifests)
        for manifest in manifests:
            face = json.loads(manifest.read_text(encoding="utf-8")).get("identity", {}).get("face", {})
            ## ASSERT: the set is shared, never per character.
            self.assertNotIn("expressions", face, manifest)


if __name__ == "__main__":
    unittest.main()
