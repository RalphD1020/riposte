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

    def test_the_jaw_stations_move_the_corners_not_the_chin_centre(self):
        ## ARRANGE: chart points: the mandibular corner, a chin corner, the chin's centre.
        def at(u, v, d):
            return (u * FRAME["half_width"], FRAME["front"] + d * (FRAME["back"] - FRAME["front"]), FRAME["low"] + v * FRAME["height"])
        jaw_corner, chin_corner, chin_centre = at(0.80, 0.15, 0.48), at(0.30, 0.04, 0.05), at(0.0, 0.04, 0.05)
        ## ACT
        jaw = variation.head_displacement(jaw_corner, FRAME, {"jaw_angle": 1.0})
        corner = variation.head_displacement(chin_corner, FRAME, {"chin_corner": 1.0})
        centre = variation.head_displacement(chin_centre, FRAME, {"chin_corner": 1.0})
        ## ASSERT: the mandibular corner moves out and forward (away from a lean neck behind
        ## it, never down into it); the chin's corners move out and down; its centre (height,
        ## projection) barely moves; all within the 1-3 mm budget.
        self.assertGreater(jaw[0], 0.0019)
        self.assertLess(jaw[1], -0.0014)
        self.assertEqual(jaw[2], 0.0)
        self.assertGreater(corner[0], 0.001)
        self.assertLess(corner[2], -0.0008)
        self.assertLess(max(abs(c) for c in centre), 0.0001)
        for move in (jaw, corner):
            self.assertLessEqual(max(abs(c) for c in move), 0.003)

    def test_the_submental_lift_raises_the_underside_and_leaves_the_chin_pad(self):
        ## ARRANGE: the chin pad (front of the underside), the submental region behind it, the
        ## jaw's side edge and the face mask's lower boundary corner (jaw_low).
        def at(u, v, d):
            return (u * FRAME["half_width"], FRAME["front"] + d * (FRAME["back"] - FRAME["front"]), FRAME["low"] + v * FRAME["height"])
        pad, submental, side_edge, jaw_low = at(0.0, 0.02, 0.05), at(0.0, 0.02, 0.45), at(0.85, 0.05, 0.45), at(0.30, 0.04, 0.10)
        params = {"submental_lift": 1.0}
        ## ACT / ASSERT: only the submental region rises (never the pad, the side edge or the
        ## mask's boundary), and it only rises (no shelf pushed forward or sideways).
        lifted = variation.head_displacement(submental, FRAME, params)
        self.assertGreater(lifted[2], 0.0035)
        self.assertEqual((lifted[0], lifted[1]), (0.0, 0.0))
        for point in (pad, side_edge, jaw_low):
            self.assertLess(abs(variation.head_displacement(point, FRAME, params)[2]), 0.0002)
        ## The jaw's lower border rises toward the corner; the chin pad stays.
        border = variation.head_displacement(at(0.68, 0.03, 0.48), FRAME, {"mandible_border": 1.0})
        self.assertGreater(border[2], 0.0035)
        self.assertLess(abs(variation.head_displacement(pad, FRAME, {"mandible_border": 1.0})[2]), 0.0002)
        ## Behind the corner the jaw's side edge rises toward the ear; ahead of it, it stays.
        behind, corner = at(0.80, 0.08, 0.66), at(0.80, 0.08, 0.40)
        self.assertGreater(variation.head_displacement(behind, FRAME, {"ramus_recess": 1.0})[2], 0.0035)
        self.assertEqual(variation.head_displacement(corner, FRAME, {"ramus_recess": 1.0}), (0.0, 0.0, 0.0))
        ## The anime_jaw study is layered on heroic_jaw: the checkpoint is the study without it.
        self.assertNotIn("submental_lift", variation.HEAD_STUDY["heroic_jaw"])
        self.assertEqual(set(variation.HEAD_STUDY["anime_jaw"]) - set(variation.HEAD_FIELDS), set())

    def test_the_submental_profile_rises_to_the_junction_and_never_folds(self):
        ## ARRANGE: the midline underside from the chin pad back to the junction, and a column
        ## of heights at the junction (the lift's strongest depth), at the study's value.
        def at(u, v, d):
            return (u * FRAME["half_width"], FRAME["front"] + d * (FRAME["back"] - FRAME["front"]), FRAME["low"] + v * FRAME["height"])
        params = {"submental_profile": variation.HEAD_STUDY["submental_fix"]["submental_profile"]}
        ## ACT / ASSERT: the lift grows from the pad to the junction (the chin stays lowest)...
        lifts = [variation.head_displacement(at(0.0, 0.0, d), FRAME, params)[2] for d in (0.10, 0.20, 0.28, 0.35)]
        self.assertEqual(lifts[0], 0.0)
        self.assertEqual(lifts, sorted(lifts))
        self.assertGreater(lifts[-1], 0.010)
        ## ...and moved heights keep their order (no fold) through the height band's ramp.
        column = [FRAME["low"] + v * FRAME["height"] + variation.head_displacement(at(0.0, v, 0.36), FRAME, params)[2]
                  for v in [i / 100.0 for i in range(0, 25)]]
        self.assertEqual(column, sorted(column))


