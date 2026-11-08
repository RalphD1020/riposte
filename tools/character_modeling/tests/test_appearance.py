"""CHARACTER-LAYERING-001: a character's layers resolve into one appearance plan; coverage is
directional and explicit; facial hair is an identity layer that preserves the mouth."""
import copy
import json
import unittest
from pathlib import Path

from character_modeling import appearance, asset_library, foundation, garments

BLENDER = Path(__file__).resolve().parents[3] / "art-src" / "blender"
CHARACTERS = BLENDER / "characters"
FIXTURES = Path(__file__).resolve().parent / "fixtures"


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def fixture():
    """A bearded character on the foundation (Wolf's manifest wearing the facial-hair
    fixture; Wolf himself is clean-shaven), the definitions, regions and garment target."""
    doc = foundation.load(asset_library.current_foundation_document())
    record = load(Path(foundation.path_of(doc, "record", BLENDER)))
    regions = load(Path(foundation.path_of(doc, "regions", BLENDER)))
    wolf = load(CHARACTERS / "wolf" / "wolf.assembly.json")
    wolf["foundation"]["facial_hair"] = ["fixture_beard"]
    definitions = {g: load(BLENDER / "garments" / ("%s.garment.json" % g)) for g in ("wolf_hair_ranger", "wolf_hair_training")}
    definitions["fixture_beard"] = load(FIXTURES / "fixture_beard.garment.json")
    return wolf, definitions, regions, foundation.garment_target(doc, record, wolf)


def shirt(target, **coverage):
    """A minimal underlayer fitted on the foundation."""
    return {"schema": garments.SCHEMA, "type": "garment", "id": "fixture_shirt", "base_id": target["base"]["id"],
            "base_topology_fingerprint": target["base"]["topology_fingerprint"], "skeleton_id": target["skeleton"]["id"],
            "rig_contract_sha256": target["skeleton"]["contract_sha256"], "category": "fitted", "layer": 1,
            "regions": ["upper_torso", "waist"], "source": {"blend": "x", "object": "Shirt"},
            "deformation": {"method": "skinned", "max_influences": 4, "physique": "keys"},
            "supported_configurations": list(target["physique"]["supported_configurations"]),
            "materials": ["fabric"], "coverage": dict({"hides": ["upper_torso"], "margin_rings": 2}, **coverage)}


class Plan(unittest.TestCase):
    def test_wolf_resolves_one_ordered_plan_per_outfit(self):
        ## ARRANGE: the bearded character's identity and outfits on the foundation.
        wolf, definitions, regions, target = fixture()
        ## ACT
        ranger = appearance.resolve(wolf, "ranger", definitions, regions, target)
        training = appearance.resolve(wolf, "training", definitions, regions, target)
        ## ASSERT: identity beneath the outfit's hair; the beard's coverage on the head; the
        ## mouth preserved; each outfit its own plan; the plan is deterministic.
        self.assertEqual([(c["id"], c["layer"]) for c in ranger["components"]],
                         [("fixture_beard", appearance.FACIAL_HAIR), ("wolf_hair_ranger", appearance.HAIR)])
        self.assertEqual(ranger["visibility"]["hidden_regions"], {"HeadV2": ["chin"]})
        self.assertEqual(ranger["visibility"]["preserved_regions"], ["mouth"])
        self.assertNotEqual(ranger["fingerprint"], training["fingerprint"])
        self.assertEqual(appearance.resolve(wolf, "ranger", definitions, regions, target), ranger)
        self.assertEqual(appearance.hidden_vertices(ranger, regions, "HeadV2"), set(regions["regions"]["chin"]["vertices"]))
        self.assertEqual(appearance.hidden_vertices(ranger, regions), set())

    def test_wolf_is_clean_shaven_in_every_outfit(self):
        ## ARRANGE: Wolf's own manifest, unchanged.
        _bearded, definitions, regions, target = fixture()
        wolf = load(CHARACTERS / "wolf" / "wolf.assembly.json")
        self.assertNotIn("facial_hair", wolf["foundation"])
        for outfit in ("ranger", "training"):
            ## ACT
            plan = appearance.resolve(wolf, outfit, definitions, regions, target)
            ## ASSERT: no facial-hair layer and no head region hidden for one.
            self.assertEqual([c["id"] for c in plan["components"]], ["wolf_hair_%s" % outfit])
            self.assertEqual(plan["visibility"]["hidden_regions"], {})
            self.assertEqual(plan["visibility"]["preserved_regions"], [])

    def test_body_coverage_lands_on_the_body_with_its_margin(self):
        ## ARRANGE: an underlayer added to the Ranger outfit.
        wolf, definitions, regions, target = fixture()
        definitions["fixture_shirt"] = shirt(target)
        wolf["outfits"]["ranger"]["garments"].append("fixture_shirt")
        wolf["art"]["outfits"]["ranger"]["construction"].append("fitted")
        ## ACT
        plan = appearance.resolve(wolf, "ranger", definitions, regions, target)
        ## ASSERT: the garment sits above the hair layer; its hidden body region and margin.
        self.assertEqual(plan["components"][-1]["layer"], "%s.1" % appearance.GARMENT)
        self.assertEqual(plan["visibility"]["hidden_regions"]["body"], ["upper_torso"])
        self.assertEqual(plan["visibility"]["margin_rings"]["body"], 2)

    def test_coverage_fails_closed_when_it_is_not_explicit_or_not_beneath(self):
        wolf, definitions, regions, target = fixture()
        ## PERTURB: a layer hiding the preserved mouth.
        definitions["fixture_shirt"] = shirt(target)
        bad = copy.deepcopy(definitions)
        bad["wolf_hair_ranger"]["coverage"] = {"hides": ["mouth"]}
        wolf["outfits"]["ranger"]["garments"] = ["wolf_hair_ranger"]
        with self.assertRaisesRegex(ValueError, "hides mouth, which fixture_beard preserves"):
            appearance.resolve(wolf, "ranger", bad, regions, target)
        ## PERTURB: a beneath layer claiming to hide the hair above it.
        upward = copy.deepcopy(definitions)
        upward["fixture_beard"]["coverage"]["hides_components"] = ["wolf_hair_ranger"]
        with self.assertRaisesRegex(ValueError, "not beneath it"):
            appearance.resolve(wolf, "ranger", upward, regions, target)
        ## PERTURB: a helmet-like garment hiding the hairstyle beneath it: hidden whole.
        helmet = copy.deepcopy(definitions)
        helmet["fixture_shirt"]["coverage"]["hides_components"] = ["wolf_hair_ranger"]
        wolf["outfits"]["ranger"]["garments"] = ["wolf_hair_ranger", "fixture_shirt"]
        wolf["art"]["outfits"]["ranger"]["construction"].append("fitted")
        plan = appearance.resolve(wolf, "ranger", helmet, regions, target)
        self.assertEqual(plan["visibility"]["hidden_components"], {"wolf_hair_ranger": ["fixture_shirt"]})
        self.assertNotIn("wolf_hair_ranger", [c["id"] for c in plan["components"]])
        ## PERTURB: an unknown outfit or a missing definition.
        with self.assertRaises(ValueError):
            appearance.resolve(wolf, "parade", definitions, regions, target)
        del definitions["fixture_beard"]
        with self.assertRaisesRegex(ValueError, "no definitions"):
            appearance.resolve(wolf, "ranger", definitions, regions, target)


