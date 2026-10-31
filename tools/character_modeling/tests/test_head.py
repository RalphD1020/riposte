"""TEST-TRUTH: head identity and morphology (head_profile) and the HeadFitSurface face
checks (head_fit). Each test states its fixture (ARRANGE), the defect it adds (PERTURB),
the production call (ACT), and the contract (ASSERT). Real files: the base's
configuration (its physique-derived head profiles) and Wolf's assembly (his head)."""

from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path

from character_modeling import head_fit, head_profile

ROOT = Path(__file__).resolve().parents[3]
CHARACTERS = ROOT / "art-src" / "blender" / "characters"


def configuration():
    return json.loads((CHARACTERS / "male_base.configuration.json").read_text(encoding="utf-8"))


def wolf():
    return json.loads((CHARACTERS / "wolf" / "wolf.assembly.json").read_text(encoding="utf-8"))


def face():
    """A symmetric face: nose tip forward-most on the centre line, cheekbones the widest
    facial landmarks, the brow above and ahead of the eye."""
    half = {"temple": (0.1, -0.08, 1.69), "ear_root": (0.105, 0.0, 1.67), "brow_inner": (0.02, -0.131, 1.695),
            "brow_outer": (0.05, -0.122, 1.7), "eye_centre": (0.036, -0.121, 1.67), "cheek_peak": (0.066, -0.124, 1.637),
            "jaw_angle": (0.09, -0.02, 1.555)}
    out = {"crown": (0.0, -0.01, 1.8), "hairline_front": (0.0, -0.118, 1.757), "occipital": (0.0, 0.106, 1.67),
           "nape": (0.0, 0.07, 1.545), "bun_anchor": (0.0, 0.09, 1.71), "nose_bridge": (0.0, -0.137, 1.695),
           "nose_tip": (0.0, -0.153, 1.628), "chin": (0.0, -0.13, 1.548), "neck_base": (0.0, 0.0, 1.41)}
    for name, (x, y, z) in half.items():
        out["%s.L" % name] = (x, y, z)
        out["%s.R" % name] = (-x, y, z)
    return out


class Profiles(unittest.TestCase):
    def test_the_shipped_physique_profiles_cover_every_configuration_and_touch_no_identity(self):
        ## ARRANGE
        config = configuration()
        ## ACT / ASSERT
        self.assertEqual(head_profile.physique_problems(config["head_profiles"], config["configurations"]), [])
        self.assertEqual(config["head_profiles"]["default"], {})

    def test_a_physique_that_changes_identity_or_inflates_the_skull_is_refused(self):
        ## PERTURB: heavy moves the eye spacing; extreme_heavy doubles the skull; one profile lost.
        config = configuration()
        profiles = copy.deepcopy(config["head_profiles"])
        profiles["heavy"]["eye_spacing"] = 0.3
        profiles["extreme_heavy"]["cranial_width"] = 0.9
        del profiles["lean"]
        ## ACT
        problems = head_profile.physique_problems(profiles, config["configurations"])
        ## ASSERT
        self.assertTrue(any("eye_spacing is identity" in p for p in problems))
        self.assertTrue(any("cranial_width = 0.9 beyond the physique limit" in p for p in problems))
        self.assertTrue(any("missing for configurations ['lean']" in p for p in problems))

    def test_wolf_is_the_reference_head(self):
        ## ACT / ASSERT
        head = wolf()["identity"]["head"]
        self.assertEqual(head_profile.identity_problems(head), [])
        self.assertEqual(head["archetype"], "reference")

    def test_changing_the_configuration_never_changes_who_he_is(self):
        ## ARRANGE: an angular character with his own nose, on two bodies.
        identity = {"archetype": "angular", "parameters": {"nose_projection": 0.4}}
        profiles = configuration()["head_profiles"]
        ## ACT
        lean = head_profile.resolve(identity, profiles["lean"])
        heavy = head_profile.resolve(identity, profiles["extreme_heavy"])
        ## ASSERT: the body changed the jaw; the identity-only parameters are identical.
        self.assertLess(lean["jaw_width"], heavy["jaw_width"])
        for key, (kind, _reads) in head_profile.PARAMETERS.items():
            if kind == "identity_only":
                self.assertEqual(lean[key], heavy[key], key)
        self.assertEqual(lean["nose_projection"], head_profile.ARCHETYPES["angular"].get("nose_projection", 0.0) + 0.4)

    def test_two_archetypes_on_one_body_are_different_people(self):
        ## ARRANGE / ACT
        body = configuration()["head_profiles"]["default"]
        broad = head_profile.resolve({"archetype": "broad"}, body)
        elongated = head_profile.resolve({"archetype": "elongated"}, body)
        ## ASSERT
        self.assertNotEqual(broad, elongated)
        self.assertGreater(elongated["face_length"], broad["face_length"])

    def test_values_clamp_and_unknowns_are_refused(self):
        ## PERTURB: an archetype pushed past the range; an unknown archetype and parameter.
        resolved = head_profile.resolve({"archetype": "broad", "parameters": {"jaw_width": 0.9}}, {"jaw_width": 0.8})
        problems = head_profile.identity_problems({"archetype": "goblin", "parameters": {"horns": 1.0, "jaw_width": 3.0}})
        ## ASSERT
        self.assertEqual(resolved["jaw_width"], 1.0)
        for word in ("unknown archetype", "unknown head parameter horns", "jaw_width = 3.0 outside"):
            self.assertTrue(any(word in p for p in problems), word)


