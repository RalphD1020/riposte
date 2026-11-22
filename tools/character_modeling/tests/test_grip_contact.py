"""A gripping hand meets its handle on opposing sides, without penetrating or floating
(PRES-GRIP-001)."""
import math
import unittest

from character_modeling import grip_contact as gc

ORIGIN = (0.0, 0.0, 0.0)
AXIS = (1.0, 0.0, 0.0)
REF = (0.0, 0.0, -1.0)
RADIUS = 15.0
HALF = 35.0


def ring_point(t, deg, rho):
    """A point at axial t, `deg` round the axis from REF, `rho` off it."""
    a = math.radians(deg)
    side = (0.0, 1.0, 0.0)  ## AXIS x REF
    return (t, rho * math.sin(a) * side[1], -rho * math.cos(a))


def grip(palm=(0.0, 16.0), fingers=(180.0, 16.0), thumb=(90.0, 16.0)):
    samples = []
    for name, (deg, rho) in (("palm", palm), ("fingers", fingers), ("thumb", thumb)):
        for t in (-20.0, 0.0, 20.0):
            samples.append((name, ring_point(t, deg, rho)))
    return samples


class Geometry(unittest.TestCase):
    def test_clearance_is_the_radial_distance_off_the_surface(self):
        ## ARRANGE: a point 20 along the axis and 18 off it. ACT / ASSERT: t 20, clearance 3.
        t, d = gc.clearance((20.0, 0.0, -18.0), ORIGIN, AXIS, RADIUS)
        self.assertAlmostEqual(t, 20.0)
        self.assertAlmostEqual(d, 3.0)

    def test_angles_are_measured_round_the_axis_from_the_reference(self):
        ## ARRANGE / ACT / ASSERT: REF itself is 0; the other side is 180; separation wraps.
        self.assertAlmostEqual(gc.angle(ring_point(0, 0, 16), ORIGIN, AXIS, REF), 0.0)
        self.assertAlmostEqual(abs(gc.angle(ring_point(0, 180, 16), ORIGIN, AXIS, REF)), 180.0)
        self.assertAlmostEqual(gc.separation(170.0, -170.0), 20.0)


class Grip(unittest.TestCase):
    def test_an_opposed_touching_grip_holds(self):
        ## ARRANGE: palm, fingers and thumb 1 mm off the handle on three sides.
        ## ACT
        report = gc.measure(grip(), ORIGIN, AXIS, RADIUS, HALF, REF)
        ## ASSERT
        self.assertEqual(gc.problems(report), [])
        self.assertEqual(report["fingers"]["contact"], 3)
        self.assertAlmostEqual(report["palm"]["deepest"], 1.0)

    def test_penetration_floating_and_missing_patches_are_reported(self):
        ## PERTURB: fingers sunk 4 mm into the handle, the thumb 10 mm off it, and the palm
        ## sampled only beyond the handle's span.
        samples = [s for s in grip(fingers=(180.0, 11.0), thumb=(90.0, 25.0)) if s[0] != "palm"]
        samples.append(("palm", (60.0, 0.0, -16.0)))
        ## ACT
        found = gc.problems(gc.measure(samples, ORIGIN, AXIS, RADIUS, HALF, REF))
        ## ASSERT
        self.assertIn("palm has no surface within the handle's span", found)
        self.assertIn("fingers penetrates the handle by 4.0", found)
        self.assertIn("thumb floats 10.0 off the handle", found)

    def test_opposition_is_described_never_failed(self):
        ## ARRANGE: an opposed grip. PERTURB: fingers and thumb beside the palm instead.
        opposed = gc.measure(grip(), ORIGIN, AXIS, RADIUS, HALF, REF)
        beside = gc.measure(grip(fingers=(40.0, 16.0), thumb=(20.0, 16.0)), ORIGIN, AXIS, RADIUS, HALF, REF)
        ## ACT
        notes, found = gc.diagnostics(beside), gc.problems(beside)
        ## ASSERT: described for the reviewer, not a failure; the opposed grip reads plainly.
        self.assertEqual(found, [])
        self.assertIn("fingers close 40 deg round from the palm (beside it, not across)", notes)
        self.assertIn("thumb closes 20 deg round from the palm (near the palm's side)", notes)
        self.assertIn("fingers close 180 deg round from the palm", gc.diagnostics(opposed))


class OvalSection(unittest.TestCase):
    def test_the_real_oval_grip_moves_clearance_by_direction(self):
        ## ARRANGE: the authored grip, 13 mm along REF (the edge axis) and 15 mm across it.
        section = (13.0, 15.0, REF)
        on_a, on_b = ring_point(0, 0, 16), ring_point(0, 90, 16)
        ## ACT
        _t, d_a = gc.clearance(on_a, ORIGIN, AXIS, RADIUS, section)
        _t, d_b = gc.clearance(on_b, ORIGIN, AXIS, RADIUS, section)
        _t, d_mid = gc.clearance(ring_point(0, 45, 16), ORIGIN, AXIS, RADIUS, section)
        ## ASSERT: 3 mm clear on the narrow axis, 1 mm on the wide one, between them in between;
        ## a point on the axis reads the narrow semi-axis.
        self.assertAlmostEqual(d_a, 3.0)
        self.assertAlmostEqual(d_b, 1.0)
        self.assertTrue(1.0 < d_mid < 3.0)
        self.assertAlmostEqual(gc.section_radius((0.0, 0.0, 0.0), RADIUS, section), 13.0)
        ## PERTURB: a palm sunk 2 mm inside the oval's wide side reports that penetration.
        sunk = [(n, ring_point(0, 90, 13.0)) for n in ("palm",)]
        self.assertLess(gc.measure(sunk, ORIGIN, AXIS, RADIUS, HALF, REF, section=section)["palm"]["deepest"], -1.9)


if __name__ == "__main__":
    unittest.main()
