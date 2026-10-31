"""TEST-TRUTH: the variation resolver (CHARACTER-VARIATION-001). Each test states the
definition it starts from (ARRANGE), the input it moves (PERTURB), the resolver call (ACT)
and the contract it holds (ASSERT): Wolf resolves to the approved default and Wolf's
physique, the seven configurations are body inputs plus development and nothing else,
every input moves only what it declares, the head grows allometrically and never with
muscle, identity survives every physique, and the boundary matrix resolves deterministically."""

from __future__ import annotations

import itertools
import json
import unittest
from pathlib import Path

from character_modeling import head_profile, physique, variation
from character_modeling.parameters import BODY_BY_ID

CONFIGURATION = Path(__file__).resolve().parents[3] / "art-src" / "blender" / "characters" / "male_base.v2.configuration.json"
DOC = json.loads(CONFIGURATION.read_text(encoding="utf-8"))
WOLF = {"height_m": 1.8, "frame_build": 1.0, "muscularity": 1.0}
FRAME = {"low": 1.522, "height": 0.2765, "half_width": 0.1084, "front": -0.1527, "back": 0.1056}


def resolved(body, development=None, head=None):
    return variation.resolve({"body": body, "development": development or {}, "head": head or {}}, DOC)


class WolfIsTheApprovedDefault(unittest.TestCase):
    def test_wolf_resolves_to_the_default_configuration_and_his_physique(self):
        out = resolved(WOLF)
        self.assertEqual(set(out["parameters"].values()), {0.0})
        self.assertEqual(out["physique"], physique.resolve_physique(WOLF))
        self.assertEqual(out["physique"]["mass_kg"], 80.0)
        self.assertEqual(out["head"]["proportions"]["relative_scale"], 1.0)
        self.assertEqual(set(out["head"]["parameters"].values()), {0.0})
        self.assertEqual(out["head"]["neck_radial_scale"], 1.0)
        self.assertEqual(out["face"], {"eye_spacing_u": 0.0, "brow_tilt_deg": 0.0})

    def test_wolf_moves_no_head_vertex(self):
        out = resolved(WOLF)
        for point in ((0.05, -0.12, 1.64), (0.1, 0.0, 1.70), (0.0, -0.14, 1.55)):
            self.assertEqual(variation.head_displacement(point, FRAME, out["head"]["parameters"]), (0.0, 0.0, 0.0))


class ConfigurationsAreDefinitions(unittest.TestCase):
    def test_each_configuration_round_trips_through_body_inputs_and_development(self):
        for name, values in DOC["configurations"].items():
            definition = variation.configuration_definition(DOC["configurations"], name)
            expected = dict({k: 0.0 for k in variation.PHYSIQUE_PARAMETERS}, **{k: float(v) for k, v in values.items()})
            out = variation.physique_parameters(definition["body"], definition["development"])
            for key in variation.PHYSIQUE_PARAMETERS:
                self.assertAlmostEqual(out[key], expected[key], places=9, msg="%s.%s" % (name, key))

    def test_each_configuration_gets_exactly_its_own_head_profile(self):
        for name, values in DOC["configurations"].items():
            profile = variation.head_physique_profile(DOC["head_profiles"], DOC["configurations"], float(values.get("mass", 0.0)))
            self.assertEqual({k: v for k, v in profile.items() if v}, DOC["head_profiles"][name], name)

    def test_configuration_mass_follows_the_physique_resolver(self):
        heavy = variation.configuration_definition(DOC["configurations"], "extreme_heavy")
        lean = variation.configuration_definition(DOC["configurations"], "extreme_lean")
        self.assertGreater(physique.resolve_physique(heavy["body"])["mass_kg"], 80.0)
        self.assertLess(physique.resolve_physique(lean["body"])["mass_kg"], 80.0)