class PhysiqueDesign(unittest.TestCase):
    """Three-physique head design: studies anchored at lean, reference and strongman,
    piecewise linear on the build coordinate, independent of height."""

    DESIGN = {"lean": {"lean_face": 1.0, "submental_fix": 1.0}, "reference": {"reference_face": 1.0, "submental_fix": 1.0},
              "strongman": {"heroic_jaw": 1.0, "submental_fix": 1.0}}

    def test_the_build_coordinate_spans_the_archetypes_and_ignores_height(self):
        for name, frame, muscle in variation.ARCHETYPES:
            expected = {"lean": -1.0, "reference": 0.0, "strongman": 1.0}[name]
            for h in variation.SWEEP_HEIGHTS_M:
                self.assertAlmostEqual(variation.design_coordinate({"height_m": h, "frame_build": frame, "muscularity": muscle}), expected)

    def test_each_anchor_gets_its_own_studies_and_between_is_linear(self):
        ## ACT: at each anchor and halfway between reference and strongman.
        lean = variation.designed_study(self.DESIGN, {"height_m": 1.8, "frame_build": 0.85, "muscularity": 0.8})
        strong = variation.designed_study(self.DESIGN, {"height_m": 2.0, "frame_build": 1.15, "muscularity": 1.25})
        half = variation.designed_study(self.DESIGN, {"height_m": 1.6, "frame_build": 1.075, "muscularity": 1.125})
        ## ASSERT: exact at the anchors, linear between, shared studies constant.
        self.assertEqual((lean["lean_face"], lean["reference_face"], lean["heroic_jaw"]), (1.0, 0.0, 0.0))
        self.assertEqual((strong["heroic_jaw"], strong["reference_face"]), (1.0, 0.0))
        self.assertAlmostEqual(half["heroic_jaw"], 0.5)
        self.assertAlmostEqual(half["reference_face"], 0.5)
        self.assertEqual({lean["submental_fix"], strong["submental_fix"], half["submental_fix"]}, {1.0})
        ## PERTURB: no design, no studies.
        self.assertEqual(variation.designed_study(None, {"height_m": 1.8, "frame_build": 1.0, "muscularity": 1.0}), {})

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


class HeadStudies(unittest.TestCase):
    def test_a_head_study_offsets_the_resolved_parameters_by_its_value(self):
        ## ARRANGE: a resolved identity head and the anime head study.
        head = resolved(WOLF)["head"]["parameters"]
        study = variation.HEAD_STUDY["anime_head"]
        self.assertTrue(set(study) <= set(variation.HEAD_FIELDS), "fixture: the study moves morph fields only")
        ## ACT
        full = variation.studied_head(head, {"anime_head": 1.0})
        half = variation.studied_head(head, {"anime_head": 0.5})
        ## ASSERT: each named parameter moves by its amount times the value; the rest and the
        ## input are untouched; no study is the identity's head.
        for name, amount in study.items():
            self.assertAlmostEqual(full[name], head.get(name, 0.0) + amount)
            self.assertAlmostEqual(half[name], head.get(name, 0.0) + 0.5 * amount)
        self.assertEqual({k: v for k, v in full.items() if k not in study}, {k: v for k, v in head.items() if k not in study})
        self.assertEqual(variation.studied_head(head), head)
        ## PERTURB: an unknown study fails closed.
        with self.assertRaises(ValueError):
            variation.studied_head(head, {"chibi": 1.0})