class FacialHair(unittest.TestCase):
    def test_the_beard_is_valid_identity_facial_hair_on_the_foundation(self):
        ## ARRANGE / ACT: the beard fixture against the foundation's target and regions.
        wolf, definitions, regions, target = fixture()
        beard = definitions["fixture_beard"]
        ## ASSERT
        self.assertEqual(garments.problems(beard, target, regions), [])
        for region in beard["design"]["growth"]:
            self.assertEqual(regions["regions"][region]["parent"], "head")

    def test_facial_hair_must_preserve_the_mouth_and_grow_on_the_head(self):
        wolf, definitions, regions, target = fixture()
        ## PERTURB: no preserved mouth; a growth region off the head; a costume material;
        ## a region both hidden and preserved.
        cases = {
            "preserves ['mouth']": lambda d: d["coverage"].update(preserves=[]),
            "not head sub-regions": lambda d: d["design"]["growth"].update(upper_torso={}),
            "only the intrinsic hair slot": lambda d: d.update(materials=["fabric"]),
            "both hides and preserves": lambda d: d["coverage"].update(hides=["chin", "mouth"]),
        }
        for reason, mutate in cases.items():
            beard = copy.deepcopy(definitions["fixture_beard"])
            mutate(beard)
            ## ACT / ASSERT
            self.assertTrue(any(reason in p for p in garments.problems(beard, target, regions)), reason)

    def test_a_definition_names_every_base_it_was_fitted_to(self):
        ## ARRANGE: the hairstyles are fitted to v1 and, per resolved head, to the foundation.
        wolf, definitions, regions, target = fixture()
        hair = definitions["wolf_hair_training"]
        ## ACT / ASSERT: compatible with the foundation through `also_fitted`...
        self.assertEqual(garments.problems(hair, target, regions), [])
        ## PERTURB: ...and refused once the foundation is not listed.
        stale = dict(hair, also_fitted=[])
        self.assertTrue(any("is fitted to character.male_base, not" in p for p in garments.problems(stale, target, regions)))


class HeadRegions(unittest.TestCase):
    def test_the_head_sub_regions_are_on_the_head_object_and_keyed_to_it(self):
        ## ARRANGE: the foundation's regions.
        doc = foundation.load(asset_library.current_foundation_document())
        regions = load(Path(foundation.path_of(doc, "regions", BLENDER)))
        record = load(Path(foundation.path_of(doc, "record", BLENDER)))
        heads = record["objects"]["HeadV2"]["vertices"]
        ## ASSERT: every sub-region names the head object, its parent, and indices in range;
        ## the mouth and the beard's regions do not overlap.
        subs = {n: r for n, r in regions["regions"].items() if r.get("parent") == "head"}
        self.assertEqual(set(subs), {"mouth", "upper_lip", "chin", "jaw", "cheek_low", "sideburn", "scalp"})
        self.assertEqual(regions["head_topology_fingerprint"], record["objects"]["HeadV2"]["sha256"])
        for name, region in subs.items():
            self.assertEqual(region["object"], "HeadV2", name)
            self.assertTrue(region["vertices"] and max(region["vertices"]) < heads, name)
        self.assertFalse(set(subs["mouth"]["vertices"]) & set(subs["chin"]["vertices"]))


if __name__ == "__main__":
    unittest.main()