class InputsMoveOnlyWhatTheyDeclare(unittest.TestCase):
    def test_muscularity_moves_mass_and_never_the_skull(self):
        base, strong = resolved(WOLF), resolved(dict(WOLF, muscularity=1.25))
        self.assertEqual(strong["parameters"]["mass"], 1.0)
        self.assertEqual({k: v for k, v in strong["parameters"].items() if k != "mass"},
                         {k: v for k, v in base["parameters"].items() if k != "mass"})
        self.assertEqual(strong["head"]["proportions"], base["head"]["proportions"])
        for key in ("cranial_width", "cranial_depth", "cranial_height"):
            self.assertLessEqual(abs(strong["head"]["parameters"][key]), head_profile.PHYSIQUE_LIMIT.get(key, 1.0))
        self.assertGreater(strong["head"]["parameters"]["jaw_width"], 0.0)

    def test_frame_moves_breadth_and_the_skull_width_but_not_mass_parameter(self):
        broad = resolved(dict(WOLF, frame_build=1.15))
        self.assertEqual(broad["parameters"]["upper_body"], 1.0)
        self.assertAlmostEqual(broad["parameters"]["waist"], variation.FRAME_PARAMETERS["waist"])
        self.assertEqual(broad["parameters"]["mass"], 0.0)
        proportions = broad["head"]["proportions"]
        self.assertGreater(proportions["size_scale"], 1.0)
        self.assertGreater(proportions["width_scale"], 1.0)
        ## A larger skull, never a balloon: the head grows far less than the frame.
        self.assertLess(proportions["size_scale"] * proportions["width_scale"], 1.15)

    def test_height_scales_the_head_allometrically(self):
        for height in (1.60, 1.70, 1.90, 2.00):
            out = resolved(dict(WOLF, height_m=height))
            h = height / 1.8
            self.assertAlmostEqual(out["stature_scale"], h)
            self.assertAlmostEqual(out["head"]["proportions"]["size_scale"], h ** variation.HEAD_STATURE_EXPONENT)
            ## Taller: a smaller head relative to the body; never a constant head.
            self.assertEqual(out["head"]["proportions"]["relative_scale"] < 1.0, height > 1.8)
            self.assertEqual(set(out["parameters"].values()), {0.0})

    def test_development_never_moves_the_body_inputs_or_mass(self):
        out = resolved(WOLF, development={"chest": 0.5, "definition": 0.4})
        self.assertEqual(out["physique"], physique.resolve_physique(WOLF))
        self.assertEqual(out["parameters"]["chest"], 0.5)

    def test_unknown_development_and_out_of_range_parameters_are_refused_not_clamped(self):
        with self.assertRaises(ValueError):
            variation.physique_parameters(WOLF, {"mass": 0.2})
        with self.assertRaises(ValueError):
            variation.physique_parameters(dict(WOLF, frame_build=1.15), {"waist": 0.8})


class IdentityIsIndependentOfPhysique(unittest.TestCase):
    def test_identity_parameters_survive_every_physique(self):
        identity = {"archetype": "angular", "parameters": {"eye_spacing": 0.3, "brow_curvature": -0.2}}
        seen = set()
        for name in DOC["configurations"]:
            definition = variation.configuration_definition(DOC["configurations"], name)
            out = variation.resolve(dict(definition, head=identity), DOC)
            seen.add(json.dumps({k: v for k, v in out["head"]["parameters"].items()
                                 if head_profile.PARAMETERS[k][0] == "identity_only"}, sort_keys=True))
            self.assertAlmostEqual(out["face"]["eye_spacing_u"], 0.3 * variation.EYE_SPACING_U)
        self.assertEqual(len(seen), 1)

    def test_two_identities_on_one_body_differ_and_one_identity_on_two_bodies_keeps_its_face(self):
        broad = resolved(WOLF, head={"archetype": "broad"})["head"]["parameters"]
        elongated = resolved(WOLF, head={"archetype": "elongated"})["head"]["parameters"]
        self.assertNotEqual(broad, elongated)
        lean = resolved(dict(WOLF, muscularity=0.8), head={"archetype": "elongated"})["head"]["parameters"]
        for key, (kind, _reads) in head_profile.PARAMETERS.items():
            if kind == "identity_only":
                self.assertEqual(lean[key], elongated[key], key)

    def test_physique_profiles_never_touch_identity_only_fields_at_the_eyes(self):
        out = resolved(dict(WOLF, frame_build=1.15, muscularity=1.25))
        eye = (0.0363, -0.145, FRAME["low"] + variation.EYE_V * FRAME["height"])
        dx, _dy, _dz = variation.head_displacement(eye, FRAME, out["head"]["parameters"])
        self.assertLess(abs(dx), 0.0005)


