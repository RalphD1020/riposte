"""The body's two region views share one vocabulary (CHARACTER-REGIONS-001)."""
import json
import os
import unittest

from character_modeling import anatomy, body_regions, rig_regions

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
CHARACTERS = os.path.join(ROOT, "art-src", "blender", "characters")
FITTING_RECORDS = ("male_base.regions.json", "male_base.foundation.v002.regions.json")


class Vocabulary(unittest.TestCase):
    def test_the_vocabulary_is_self_consistent(self):
        ## ARRANGE: the shipped tables. ACT: the vocabulary's own check. ASSERT: nothing to report.
        self.assertEqual(body_regions.problems(), [])
        ## The two views stay apart: a shape group names regions and structures, never a bone.
        bones = set(rig_regions.REGION)
        for group, spec in body_regions.SHAPE_GROUPS.items():
            for field in spec[:3]:
                self.assertFalse(bones & {item.split(".")[0] for item in field}, group)

    def test_a_broken_neighbour_or_alias_is_reported(self):
        ## PERTURB: a one-sided neighbour and an alias to nowhere.
        groups, aliases = dict(body_regions.SHAPE_GROUPS), dict(body_regions.ALIASES)
        try:
            spec = list(body_regions.SHAPE_GROUPS["tibialis_anterior"])
            spec[2] = spec[2] + ("pectorals",)
            body_regions.SHAPE_GROUPS["tibialis_anterior"] = tuple(spec)
            body_regions.ALIASES["shin"] = "lower_shin"
            ## ACT
            found = body_regions.problems()
        finally:
            body_regions.SHAPE_GROUPS.clear()
            body_regions.SHAPE_GROUPS.update(groups)
            body_regions.ALIASES.clear()
            body_regions.ALIASES.update(aliases)
        ## ASSERT
        self.assertIn("shape groups tibialis_anterior and pectorals are not mutual neighbours", found)
        self.assertIn("alias shin points at unknown region lower_shin", found)

    def test_every_older_name_resolves_to_one_canonical_region(self):
        ## ARRANGE: the v1 creation regions and the rig's regions.
        ## ACT / ASSERT: each lands on a canonical deformation region.
        for region in anatomy.REGIONS:
            self.assertIn(anatomy.deformation_region(region), body_regions.DEFORMATION_REGIONS, region)
        self.assertEqual(anatomy.deformation_region("thigh"), "upper_leg")
        self.assertEqual(anatomy.deformation_region("calf"), "lower_leg")
        self.assertEqual(anatomy.deformation_region("back_upper"), "upper_torso")
        for region in rig_regions.REGION.values():
            if region not in rig_regions.NON_BODY:
                self.assertEqual(body_regions.canonical(region), region)
        self.assertEqual(anatomy.SHAPE_GROUPS, body_regions.SHAPE_GROUP_IDS)

    def test_an_unknown_or_unsided_name_fails_closed(self):
        ## PERTURB: a typo, and a side on a centre region.
        for name in ("upperarm", "Thigh", "waist.L", "head.R"):
            ## ACT / ASSERT
            with self.assertRaises(KeyError):
                body_regions.canonical(name)
        self.assertEqual(body_regions.canonical("thigh.L"), "upper_leg.L")
        self.assertEqual(body_regions.fit_mask("calf.R"), "fit.lower_leg.R")
        self.assertEqual(body_regions.shape_mask("pectorals"), "shape.pectorals")
        with self.assertRaises(KeyError):
            body_regions.shape_mask("upper_arm")


class FittingParity(unittest.TestCase):
    def test_the_fitting_table_reproduces_every_stored_fitting_record(self):
        ## ARRANGE: the fitting records the old inline table wrote (v1 and the v002 foundation).
        table = body_regions.fitting_table()
        for name in FITTING_RECORDS:
            with open(os.path.join(CHARACTERS, name), encoding="utf-8") as handle:
                stored = json.load(handle)["regions"]
            body = [r for r, spec in stored.items() if "parent" not in spec]
            ## ACT / ASSERT: same regions, same order, same metadata.
            self.assertEqual(body, list(table), name)
            for region in body:
                _dominant, bones, physique, neighbours, clips = table[region]
                spec = stored[region]
                self.assertEqual((spec["bones"], spec["physique"], spec["neighbours"], spec["clips"]),
                                 (list(bones), list(physique), list(neighbours), list(clips)), "%s %s" % (name, region))

    def test_joint_bands_join_neighbouring_segments(self):
        ## ARRANGE: the segment adjacency the fitting records declare.
        table = body_regions.fitting_table()
        for band, (joins, bones, states) in body_regions.JOINT_BANDS.items():
            a, b = ("%s.L" % s if "%s.L" % s in table else s for s in joins)
            ## ACT / ASSERT: a band sits between two regions that are neighbours, on real bones.
            self.assertTrue(b in table[a][3] or a in table[b][3], band)
            for bone in bones:
                rig_regions.region_of(bone.format(s="L") if "{s}" in bone else bone)
            self.assertTrue(states, band)


if __name__ == "__main__":
    unittest.main()
