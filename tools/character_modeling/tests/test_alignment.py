"""CHARACTER-ALIGNMENT-001: a discrepancy is classified to its owning layer and fixed there, the
skin binding obeys the Godot-import contract, and Blender<->Godot landmarks agree after
conversion. The decision layer is pure: it labels outcomes, it does not measure geometry."""
import unittest

from character_modeling import alignment


class ClassifyTest(unittest.TestCase):
    def test_all_passing_measured_layers_owns_nothing(self):
        # ARRANGE every measured layer passes. ACT/ASSERT: no owning layer.
        checks = {alignment.LAYER_SOURCE: True, alignment.LAYER_WEIGHTS: True}
        self.assertIsNone(alignment.classify(checks))

    def test_empty_owns_nothing(self):
        self.assertIsNone(alignment.classify({}))

    def test_owner_is_the_first_failing_layer_in_dependency_order(self):
        # ARRANGE weights AND a later animation layer both fail; weights is earlier.
        # PERTURB: order must win over insertion order. ASSERT the earlier layer owns it.
        checks = {alignment.LAYER_ANIMATION: False, alignment.LAYER_WEIGHTS: False}
        self.assertEqual(alignment.classify(checks), alignment.LAYER_WEIGHTS)

    def test_each_layer_can_own_when_it_is_the_earliest_failure(self):
        for index, layer in enumerate(alignment.BOUNDARY_ORDER):
            # Every earlier layer passes; this one fails -> it owns the fix.
            checks = {earlier: True for earlier in alignment.BOUNDARY_ORDER[:index]}
            checks[layer] = False
            self.assertEqual(alignment.classify(checks), layer)

    def test_absent_layer_is_not_a_failure(self):
        # Only runtime measured and passing; earlier layers unmeasured -> owns nothing.
        self.assertIsNone(alignment.classify({alignment.LAYER_RUNTIME: True}))

    def test_unknown_layer_fails_closed(self):
        with self.assertRaises(ValueError):
            alignment.classify({"spine_vibes": False})


class FixOrderTest(unittest.TestCase):
    def test_offset_in_godot_checks_transforms_before_vertices(self):
        order = alignment.fix_order(alignment.SYMPTOM_OFFSET_IN_GODOT)
        self.assertEqual(order[0], alignment.LAYER_TRANSFORM)
        self.assertEqual(order[-1], alignment.LAYER_SOURCE)

    def test_wrong_when_posed_checks_skeleton_last(self):
        order = alignment.fix_order(alignment.SYMPTOM_WRONG_WHEN_POSED)
        self.assertEqual(order[0], alignment.LAYER_ANIMATION)
        self.assertLess(order.index(alignment.LAYER_WEIGHTS), order.index(alignment.LAYER_JOINT))

    def test_blender_ok_godot_wrong_checks_runtime_before_art(self):
        order = alignment.fix_order(alignment.SYMPTOM_BLENDER_OK_GODOT_WRONG)
        self.assertEqual(order[0], alignment.LAYER_RUNTIME)
        self.assertEqual(order[-1], alignment.LAYER_SOURCE)

    def test_unknown_symptom_fails_closed(self):
        with self.assertRaises(ValueError):
            alignment.fix_order("it_looks_weird")


class SkinContractTest(unittest.TestCase):
    def test_clean_four_influence_normalized_body_vertex_passes(self):
        influences = [("Chest", 0.5), ("Shoulder.L", 0.3), ("UpperArm.L", 0.1), ("Spine", 0.1)]
        self.assertEqual(alignment.skin_problems(influences), [])

    def test_empty_influences_are_not_reported_as_unnormalized(self):
        # A vertex with no influences is a different (unweighted) check; this one is silent.
        self.assertEqual(alignment.skin_problems([]), [])

    def test_over_the_limit_is_reported(self):
        influences = [("Chest", 0.2), ("Spine", 0.2), ("Hips", 0.2), ("Neck", 0.2), ("Head", 0.2)]
        problems = alignment.skin_problems(influences)
        self.assertTrue(any("limit" in p for p in problems))

    def test_non_deforming_bone_on_the_body_is_reported(self):
        influences = [("Chest", 0.5), ("SwordMount", 0.5)]
        problems = alignment.skin_problems(influences)
        self.assertTrue(any("SwordMount" in p for p in problems))

    def test_unnormalized_influences_are_reported(self):
        influences = [("Chest", 0.5), ("Spine", 0.2)]
        problems = alignment.skin_problems(influences)
        self.assertTrue(any("normalized" in p for p in problems))


class LandmarkParityTest(unittest.TestCase):
    def test_matching_landmarks_within_tolerance_pass(self):
        blender = {"Hand.L": (0.3, 0.1, 1.0)}
        godot = {"Hand.L": (0.3005, 0.1, 1.0)}
        self.assertEqual(alignment.landmark_parity_problems(blender, godot, 0.001), [])

    def test_a_landmark_beyond_tolerance_is_reported(self):
        blender = {"Hand.L": (0.3, 0.1, 1.0)}
        godot = {"Hand.L": (0.5, 0.1, 1.0)}
        problems = alignment.landmark_parity_problems(blender, godot, 0.001)
        self.assertTrue(any("Hand.L" in p and "differs" in p for p in problems))

    def test_a_landmark_on_one_side_only_is_a_parity_failure(self):
        problems = alignment.landmark_parity_problems({"Hand.L": (0, 0, 0)}, {}, 0.001)
        self.assertTrue(any("only one side" in p for p in problems))


if __name__ == "__main__":
    unittest.main()
