"""TEST-TRUTH: construction landmarks and the anatomy -> deform-bone mapping
(LANDMARKS-001, DEFORM-REGIONS-001). ARRANGE a resolved profile and the rig
contract; PERTURB the profile or rig; ACT ``anatomy.derive_anatomy`` /
``anatomy.region_affinity``; ASSERT the landmarks sit where the rig and Model A
put them, are immutable, malformed inputs are refused rather than repaired,
and every deformation region maps onto real deform bones."""

from __future__ import annotations

import copy
import dataclasses
import json
import unittest

from character_modeling import anatomy, baseline, definition

RIG = json.loads(baseline.RIG_CONTRACT.read_text(encoding="utf-8"))
BONES = {bone["name"] for bone in RIG["bones"]}
# Model A's measured girdle top (the accepted study's high heroic mantle).
MODEL_A_GIRDLE_TOP_M = 1.473


def wolf():
    return definition.load_profile(definition.PROFILES / "male_base.json")


class Shoulder(unittest.TestCase):
    def test_the_joint_is_the_rig_and_the_anatomy_sits_around_it(self):
        found = anatomy.derive_anatomy(wolf(), RIG)
        points = anatomy.rig_points(RIG)
        for side, sign in (("L", 1.0), ("R", -1.0)):
            s = found.shoulders[side]
            self.assertEqual(s.gh_center, points["UpperArm." + side][0])
            self.assertEqual(s.clavicle_start, points["Shoulder." + side][0])
            self.assertEqual(s.chest_anchor, points["Chest"][0])
            self.assertEqual(s.neck_base, points["Neck"][0])
            self.assertEqual(s.clavicle_end, s.acromion)
            self.assertGreater(s.acromion[2], s.gh_center[2], "acromion above the joint")
            self.assertGreater(sign * s.acromion[0], sign * s.gh_center[0], "acromion lateral of the joint")
            self.assertLess(s.axilla[2], s.gh_center[2], "armpit below the joint")
            self.assertLess(s.axilla_front[1], s.axilla[1], "pectoral fold in front (-Y)")
            self.assertGreater(s.axilla_back[1], s.axilla[1], "latissimus fold behind")
            self.assertGreater(sign * s.deltoid_outer_extent[0], sign * s.acromion[0], "deltoid outside the acromion")
            self.assertEqual(s.deltoid_underside[0],
                             s.gh_center[0] + (points["UpperArm." + side][1][0] - s.gh_center[0]) * anatomy.DELTOID_HANDOFF)
            self.assertEqual(s.socket_z[0], s.axilla[2])
            self.assertEqual(s.socket_z[2], s.acromion[2])

    def test_the_mantle_matches_model_a_and_clears_the_neck(self):
        found = anatomy.derive_anatomy(wolf(), RIG)
        self.assertAlmostEqual(found.mantle_top_z, MODEL_A_GIRDLE_TOP_M, delta=0.01)
        points = anatomy.rig_points(RIG)
        self.assertLess(points["Neck"][0][2], found.mantle_top_z)
        self.assertLess(found.mantle_top_z, points["Head"][0][2])

    def test_the_trapezius_ridge_runs_from_the_neck_root_down_to_the_acromion(self):
        found = anatomy.derive_anatomy(wolf(), RIG)
        neck_x, top = found.neck_root
        acromion = found.shoulders["L"].acromion
        self.assertEqual(found.shoulders["L"].trap_ridge[1], acromion)
        self.assertAlmostEqual(anatomy.trapezius_ridge_z(found, neck_x), top)
        self.assertAlmostEqual(anatomy.trapezius_ridge_z(found, -acromion[0]), acromion[2])
        self.assertIsNone(anatomy.trapezius_ridge_z(found, neck_x * 0.5), "no ridge over the neck")
        self.assertIsNone(anatomy.trapezius_ridge_z(found, acromion[0] + 0.05), "no ridge over the deltoid")


class Pelvis(unittest.TestCase):
    def test_hip_crest_glute_and_groin(self):
        found = anatomy.derive_anatomy(wolf(), RIG)
        points = anatomy.rig_points(RIG)
        for side in ("L", "R"):
            p = found.pelvis[side]
            self.assertEqual(p.hip, points["UpperLeg." + side][0])
            self.assertGreater(p.iliac_z, p.hip[2])
            self.assertLess(p.groin[2], p.hip[2])
            self.assertGreater(p.glute[1], p.hip[1], "glute behind the joint (+Y is back)")


