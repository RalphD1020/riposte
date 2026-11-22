import unittest

from character_modeling import pose_suite


class PoseSuiteContract(unittest.TestCase):
    def test_the_shipped_fixtures_satisfy_the_contract(self):
        self.assertEqual(pose_suite.problems(), [])

    def test_a_broken_fixture_is_reported_not_accepted(self):
        bad = {"id": "bad", "source": "x", "stress": "y", "arms": {"L": {"elevate": 10.0, "clavicle": 0.9, "spin": 1.0}},
               "fractions": (0.0,)}
        saved = pose_suite.FIXTURES
        pose_suite.FIXTURES = saved + (bad, dict(bad))
        try:
            found = pose_suite.problems()
        finally:
            pose_suite.FIXTURES = saved
        self.assertTrue(any("clavicle share" in p for p in found))
        self.assertTrue(any("unknown arm keys" in p for p in found))
        self.assertTrue(any("fractions" in p for p in found))
        self.assertTrue(any("repeated" in p for p in found))

    def test_samples_walk_intermediate_fractions_and_scale_angles_not_shares(self):
        raise_samples = [s for s in pose_suite.samples() if s["id"] == "arms_raise"]
        self.assertEqual([s["t"] for s in raise_samples], [0.25, 0.5, 1.0])
        half = raise_samples[1]["arms"]["L"]
        self.assertAlmostEqual(half["elevate"], 32.5)
        self.assertAlmostEqual(half["clavicle"], 0.3)

    def test_the_acceptance_raise_moves_the_shoulder_girdle_and_the_diagnostic_does_not(self):
        self.assertGreater(pose_suite.fixture("arms_raise")["arms"]["L"]["clavicle"], 0.0)
        diag = pose_suite.fixture("arms_raise_no_clavicle")
        self.assertTrue(diag["diagnostic"])
        self.assertEqual(diag["arms"]["L"]["clavicle"], 0.0)
        ids = {s["id"] for s in pose_suite.samples(include_diagnostic=False)}
        self.assertNotIn("arms_raise_no_clavicle", ids)

    def test_head_motion_is_sampled_and_unknown_head_keys_are_reported(self):
        down = [s for s in pose_suite.samples() if s["id"] == "head_down"]
        self.assertAlmostEqual(down[1]["head"]["pitch"], 17.5)
        saved = pose_suite.FIXTURES
        pose_suite.FIXTURES = saved + ({"id": "nod", "source": "x", "stress": "y", "head": {"roll": 5.0}},)
        try:
            found = pose_suite.problems()
        finally:
            pose_suite.FIXTURES = saved
        self.assertTrue(any("unknown head keys" in p for p in found))

    def test_an_unknown_fixture_is_a_key_error(self):
        with self.assertRaises(KeyError):
            pose_suite.fixture("missing")

    def test_horizontal_is_the_a_pose_drop(self):
        self.assertEqual(pose_suite.fixture("arms_horizontal")["arms"]["L"]["elevate"], pose_suite.HORIZONTAL)


if __name__ == "__main__":
    unittest.main()
