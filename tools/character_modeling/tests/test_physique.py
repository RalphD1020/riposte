"""TEST-TRUTH: the physique resolver. Each test states the body it starts from
(ARRANGE), the input it moves (PERTURB), the resolver call (ACT), and the
contract it holds (ASSERT): Wolf is exactly 1.0, every input moves only the
outputs it declares, mass is not strength, the torso circle follows its
documented policy and never exceeds the push footprint."""

from __future__ import annotations

import itertools
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from character_modeling import baseline, physique
from character_modeling.parameters import BODY_BY_ID, BODY_INPUTS

WOLF = {"height_m": 1.8, "frame_build": 1.0, "muscularity": 1.0}
CONTRACT = physique.APPLIED + physique.PROPOSED + ("mass_scale",)


def moved(body, key, value):
    return dict(body, **{key: value})


class WolfParity(unittest.TestCase):
    def test_wolf_resolves_to_exactly_the_reference(self):
        out = physique.resolve_physique(WOLF)
        self.assertEqual(out["mass_kg"], baseline.REFERENCE_MASS_KG)
        self.assertEqual(out["hurt_radius_m"], baseline.REFERENCE_HURT_RADIUS_M)
        self.assertEqual(out["push_radius_m"], baseline.REFERENCE_PUSH_RADIUS_M)
        for key, value in baseline.reference_geometry().items():
            self.assertEqual(out[key], value, key)
        for key in ("strength_scale", "traction_scale", "turn_support_scale", "stamina_capacity",
                    "stamina_recovery", "mass_scale", "acceleration_scale", "turn_acceleration_scale"):
            self.assertEqual(out[key], 1.0, key)

    def test_wolf_geometry_matches_the_gdscript_sources(self):
        self.assertEqual(baseline.game_geometry(), baseline.reference_geometry())

    def test_same_body_resolves_to_the_same_bits(self):
        body = {"height_m": 1.93, "frame_build": 1.07, "muscularity": 0.91}
        self.assertEqual(physique.resolve_physique(body), physique.resolve_physique(dict(body)))
        self.assertEqual(physique.render(physique.physique_document("x", body)),
                         physique.render(physique.physique_document("x", body)))


class InputIndependence(unittest.TestCase):
    def test_each_input_moves_only_the_outputs_it_declares(self):
        base = physique.resolve_physique(WOLF)
        for entry in BODY_INPUTS:
            for value in (entry.minimum, entry.maximum):
                out = physique.resolve_physique(moved(WOLF, entry.id, value))
                changed = {key for key in CONTRACT if abs(out[key] - base[key]) > 1e-12}
                self.assertTrue(changed, "%s=%s moved nothing" % (entry.id, value))
                self.assertLessEqual(changed, set(entry.affects), "%s=%s moved %s" % (
                    entry.id, value, sorted(changed - set(entry.affects))))

    def test_stamina_recovery_is_conditioning_and_no_body_input_moves_it(self):
        for corner in itertools.product(*((e.minimum, e.maximum) for e in BODY_INPUTS)):
            body = dict(zip((e.id for e in BODY_INPUTS), corner))
            self.assertEqual(physique.resolve_physique(body)["stamina_recovery"], 1.0)
        self.assertFalse(any("stamina_recovery" in e.affects for e in BODY_INPUTS))