class HeadFields(unittest.TestCase):
    def test_every_field_names_a_head_parameter_and_placement_is_not_geometry(self):
        self.assertTrue(set(variation.HEAD_FIELDS) <= set(head_profile.PARAMETERS))
        self.assertEqual(set(head_profile.PARAMETERS) - set(variation.HEAD_FIELDS), set(variation.PLACEMENT_PARAMETERS))

    def test_jaw_width_widens_the_jaw_and_leaves_the_crown(self):
        jaw, crown = (0.07, -0.05, 1.56), (0.06, 0.0, 1.79)
        params = {"jaw_width": 1.0}
        self.assertGreater(variation.head_displacement(jaw, FRAME, params)[0], 0.004)
        self.assertEqual(variation.head_displacement(crown, FRAME, params), (0.0, 0.0, 0.0))

    def test_fields_are_mirror_symmetric(self):
        params = {k: 0.7 for k in variation.HEAD_FIELDS}
        for point in ((0.05, -0.12, 1.64), (0.09, 0.02, 1.72), (0.04, -0.13, 1.56)):
            left = variation.head_displacement(point, FRAME, params)
            right = variation.head_displacement((-point[0],) + point[1:], FRAME, params)
            self.assertAlmostEqual(left[0], -right[0])
            self.assertAlmostEqual(left[1], right[1])
            self.assertAlmostEqual(left[2], right[2])


class BoundaryMatrix(unittest.TestCase):
    def test_the_matrix_covers_every_corner_of_the_three_inputs(self):
        names = {(h, f, m) for _n, h, f, m in variation.BOUNDARY_MATRIX}
        extremes = [(BODY_BY_ID[k].minimum, BODY_BY_ID[k].maximum) for k in ("height_m", "frame_build", "muscularity")]
        corners = {(h, f, m) for h, f, m in itertools.product(*extremes) if f == m or (f, m) in ((1.15, 1.25), (0.85, 0.8))}
        self.assertTrue({(1.6, 0.85, 0.8), (1.6, 1.15, 1.25), (2.0, 0.85, 0.8), (2.0, 1.15, 1.25)} <= names | corners)
        self.assertTrue({(1.6, 0.85, 0.8), (1.6, 1.15, 1.25), (2.0, 0.85, 0.8), (2.0, 1.15, 1.25),
                         (1.6, 1.0, 1.25), (2.0, 1.0, 0.8), (1.8, 1.0, 1.0)} <= names)

    def test_every_matrix_row_resolves_deterministically_inside_the_ranges(self):
        first, second = variation.matrix_report(), variation.matrix_report()
        self.assertEqual(first, second)
        for row in first["rows"]:
            self.assertLessEqual(row["hurt_radius_m"], row["push_radius_m"])
            for value in row["parameters"].values():
                self.assertLessEqual(abs(value), 1.0)
        self.assertEqual(first["head_outside_bounds"], [])
        low, high = first["mass_range_kg"]
        self.assertLess(low, 80.0)
        self.assertGreater(high, 80.0)

    def test_the_underweight_reading_names_the_short_lean_corner(self):
        self.assertEqual(variation.matrix_report()["below_underweight_bmi"], ["short_lean"])

    def test_every_body_input_extreme_resolves(self):
        for values in itertools.product((1.60, 2.00), (0.85, 1.15), (0.80, 1.25)):
            body = dict(zip(("height_m", "frame_build", "muscularity"), values))
            out = resolved(body)
            self.assertEqual(out["body"], body)


if __name__ == "__main__":
    unittest.main()