class FaceChecks(unittest.TestCase):
    def test_a_well_formed_face_has_no_finding(self):
        ## ARRANGE / ACT
        landmarks = face()
        measures, findings = head_fit.face_checks(landmarks, face_front_y=-0.153, cheekbone_bulge_m=0.004)
        ## ASSERT
        self.assertEqual(head_fit.landmark_problems(landmarks), [])
        self.assertEqual(findings, [])
        self.assertAlmostEqual(measures["nose_projection_m"], 0.029, places=4)
        self.assertAlmostEqual(measures["brow_eye_separation_m"], 0.025, places=4)

    def test_losing_the_nose_peak_or_the_cheekbone_width_is_hard(self):
        ## PERTURB: the brow projects ahead of the nose; the brow outer wider than the cheekbone.
        landmarks = face()
        landmarks["brow_outer.L"] = (0.08, -0.122, 1.7)
        landmarks["brow_outer.R"] = (-0.08, -0.122, 1.7)
        ## ACT
        _m, findings = head_fit.face_checks(landmarks, face_front_y=-0.16, cheekbone_bulge_m=0.004)
        ## ASSERT
        self.assertEqual(sorted((f["severity"], f["metric"]) for f in findings), [("hard", "cheekbone_width"), ("hard", "nose_peak")])

    def test_a_flat_panel_has_no_cheekbone_to_judge(self):
        ## ARRANGE: the approved v1 panel is planar (no apex).
        _m, findings = head_fit.face_checks(face(), face_front_y=-0.153, cheekbone_bulge_m=0.0002)
        ## ASSERT: advisory, never a hard failure of the approved face.
        self.assertEqual([(f["severity"], f["metric"]) for f in findings], [("advisory", "cheekbone_apex")])

    def test_asymmetry_and_a_buried_eye_are_warnings(self):
        ## PERTURB: one cheekbone 3 mm higher; both brows dropped onto the eye line.
        landmarks = face()
        landmarks["cheek_peak.R"] = (-0.066, -0.124, 1.64)
        landmarks["brow_inner.L"] = (0.02, -0.131, 1.668)
        landmarks["brow_inner.R"] = (-0.02, -0.131, 1.668)
        ## ACT
        _m, findings = head_fit.face_checks(landmarks, face_front_y=-0.153, cheekbone_bulge_m=0.004)
        ## ASSERT
        self.assertEqual(sorted((f["severity"], f["metric"]) for f in findings), [("warning", "eyelid_separation"), ("warning", "symmetry")])

    def test_identity_is_the_eye_line_the_nose_centre_and_the_crown(self):
        ## ARRANGE: a sculpted revision: deeper orbits and a longer nose, same eye line.
        reference, revised = face(), face()
        revised["eye_centre.L"] = (0.036, -0.117, 1.67)
        revised["nose_tip"] = (0.0, -0.16, 1.628)
        ## PERTURB: a revision that also drops the eyes 4 mm and shifts the nose off centre.
        moved = dict(revised)
        moved["eye_centre.L"] = (0.036, -0.117, 1.666)
        moved["nose_tip"] = (0.003, -0.16, 1.628)
        ## ACT / ASSERT
        self.assertEqual(head_fit.identity_problems(reference, revised), [])
        problems = head_fit.identity_problems(reference, moved)
        self.assertTrue(any("eye_centre.L height" in p for p in problems))
        self.assertTrue(any("nose_tip left the centre line" in p for p in problems))

    def test_a_missing_or_broken_landmark_is_named(self):
        ## PERTURB
        landmarks = face()
        del landmarks["bun_anchor"]
        landmarks["chin"] = (0.0, float("nan"), 1.5)
        ## ACT
        problems = head_fit.landmark_problems(landmarks)
        ## ASSERT
        self.assertTrue(any("bun_anchor" in p for p in problems))
        self.assertTrue(any("chin is not a finite point" in p for p in problems))


if __name__ == "__main__":
    unittest.main()
