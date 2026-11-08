"""TEST-TRUTH: art iterations (ART-ITERATION-001). Fixture: a repository root and a fixed
time (ARRANGE); perturbation: malformed names, impossible dates, paths outside the one
location (PERTURB); the production calls `iterations.name`, `name_problems`,
`path_problems` (ACT); contracts (ASSERT): names are YYYYMMDD_HHMM_<descriptive_name>,
real times, lowercase words; outputs live in exactly one iteration folder under ROOT."""

from __future__ import annotations

import os
import unittest
from datetime import datetime

from character_modeling import iterations

ROOT = os.path.abspath("repo")
WHEN = datetime(2026, 10, 31, 18, 45)


class Names(unittest.TestCase):
    def test_a_name_is_the_time_then_the_description(self):
        self.assertEqual(iterations.name("head_approval", WHEN), "20261031_1845_head_approval")
        self.assertEqual(iterations.name_problems("20261031_1845_head_approval"), [])

    def test_malformed_names_are_refused(self):
        for bad in ("head_approval", "20261031_head", "20261031_1845_Head", "20261031_1845_", "2026-10-31_1845_x",
                    "20261031_1845_head-approval", "20261031_1845_head__x"):
            self.assertTrue(iterations.name_problems(bad), bad)
        with self.assertRaises(ValueError):
            iterations.name("Head Approval", WHEN)

    def test_impossible_times_are_refused(self):
        self.assertTrue(iterations.name_problems("20261331_1845_x"))
        self.assertTrue(iterations.name_problems("20261031_2561_x"))


class Location(unittest.TestCase):
    def test_outputs_live_in_one_iteration_folder(self):
        good = os.path.join(ROOT, iterations.ROOT, "20261031_1845_head_approval", "candidate.blend")
        self.assertEqual(iterations.path_problems(good, ROOT), [])

    def test_outputs_elsewhere_or_unnamed_are_refused(self):
        self.assertTrue(iterations.path_problems(os.path.join(ROOT, ".reports", "male_base", "x.blend"), ROOT))
        self.assertTrue(iterations.path_problems(os.path.join(ROOT, iterations.ROOT, "head", "x.blend"), ROOT))
        self.assertTrue(iterations.path_problems(os.path.join(ROOT, iterations.ROOT, "x.blend"), ROOT))


if __name__ == "__main__":
    unittest.main()
