"""TEST-TRUTH: a character's identity profile (the manifest's `art` block) against its
outfits and the assets they wear. Each test states its fixture (ARRANGE), the drift
it adds (PERTURB), the production call (ACT), and the contract (ASSERT). Real files:
the shipped Wolf manifest and Wolf's hair definitions."""

from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path

from character_modeling import identity

ROOT = Path(__file__).resolve().parents[3]
BLENDER = ROOT / "art-src" / "blender"


def manifest():
    return json.loads((BLENDER / "characters" / "wolf" / "wolf.assembly.json").read_text(encoding="utf-8"))


def definition(gid):
    return json.loads((BLENDER / "garments" / ("%s.garment.json" % gid)).read_text(encoding="utf-8"))


def gambeson(category="padded"):
    return {"id": "fixture_gambeson", "type": "garment", "category": category}


class IdentityProfile(unittest.TestCase):
    def test_the_shipped_profile_and_both_hair_outfits_are_consistent(self):
        ## ARRANGE: the shipped manifest and the hairstyles its outfits wear.
        m = manifest()
        ## ACT
        found = {
            None: identity.problems(m),
            "ranger": identity.problems(m, "ranger", [definition("wolf_hair_ranger")]),
            "training": identity.problems(m, "training", [definition("wolf_hair_training")]),
        }
        ## ASSERT
        self.assertEqual(found, {None: [], "ranger": [], "training": []})

    def test_a_costume_never_recolors_identity_materials(self):
        ## ARRANGE
        m = manifest()
        ## PERTURB: Training's palette names Wolf's skin.
        m["outfits"]["training"]["palette"] = {"skin": {"srgb": [0.5, 0.4, 0.3]}}
        ## ACT
        found = identity.problems(m)
        ## ASSERT
        self.assertIn("outfit training recolors identity materials ['skin']", found)

    def test_skin_is_a_shared_swatch_the_crowd_draws_from(self):
        ## ARRANGE: the shipped manifest and the shared swatches it names.
        m = manifest()
        swatches = identity.load_swatches(m, ROOT)
        crowd = json.loads((ROOT / m["skin_swatches"]).read_text(encoding="utf-8"))["skin_swatches"]
        ## ACT
        skin = identity.palette_srgb(m, identity.SKIN, swatches)
        hair = identity.palette_srgb(m, "hair", swatches)
        ## ASSERT
        self.assertEqual(identity.problems(m, swatches=swatches), [])
        self.assertEqual(skin, crowd[m["identity"]["palette"]["skin"]["swatch"]])
        self.assertEqual(hair, m["identity"]["palette"]["hair"]["srgb"])
        ## PERTURB: a swatch the shared file does not have; then a free colour.
        m["identity"]["palette"]["skin"]["swatch"] = "skin_99"
        unknown = identity.problems(m, swatches=swatches)
        m["identity"]["palette"]["skin"] = {"srgb": [0.94, 0.86, 0.8], "roughness": 0.75}
        colour = identity.problems(m, swatches=swatches)
        ## ASSERT
        self.assertEqual(unknown, ["the identity skin swatch skin_99 is not one of the shared swatches"])
        self.assertEqual(colour, ["the identity skin must name a shared skin swatch, not a colour"])

    def test_the_profile_names_every_anchor_and_every_complete_outfit(self):
        ## ARRANGE
        m = manifest()
        ## PERTURB: the face anchor dropped; a complete outfit without a profile.
        del m["art"]["anchors"]["face"]
        m["outfits"]["field"] = {"collections": [], "garments": [], "complete": True}
        ## ACT
        found = identity.problems(m)
        ## ASSERT
        self.assertIn("art profile lacks the face anchor", found)
        self.assertIn("complete outfit field has no art profile", found)
        ## PERTURB: no art block at all.
        del m["art"]
        self.assertEqual(identity.problems(m), ["character.wolf has no art profile"])

    def test_each_malformed_outfit_profile_field_is_named(self):
        ## ARRANGE
        cases = [
            ("shoulder_reinforcement", "pauldrons", "shoulder_reinforcement must be one of"),
            ("construction", ["fitted", "plate"], "unknown constructions ['plate']"),
            ("hair_regions", ["front_sweep"], "a hairstyle is built on a scalp region"),
        ]
        for key, value, expected in cases:
            ## PERTURB
            m = manifest()
            m["art"]["outfits"]["ranger"][key] = value
            ## ACT
            found = identity.problems(m)
            ## ASSERT
            self.assertTrue(any(expected in p for p in found), (key, found))
        m = manifest()
        del m["art"]["outfits"]["ranger"]["identity"]
        self.assertIn("outfit ranger: art profile lacks identity", identity.problems(m))

    def test_an_outfit_wears_its_profiled_hairstyle_with_its_design_regions(self):
        ## ARRANGE
        m = manifest()
        ranger, training = definition("wolf_hair_ranger"), definition("wolf_hair_training")
        ## PERTURB: Ranger wears Training's hairstyle; then Ranger's hair loses its temples.
        swapped = identity.problems(m, "ranger", [training])
        lacking = copy.deepcopy(ranger)
        del lacking["design"]["regions"]["temples"]
        missing = identity.problems(m, "ranger", [lacking])
        ## PERTURB: a design region outside the profile (accents stay allowed).
        extra = copy.deepcopy(ranger)
        extra["design"]["regions"]["fringe"] = ["Fringe"]
        outside = identity.problems(m, "ranger", [extra])
        ## ASSERT
        self.assertIn("outfit ranger does not wear its profiled hairstyle wolf_hair_ranger", swapped)
        self.assertIn("outfit ranger: hairstyle wolf_hair_ranger lacks the design regions ['temples']", missing)
        self.assertEqual(outside, ["outfit ranger: hairstyle wolf_hair_ranger has design regions ['fringe'] outside the profile"])

    def test_a_garment_outside_the_outfits_constructions_is_identity_drift(self):
        ## ARRANGE: Training has no fur and no rigid armour.
        m = manifest()
        hair = definition("wolf_hair_training")
        ## ACT
        padded = identity.problems(m, "training", [hair, gambeson("padded")])
        ## PERTURB: a fur garment worn in Training.
        fur = identity.problems(m, "training", [hair, gambeson("fur")])
        ## ASSERT
        self.assertEqual(padded, [])
        self.assertTrue(any("fixture_gambeson is fur, not one of the outfit's constructions" in p for p in fur), fur)


if __name__ == "__main__":
    unittest.main()
