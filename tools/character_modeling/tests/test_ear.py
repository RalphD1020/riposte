from __future__ import annotations

import unittest

from character_modeling import ear


class Design(unittest.TestCase):
    """The foundation's ear: a designed outline and relief (helix, antihelix, concha,
    tragus, lobule), placed from the head's chart, its root sunk into the skull."""

    def test_the_ear_spans_brow_to_nose_base_height(self):
        ## ARRANGE / ASSERT: the top at about brow height, the bottom at about the nose base.
        self.assertAlmostEqual(ear.EAR_HEIGHT, ear.EAR_TOP_V - ear.EAR_BOTTOM_V)
        self.assertTrue(0.62 <= ear.EAR_TOP_V <= 0.68)
        self.assertTrue(0.33 <= ear.EAR_BOTTOM_V <= 0.38)
        ## The root is never behind the head's mid-depth by more than a little.
        self.assertLessEqual(ear.ROOT_DEPTH_OFFSET, 0.05)

    def test_the_relief_reads_as_simplified_anatomy(self):
        ## ACT: front heights across the ear.
        front = lambda s, t: ear.relief(s, t)[0]
        ## ASSERT: the helix rim stands proud of the scapha inside it, thicker at the top;
        ## the antihelix stands proud of the scapha; the concha is the low bowl; the tragus
        ## rises at the front; the lobule has no rim.
        self.assertGreater(front(0.92, 0.45), front(0.80, 0.45))
        self.assertGreater(front(0.92, 0.2), front(0.92, 0.45))
        self.assertGreater(front(0.66, 0.35), front(0.80, 0.35))
        self.assertLess(front(0.1, 0.35), front(0.66, 0.35))
        self.assertGreater(front(0.72, ear.TRAGUS_T), front(0.72, ear.TRAGUS_T - 0.12))
        self.assertLess(front(0.92, 0.69), front(0.92, 0.45))

    def test_the_relief_is_continuous_at_the_concha_centre(self):
        ## ARRANGE: near the centre every direction meets the same bowl.
        values = [ear.relief(0.02, k / 40.0)[0] for k in range(40)]
        ## ASSERT: no jump between directions (the lobule only acts away from the centre).
        self.assertLess(max(values) - min(values), 0.002)

    def test_the_back_sheet_is_behind_the_front_and_they_meet_at_the_outline(self):
        for s in (0.0, 0.5, 0.95):
            for t in (0.0, 0.3, 0.7):
                front, back = ear.relief(s, t)
                self.assertLess(back, front)
        ## The outline ring is shared: one index set, inside the point list.
        points, quads, tris = ear.grid()
        ring = ear.outline_indices()
        self.assertEqual(len(ring), ear.AROUND)
        self.assertLess(max(ring), len(points))
        used = {i for f in list(quads) + list(tris) for i in f}
        self.assertEqual(used, set(range(len(points))))

    def test_the_attachment_arc_runs_from_the_lobule_front_to_the_helix_root(self):
        ## ASSERT: the tragus side is attached, the top and back of the helix and the lobule's
        ## bottom are free, and the arc ramps (the rim emerges gradually).
        self.assertEqual(ear.attachment(ear.TRAGUS_T), 1.0)
        self.assertEqual(ear.attachment(0.0), 1.0)
        self.assertEqual(ear.attachment(0.3), 0.0)
        self.assertEqual(ear.attachment(0.6), 0.0)
        self.assertTrue(0.0 < ear.attachment(0.06) < 1.0)
        ## The arc is sunk at the outline, so the front sheet there is lower than off it.
        self.assertLess(ear.relief(1.0, 0.0)[0], ear.relief(1.0, 0.3)[0])
        ## Only the arc's outer rings may shade as the skin; never the concha.
        weights = ear.root_blend()
        points, _q, _t = ear.grid()
        self.assertEqual(len(weights), len(points))
        self.assertEqual(weights[0], 0.0)
        ring = list(ear.outline_indices())
        self.assertEqual(weights[ring[0]], 1.0)
        self.assertEqual(weights[ring[len(ring) // 3]], 0.0)

    def test_the_root_sinks_into_the_skull_and_the_back_flares_out(self):
        ## ASSERT: ahead of the root the ear is below the skull's surface; behind it, out.
        self.assertLess(ear.placement(ear.ROOT_A + 0.05), 0.0)
        self.assertGreater(ear.placement(-0.35), 0.05)
        ## The root follows the skull fully; the free ear does not.
        self.assertEqual(ear.follow_weight(ear.ROOT_A), 1.0)
        self.assertEqual(ear.follow_weight(-0.3), 0.0)
        ## PERTURB: past the outline parameter's end the outline wraps (closed).
        self.assertEqual(ear.outline_at(1.25), ear.outline_at(0.25))
        ## A window's ramps: zero outside, one inside, between at the ramp.
        self.assertEqual(ear.band(0.5, (0.0, 0.1, 0.9, 1.0)), 1.0)
        self.assertEqual(ear.band(1.5, (0.0, 0.1, 0.9, 1.0)), 0.0)
        self.assertTrue(0.0 < ear.band(0.05, (0.0, 0.1, 0.9, 1.0)) < 1.0)
        self.assertTrue(0.0 < ear.band(0.95, (0.0, 0.1, 0.9, 1.0)) < 1.0)

    def test_the_designed_flare_follows_the_build_and_every_build_is_flatter(self):
        ## ARRANGE / ACT: the flare across the build coordinate, past both ends.
        flares = [ear.design_flare(c / 4.0) for c in range(-6, 7)]
        ## ASSERT: the anchors' values; rising from lean to strongman, held past the ends;
        ## all flatter than the undesigned ear.
        self.assertEqual((ear.design_flare(-1.0), ear.design_flare(0.0), ear.design_flare(1.0)), ear.DESIGN_FLARE_DEG)
        self.assertEqual(flares, sorted(flares))
        self.assertEqual(ear.design_flare(-3.0), ear.design_flare(-1.0))
        self.assertLess(max(flares), ear.FLARE_DEG)
        ## PERTURB: a flatter ear stands out less behind the root.
        self.assertLess(ear.placement(-0.35, ear.design_flare(-1.0)), ear.placement(-0.35))
        self.assertEqual(ear.grid(flare_deg=ear.FLARE_DEG), ear.grid())
        ## The size: smaller on the lean head only; never larger than the approved ear.
        self.assertEqual((ear.design_scale(-1.0), ear.design_scale(0.0), ear.design_scale(1.0)), ear.DESIGN_SCALE)
        self.assertLess(ear.design_scale(-0.5), 1.0)
        self.assertEqual(ear.design_scale(0.5), 1.0)
        self.assertLessEqual(max(ear.design_scale(c / 4.0) for c in range(-6, 7)), 1.0)


if __name__ == "__main__":
    unittest.main()
