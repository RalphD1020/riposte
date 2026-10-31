"""TEST-TRUTH: hair design heuristics on synthetic locks. Each test states its fixture
(ARRANGE), the defect it adds (PERTURB), the production call (ACT), and the contract
(ASSERT). The heuristics are design warnings, so the contract is what they flag and
what they leave alone, never a verdict on the hair."""

from __future__ import annotations

import math
import unittest

from character_modeling import hair_design

REGIONS = {"rear_mass": ["Fall.*"], "front_sweep": ["Sweep.*"]}


def lock(name, width, bend_deg, tip_share, free=True, steps=6):
    """A lock of `steps` segments 0.04 m long turning `bend_deg` in total, its widths
    rising to `width` then tapering to `tip_share` of it."""
    points, heading, x, y = [(0.0, 0.0, 0.0)], 0.0, 0.0, 0.0
    for _ in range(steps):
        x += 0.04 * math.sin(math.radians(heading))
        y -= 0.04 * math.cos(math.radians(heading))
        points.append((x, 0.0, y))
        heading += bend_deg / max(1, steps - 1)
    widths = [width * 0.8, width, width, width * 0.9, width * 0.7, width * 0.5, width * tip_share]
    return {"name": name, "points": points, "widths": widths, "heights": [0.01] * len(widths), "free": free}


def varied():
    return [lock("Fall.01", 0.06, 18.0, 0.16), lock("Fall.02", 0.072, 30.0, 0.14),
            lock("Fall.03", 0.05, 9.0, 0.2), lock("Fall.04", 0.066, 24.0, 0.15)]


class HairDesign(unittest.TestCase):
    def test_varied_tapered_flowing_locks_raise_nothing(self):
        ## ARRANGE: widths, bends and tapers that differ lock to lock.
        ## ACT
        metrics, findings = hair_design.heuristics(varied(), REGIONS)
        ## ASSERT
        self.assertEqual(findings, [])
        self.assertAlmostEqual(metrics["Fall.02"]["tip_share"], 0.14, places=3)
        self.assertAlmostEqual(metrics["Fall.02"]["turn_deg"], 30.0, places=1)

    def test_uniform_straight_blunt_locks_are_the_dreadlock_look(self):
        ## PERTURB: four identical straight locks with blunt tips.
        locks = [lock("Fall.%02d" % i, 0.06, 0.0, 0.8) for i in range(1, 5)]
        ## ACT
        _metrics, findings = hair_design.heuristics(locks, REGIONS)
        ## ASSERT: each defect named once, in the right region, as a provisional heuristic.
        self.assertEqual(sorted(f["metric"] for f in findings), ["curvature", "tip_taper", "width_variation"])
        self.assertTrue(all(f["region"] == "rear_mass" and f["kind"] == "design_heuristic" and f["status"] == "provisional"
                            for f in findings))

    def test_identical_bends_are_repetitive_even_when_they_flow(self):
        ## PERTURB: varied widths, but every lock bends by the same angle.
        locks = [lock("Fall.%02d" % i, 0.05 + 0.008 * i, 20.0, 0.15) for i in range(1, 5)]
        ## ACT
        _metrics, findings = hair_design.heuristics(locks, REGIONS)
        ## ASSERT
        self.assertEqual([f["metric"] for f in findings], ["curvature_variation"])

    def test_tied_hair_combed_alike_is_not_called_repetitive(self):
        ## ARRANGE: tied locks (tips hidden in the bun) of varied width all bending alike.
        locks = [lock("Sweep.%02d" % i, 0.05 + 0.008 * i, 20.0, 0.3, free=False) for i in range(1, 5)]
        ## ACT
        _metrics, findings = hair_design.heuristics(locks, REGIONS)
        ## PERTURB: the same locks hanging free.
        _metrics, hanging = hair_design.heuristics([dict(l, free=True, name=l["name"].replace("Sweep", "Fall")) for l in locks], REGIONS)
        ## ASSERT
        self.assertEqual(findings, [])
        self.assertEqual([f["metric"] for f in hanging], ["curvature_variation"])

    def test_hidden_tips_are_not_judged_for_taper(self):
        ## ARRANGE: tied locks ending inside the bun have blunt but invisible ends.
        locks = [lock("Sweep.%02d" % i, 0.04 + 0.01 * i, 10.0 + 8 * i, 0.9, free=False) for i in range(1, 4)]
        ## ACT
        _metrics, findings = hair_design.heuristics(locks, REGIONS)
        ## ASSERT
        self.assertEqual(findings, [])

    def test_a_region_too_small_to_compare_is_only_judged_for_taper(self):
        ## PERTURB: two identical blunt locks — too few to call uniform.
        locks = [lock("Fall.01", 0.06, 0.0, 0.9), lock("Fall.02", 0.06, 0.0, 0.9)]
        ## ACT
        _metrics, findings = hair_design.heuristics(locks, REGIONS)
        ## ASSERT
        self.assertEqual([f["metric"] for f in findings], ["tip_taper"])
        self.assertEqual(findings[0]["value"], ["Fall.01", "Fall.02"])

    def test_locks_map_to_regions_by_pattern(self):
        ## ACT / ASSERT
        self.assertEqual(hair_design.region_of("Fall.07", REGIONS), "rear_mass")
        self.assertEqual(hair_design.region_of("Sweep.12", REGIONS), "front_sweep")
        self.assertIsNone(hair_design.region_of("Bun.Core", REGIONS))


if __name__ == "__main__":
    unittest.main()
