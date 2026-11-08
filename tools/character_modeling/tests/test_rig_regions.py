"""The deform groups' anatomical regions: an explicit table, exact names, fail closed."""
import unittest

from character_modeling import rig_regions as regions


class Regions(unittest.TestCase):
    def test_every_limb_segment_is_classified_on_both_sides(self):
        ## ARRANGE: the rig's limb groups and their regions.
        expected = {"UpperArm": "upper_arm", "Forearm": "forearm", "Hand": "hand",
                    "UpperLeg": "thigh", "LowerLeg": "calf", "Foot": "foot"}
        for bone, region in expected.items():
            for side in regions.SIDES:
                ## ACT / ASSERT: each side, and the arm and leg sets.
                self.assertEqual(regions.region_of(bone + side), region)
                self.assertEqual(regions.in_regions(bone + side, regions.ARM), region in regions.ARM)
                self.assertEqual(regions.in_regions(bone + side, regions.LEG), region in regions.LEG)
        ## The forearm is an arm (the case-sensitive "Arm" match missed it); the torso is not.
        self.assertTrue(regions.in_regions("Forearm.L", regions.ARM))
        self.assertFalse(regions.in_regions("Chest", regions.ARM))
        self.assertFalse(regions.in_regions("Shoulder.R", regions.ARM))

    def test_an_unknown_or_miscased_group_fails_closed(self):
        ## PERTURB: a renamed or miscased bone is an error, never a silent "not an arm".
        for name in ("forearm.L", "UpperArmTwist.L", "Spine2"):
            with self.assertRaises(KeyError):
                regions.region_of(name)


if __name__ == "__main__":
    unittest.main()