class Purity(unittest.TestCase):
    def test_derivation_is_deterministic_and_immutable(self):
        found = anatomy.derive_anatomy(wolf(), RIG)
        self.assertEqual(found, anatomy.derive_anatomy(wolf(), RIG))
        with self.assertRaises(dataclasses.FrozenInstanceError):
            found.mantle_top_z = 2.0
        with self.assertRaises(TypeError):
            found.sizes["chest"] = 1.0

    def test_a_broader_profile_moves_the_deltoid_not_the_joint(self):
        broad = copy.deepcopy(wolf())
        broad["style"]["shoulders"] *= 1.1
        base, wide = anatomy.derive_anatomy(wolf(), RIG), anatomy.derive_anatomy(broad, RIG)
        self.assertEqual(base.shoulders["L"].gh_center, wide.shoulders["L"].gh_center)
        self.assertGreater(wide.shoulders["L"].deltoid_outer_extent[0], base.shoulders["L"].deltoid_outer_extent[0])


class Malformed(unittest.TestCase):
    def test_a_shoulder_span_inside_the_joint_is_refused(self):
        narrow = copy.deepcopy(wolf())
        narrow["style"]["shoulders"] = 1.0
        with self.assertRaisesRegex(ValueError, "does not clear"):
            anatomy.derive_anatomy(narrow, RIG)

    def test_a_rig_whose_head_sits_below_the_mantle_is_refused(self):
        rig = copy.deepcopy(RIG)
        for bone in rig["bones"]:
            if bone["name"] == "Head":
                bone["head"] = [0.0, 0.0, 1.45]
        with self.assertRaisesRegex(ValueError, "mantle top"):
            anatomy.derive_anatomy(wolf(), rig)

    def test_a_rig_missing_a_bone_is_refused(self):
        rig = copy.deepcopy(RIG)
        rig["bones"] = [bone for bone in rig["bones"] if bone["name"] != "UpperArm.L"]
        with self.assertRaises(KeyError):
            anatomy.derive_anatomy(wolf(), rig)


class DeformRegions(unittest.TestCase):
    def test_every_region_maps_onto_real_deform_bones_with_unit_rows(self):
        for region, row in anatomy.DEFORM_REGIONS.items():
            for side in ("L", "R"):
                resolved = anatomy.region_affinity(region, side)
                self.assertLessEqual({bone for bone, _share in resolved}, BONES - {"Root", "SwordMount"}, region)
                if resolved:
                    self.assertAlmostEqual(sum(share for _bone, share in resolved), 1.0, places=12, msg=region)
            self.assertEqual(len(row) == 0, region in ("spine", "trapezius"), "only the blend regions are empty")

    def test_the_girdle_rides_the_clavicle_and_the_arm_not_the_chest_alone(self):
        for region in ("acromial", "axilla", "deltoid", "deltoid_outer"):
            bones = {bone for bone, _share in anatomy.region_affinity(region, "L")}
            self.assertIn("Shoulder.L", bones, region)
            self.assertIn("UpperArm.L", bones, region)
        acromial = dict(anatomy.region_affinity("acromial", "L"))
        self.assertGreater(acromial["Shoulder.L"] + acromial["UpperArm.L"], acromial["Chest"])

    def test_each_row_stays_inside_its_creation_region(self):
        self.assertEqual(anatomy.validate_deform_ownership(), [])
        shoulder = set(anatomy.REGION_BY_ID["shoulder"].deform_bones)
        for region in ("acromial", "axilla", "deltoid", "deltoid_outer"):
            bones = {bone for bone, _share in anatomy.region_affinity(region, "L")}
            self.assertLessEqual(bones, shoulder, region)

    def test_sides_resolve_and_unknown_regions_are_refused(self):
        self.assertEqual(dict(anatomy.region_affinity("deltoid", "R"))["UpperArm.R"],
                         dict(anatomy.region_affinity("deltoid", "L"))["UpperArm.L"])
        with self.assertRaisesRegex(ValueError, "unknown deformation region"):
            anatomy.region_affinity("elbow_pit", "L")


if __name__ == "__main__":
    unittest.main()