class PhysicalOrdering(unittest.TestCase):
    def test_taller_is_heavier_stronger_and_wider_by_the_square_cube_laws(self):
        short = physique.resolve_physique(moved(WOLF, "height_m", 1.6))
        tall = physique.resolve_physique(moved(WOLF, "height_m", 2.0))
        h = 2.0 / 1.8
        self.assertAlmostEqual(tall["mass_kg"], 80.0 * h ** 3, places=9)
        self.assertAlmostEqual(tall["traction_scale"], h ** 2, places=12)
        self.assertAlmostEqual(tall["strength_scale"], h ** 3, places=12)
        self.assertAlmostEqual(tall["hurt_radius_m"], 0.195 * h ** physique.GIRTH_EXPONENT, places=12)
        self.assertGreater(tall["grip_radius_m"], short["grip_radius_m"])
        self.assertLess(tall["acceleration_scale"], 1.0, "force/mass falls as 1/h under similarity")
        self.assertLess(tall["turn_acceleration_scale"], short["turn_acceleration_scale"])

    def test_a_wider_frame_adds_mass_and_girth_but_not_strength(self):
        wide = physique.resolve_physique(moved(WOLF, "frame_build", 1.15))
        self.assertGreater(wide["mass_kg"], 80.0)
        self.assertGreater(wide["hurt_radius_m"], 0.195)
        self.assertGreater(wide["push_radius_m"], 0.27)
        self.assertEqual(wide["strength_scale"], 1.0)
        self.assertEqual(wide["turn_support_scale"], 1.0)
        self.assertLess(wide["turn_acceleration_scale"], 1.0, "more inertia, same torque: turns slower")

    def test_muscle_adds_force_faster_than_mass_and_never_the_footprint(self):
        strong = physique.resolve_physique(moved(WOLF, "muscularity", 1.25))
        self.assertAlmostEqual(strong["strength_scale"], 1.25, places=12)
        self.assertLess(strong["mass_scale"], strong["strength_scale"], "muscle is a share of the body")
        self.assertGreater(strong["acceleration_scale"], 1.0)
        self.assertEqual(strong["push_radius_m"], 0.27)
        girth = strong["hurt_radius_m"] / 0.195
        self.assertLess(girth, 1.25, "torso girth grows by the root of its section, not linearly")
        self.assertGreater(girth, 1.0)

    def test_mass_does_not_buy_strength(self):
        heavy_frame = physique.resolve_physique(moved(WOLF, "frame_build", 1.15))
        light_muscle = physique.resolve_physique(moved(WOLF, "muscularity", 1.1))
        self.assertGreater(heavy_frame["mass_kg"], light_muscle["mass_kg"])
        self.assertLess(heavy_frame["strength_scale"], light_muscle["strength_scale"])


class TorsoCircle(unittest.TestCase):
    def test_every_valid_body_keeps_the_hurt_circle_inside_the_footprint(self):
        steps = {e.id: [e.minimum + (e.maximum - e.minimum) * k / 4.0 for k in range(5)] for e in BODY_INPUTS}
        for values in itertools.product(*steps.values()):
            out = physique.resolve_physique(dict(zip(steps, values)))
            self.assertGreater(out["hurt_radius_m"], 0.0)
            self.assertLessEqual(out["hurt_radius_m"], out["push_radius_m"])

    def test_a_calibration_that_breaks_the_bound_errors_instead_of_clamping(self):
        with mock.patch.object(physique, "TORSO_MUSCLE_AREA_SHARE", 8.0):
            with self.assertRaisesRegex(ValueError, "must be positive and within push_radius"):
                physique.resolve_physique(moved(WOLF, "muscularity", 1.25))

    def test_the_convention_reproduces_wolfs_measured_baseline(self):
        section = physique.polygon_section(0.185, 0.154)
        self.assertEqual(len(section), physique.HURT_SECTION_SIDES)
        self.assertAlmostEqual(max(abs(x) for x, _ in section), 0.185, places=12)
        self.assertAlmostEqual(max(abs(y) for _, y in section), 0.154, places=12)
        radius = physique.enclosing_radius(section)
        self.assertAlmostEqual(radius, baseline.REFERENCE_HURT_RADIUS_M, delta=0.001)
        self.assertGreater(radius, 0.185, "not the ellipse semiaxis")
        self.assertLess(radius, (0.185 ** 2 + 0.154 ** 2) ** 0.5, "not the rectangle corner")


class BadBodies(unittest.TestCase):
    def test_out_of_range_missing_or_unknown_inputs_are_refused(self):
        for body in (moved(WOLF, "height_m", 2.2), moved(WOLF, "muscularity", True),
                     {"height_m": 1.8, "frame_build": 1.0}, dict(WOLF, weight=1.0)):
            with self.assertRaises(ValueError):
                physique.resolve_physique(body)
        self.assertEqual(physique.validate_body(WOLF), [])
        self.assertEqual(set(BODY_BY_ID), set(WOLF))


class CommittedPhysique(unittest.TestCase):
    def test_the_committed_wolf_file_matches_the_resolver(self):
        self.assertEqual(physique.physique_drift(), [])

    def test_a_hand_edited_or_missing_file_is_reported(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "wolf.physique.json"
            self.assertIn("wolf.physique.json is missing; run the physique writer",
                          physique.drift(path, "character.wolf", WOLF))
            physique.write_physique(path, "character.wolf", WOLF)
            self.assertEqual(physique.drift(path, "character.wolf", WOLF), [])
            path.write_text(path.read_text(encoding="utf-8").replace('"mass_kg": 80.0', '"mass_kg": 85.0'),
                            encoding="utf-8")
            self.assertIn("wolf.physique.json is stale; regenerate it from the profile",
                          physique.drift(path, "character.wolf", WOLF))


if __name__ == "__main__":
    unittest.main()