class LimbGirth(unittest.TestCase):
    def test_mass_slims_lean_muscle_bellies_and_leaves_joints_and_heavier_builds(self):
        ## ARRANGE: the lean profile's muscle bellies and joints.
        thigh, calf, knee, ankle = 0.40, 0.20, 0.285, 0.07
        upper_arm, forearm, wrist = 0.22, 0.55, 0.74
        ## ACT / ASSERT: at the lean anchor the bellies slim far more than the joints (the
        ## fleshy-versus-bony scaling of measured girths); the gluteal fold and the hand
        ## never change; the reference and everything heavier is untouched.
        lean = lambda limb, t: variation.girth_factor(-1.0, limb, t)  # noqa: E731
        self.assertLess(lean("leg", thigh), 0.9)
        self.assertLess(lean("leg", calf), 0.92)
        self.assertGreater(lean("leg", knee), 0.95)
        self.assertGreater(lean("leg", ankle), 0.97)
        self.assertLess(lean("arm", upper_arm), lean("arm", forearm))
        self.assertEqual(lean("arm", wrist), 1.0)
        self.assertEqual(lean("leg", 0.47), 1.0)
        self.assertEqual(lean("leg", 0.9), 1.0)
        for mass in (0.0, 0.5, 1.0, 2.0):
            self.assertEqual(variation.girth_factor(mass, "leg", thigh), 1.0)
        ## The strongman's distal fullness (opt-in): the calf and forearm bellies grow, the
        ## joints and the thigh hold; halfway is half; never below the reference.
        strong = lambda limb, t: variation.girth_factor(1.0, limb, t, True)  # noqa: E731
        self.assertGreater(strong("leg", calf), 1.04)
        self.assertGreater(strong("arm", 0.5), 1.05)
        for limb, joint in (("leg", knee), ("leg", ankle), ("arm", wrist), ("arm", 0.40), ("leg", thigh)):
            self.assertEqual(strong(limb, joint), 1.0)
        self.assertAlmostEqual(variation.girth_factor(0.5, "leg", calf, True), 0.5 * (1.0 + strong("leg", calf)))
        self.assertEqual(variation.girth_factor(0.0, "leg", calf, True), 1.0)
        self.assertEqual(variation.girth_factor(-1.0, "leg", calf, True), lean("leg", calf))
        ## PERTURB: halfway to lean is halfway in factor; past lean it is held.
        self.assertAlmostEqual(variation.girth_factor(-0.5, "leg", thigh), 0.5 * (1.0 + lean("leg", thigh)))
        self.assertAlmostEqual(variation.girth_factor(-3.0, "arm", upper_arm), lean("arm", upper_arm))

    def test_the_head_plane_study_stays_below_the_eyes(self):
        ## ARRANGE / ACT / ASSERT: its fields are head fields, none of them the cranium's or
        ## a field whose window reaches the eye panel (the cheekbone's).
        study = variation.HEAD_STUDY["anime_planes"]
        self.assertTrue(set(study) <= set(variation.HEAD_FIELDS))
        self.assertFalse(set(study) & {"cranial_width", "cranial_depth", "cranial_height", "cheekbone_width",
                                       "cheekbone_depth", "brow_strength"})


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

    def test_the_sweep_reaches_every_build_at_every_height(self):
        ## ARRANGE / ACT
        rows = variation.sweep()
        ## ASSERT: five heights x three archetypes, the reference row the approved default;
        ## the matrix holds all eight combinations of the body-input extremes.
        self.assertEqual(len(rows), len(variation.SWEEP_HEIGHTS_M) * len(variation.ARCHETYPES))
        self.assertIn(("reference_180", 1.80, 1.00, 1.00), rows)
        corners = {(h, f, m) for _n, h, f, m in variation.BOUNDARY_MATRIX}
        self.assertLessEqual(set(itertools.product((1.60, 2.00), (0.85, 1.15), (0.80, 1.25))), corners)

    def test_the_resolved_fingerprint_follows_the_physical_inputs(self):
        ## ARRANGE
        body = {"height_m": 1.8, "frame_build": 1.0, "muscularity": 1.0}
        ## PERTURB
        taller = dict(body, height_m=1.81)
        ## ACT / ASSERT: the same inputs, the same fingerprint; a change invalidates it.
        self.assertEqual(variation.fingerprint(resolved(body)), variation.fingerprint(resolved(dict(body))))
        self.assertNotEqual(variation.fingerprint(resolved(body)), variation.fingerprint(resolved(taller)))

    def test_every_body_input_extreme_resolves(self):
        for values in itertools.product((1.60, 2.00), (0.85, 1.15), (0.80, 1.25)):
            body = dict(zip(("height_m", "frame_build", "muscularity"), values))
            out = resolved(body)
            self.assertEqual(out["body"], body)


if __name__ == "__main__":
    unittest.main()
