"""TEST-TRUTH: garment definitions against a character manifest and the base's fitting
regions, outfit pairing, and the export-copy body mask. Each test states its fixture
(ARRANGE), the defect it adds (PERTURB), the production call (ACT), and the contract
(ASSERT). Real files: the shipped Wolf manifest and the base's fitting regions."""

from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path

from character_modeling import garments

ROOT = Path(__file__).resolve().parents[3]
CHARACTERS = ROOT / "art-src" / "blender" / "characters"


def manifest():
    return json.loads((CHARACTERS / "wolf" / "wolf.assembly.json").read_text(encoding="utf-8"))


def regions():
    return json.loads((CHARACTERS / "male_base.regions.json").read_text(encoding="utf-8"))


def gambeson(m):
    return {
        "schema": garments.SCHEMA,
        "id": "fixture_gambeson",
        "base_id": m["base"]["id"],
        "base_topology_fingerprint": m["base"]["topology_fingerprint"],
        "skeleton_id": m["skeleton"]["id"],
        "rig_contract_sha256": m["skeleton"]["contract_sha256"],
        "category": "fitted",
        "regions": ["upper_torso", "waist", "shoulder.L", "shoulder.R"],
        "layer": 1,
        "source": {"blend": "characters/wolf/wolf_attire.blend", "object": "FixtureGambeson"},
        "deformation": {"method": "skinned", "max_influences": 4},
        "supported_configurations": list(m["physique"]["supported_configurations"]),
        "coverage": {"hides": ["upper_torso", "waist"], "margin_rings": 1},
        "materials": ["fabric"],
    }


def mantle(m):
    garment = gambeson(m)
    garment.update({
        "id": "fixture_mantle", "category": "structured", "layer": 3,
        "regions": ["shoulder.L", "shoulder.R", "upper_torso"],
        "coverage": {"hides": []}, "materials": ["mantle"], "requires": ["fixture_gambeson"],
    })
    return garment


class GarmentContract(unittest.TestCase):
    def test_a_garment_fitted_to_this_base_and_rig_is_compatible(self):
        ## ARRANGE: the shipped manifest and regions, a definition fitted to them.
        m, r = manifest(), regions()
        ## ACT / ASSERT
        self.assertEqual(garments.problems(gambeson(m), m, r), [])

    def test_a_garment_fitted_to_another_base_or_rig_is_refused(self):
        ## ARRANGE
        m, r = manifest(), regions()
        cases = {
            "another base topology": ("base_topology_fingerprint", "0" * 64),
            "another rig contract": ("rig_contract_sha256", "f" * 64),
            "is fitted to": ("base_id", "character.female_base"),
        }
        for expected, (key, value) in cases.items():
            ## PERTURB: one identity field changed.
            garment = gambeson(m)
            garment[key] = value
            ## ACT
            found = garments.problems(garment, m, r)
            ## ASSERT: refused, naming the reason.
            self.assertTrue(any(expected in p for p in found), (key, found))

    def test_each_malformed_field_is_named(self):
        ## ARRANGE
        m, r = manifest(), regions()
        cases = [
            ("category", "draped", "unknown category"),
            ("layer", 0, "not a garment layer"),
            ("regions", ["tail"], "unknown fitting regions"),
            ("regions", [], "no fitting region"),
            ("deformation", {"method": "skinned", "max_influences": 8}, "more than 4 influences"),
            ("deformation", {"method": "cloth"}, "deformation must be"),
            ("deformation", {"method": "rigid"}, "names its one bone"),
            ("supported_configurations", ["default"], "does not support the character's configurations"),
            ("materials", ["velvet"], "material slots outside"),
        ]
        for key, value, expected in cases:
            ## PERTURB
            garment = gambeson(m)
            garment[key] = value
            if key == "regions" and value == ["tail"]:
                garment["coverage"] = {"hides": []}
            ## ACT
            found = garments.problems(garment, m, r)
            ## ASSERT
            self.assertTrue(any(expected in p for p in found), (key, value, found))

    def test_a_garment_reaching_the_neck_declares_its_upper_boundary(self):
        ## ARRANGE: the fixture gambeson grows a collar onto the neck.
        m, r = manifest(), regions()
        garment = gambeson(m)
        garment["regions"] = garment["regions"] + ["neck"]
        ## ACT: no boundary declared.
        undeclared = garments.problems(garment, m, r)
        ## PERTURB: declared, then with a negative opening and an unknown contact rule.
        garment["upper_boundary"] = {"collar_height_m": 0.04, "collar_opening_m": 0.16, "hood_clearance_m": 0.0, "contact": "clearance"}
        declared = garments.problems(garment, m, r)
        garment["upper_boundary"] = {"collar_height_m": 0.04, "collar_opening_m": -0.1, "contact": "glued"}
        malformed = garments.problems(garment, m, r)
        ## ASSERT
        self.assertTrue(any("declares its upper boundary" in p for p in undeclared))
        self.assertFalse(any("upper_boundary" in p or "upper boundary" in p for p in declared))
        self.assertTrue(any("collar_opening_m is a length" in p for p in malformed))
        self.assertTrue(any("contact must be one of" in p for p in malformed))

    def test_a_garment_may_hide_only_regions_it_covers(self):
        ## ARRANGE
        m, r = manifest(), regions()
        garment = gambeson(m)
        ## PERTURB: hides the pelvis it does not occupy.
        garment["coverage"]["hides"] = ["pelvis"]
        ## ACT / ASSERT
        self.assertTrue(any("hides regions it does not cover" in p for p in garments.problems(garment, m, r)))

    def test_only_a_garment_on_unshaped_regions_may_ignore_physique(self):
        ## ARRANGE: a rigid hair piece on the head, which no physique parameter shapes.
        m, r = manifest(), regions()
        hair = gambeson(m)
        hair.update({"id": "fixture_hair", "category": "structured", "regions": ["head"], "layer": 2,
                     "deformation": {"method": "rigid", "bone": "Head", "physique": "none"},
                     "coverage": {"hides": []}, "materials": ["hair"]})
        ## ACT
        on_head = garments.problems(hair, m, r)
        ## PERTURB: the same piece reaching the neck, which mass and shoulders shape.
        hair["regions"] = ["head", "neck"]
        on_neck = garments.problems(hair, m, r)
        ## ASSERT
        self.assertEqual(on_head, [])
        self.assertTrue(any("does not follow physique but covers regions shaped by" in p for p in on_neck), on_neck)

    def test_a_missing_field_is_reported_before_anything_else(self):
        ## ARRANGE / PERTURB
        m, r = manifest(), regions()
        garment = gambeson(m)
        del garment["coverage"]
        ## ACT / ASSERT
        self.assertEqual(garments.problems(garment, m, r), ["garment fixture_gambeson lacks coverage"])

    def test_clearance_overrides_and_overlaps_are_declared_not_silent(self):
        ## ARRANGE: a mantle that sits farther off the shoulders and overlaps the collar.
        m, r = manifest(), regions()
        garment = mantle(m)
        garment["clearance_m"] = {"default": [0.006, 0.04], "shoulder.L": [0.01, 0.06]}
        garment["overlaps"] = [{"with": "fixture_collar", "max_m": 0.01, "reason": "the mantle's edge tucks under the fur"}]
        ## ACT
        clean = garments.problems(garment, m, r, [gambeson(m)])
        band = garments.clearance_for(garment, r, "shoulder.L")
        fallback = garments.clearance_for(gambeson(m), r, "upper_torso")
        ## PERTURB: an inverted band, an unknown region, an overlap without a reason.
        garment["clearance_m"] = {"tail": [0.0, 0.1], "default": [0.05, 0.01]}
        garment["overlaps"] = [{"with": "fixture_collar", "max_m": 0.01}]
        broken = garments.problems(garment, m, r, [gambeson(m)])
        ## ASSERT
        self.assertEqual(clean, [])
        self.assertEqual(band, [0.01, 0.06])
        self.assertEqual(fallback, r["clearance_m"]["fitted"])
        for expected in ("unknown region tail", "with 0 <= low < high", "a positive max_m and a reason"):
            self.assertTrue(any(expected in p for p in broken), (expected, broken))


class HairContract(unittest.TestCase):
    def hair(self, m):
        return {
            "schema": garments.SCHEMA, "type": "hair", "id": "fixture_hair",
            "base_id": m["base"]["id"], "base_topology_fingerprint": m["base"]["topology_fingerprint"],
            "skeleton_id": m["skeleton"]["id"], "rig_contract_sha256": m["skeleton"]["contract_sha256"],
            "category": "structured", "regions": ["head"],
            "source": {"blend": "characters/wolf/wolf_attire.blend", "object": "FixtureHair"},
            "deformation": {"method": "rigid", "bone": "Head", "physique": "none"},
            "supported_configurations": list(m["physique"]["supported_configurations"]),
            "materials": ["hair"], "clearance": {"face": True},
            "design": {"style": "tied_back", "method": "sculpted_mesh", "primary": "front_sweep", "variant": "A",
                       "regions": {"scalp": ["Cap"], "front_sweep": ["Sweep.*"], "rear_tie": ["Nape.*", "Bun.*"]}},
            "surfaces": {"relationships": [{"region": "scalp", "relationship": "attach", "design_regions": ["scalp"]}]},
        }

    def test_hair_on_the_head_in_the_hair_slot_keeping_the_face_clear_is_valid(self):
        ## ARRANGE
        m, r = manifest(), regions()
        ## ACT / ASSERT: no layer or coverage required for hair.
        self.assertEqual(garments.problems(self.hair(m), m, r), [])

    def test_hair_off_the_head_in_a_costume_slot_or_over_the_face_is_refused(self):
        ## ARRANGE
        m, r = manifest(), regions()
        cases = [("regions", ["neck"], "hair sits on the head region"),
                 ("materials", ["fabric"], "wears only the intrinsic hair slot"),
                 ("clearance", {"face": False}, "must keep the face clear"),
                 ("surfaces", {}, "declares how it meets the body"),
                 ("type", "wig", "type must be one of")]
        for key, value, expected in cases:
            ## PERTURB
            hair = self.hair(m)
            hair[key] = value
            if key == "regions":
                hair["deformation"]["physique"] = "keys"
            ## ACT
            found = garments.problems(hair, m, r)
            ## ASSERT
            self.assertTrue(any(expected in p for p in found), (key, found))

    def test_a_hairstyle_declares_its_design_regions_on_a_scalp(self):
        ## ARRANGE
        m, r = manifest(), regions()
        cases = [
            ({"style": ""}, "names its style"),
            ({"method": "hair_cards"}, "opaque sculpted hair; no strands or cards"),
            ({"regions": {"front_sweep": ["SweptFront"]}, "primary": "front_sweep"}, "built on a scalp region"),
            ({"primary": "bun"}, "design.primary must be one of its regions"),
            ({"regions": {"scalp": ["Cap"], "front_sweep": []}, "primary": "scalp"}, "every design region names its masses"),
            ({"regions": {"scalp": ["Cap"], "front_sweep": ["Cap"]}, "primary": "scalp"}, "belong to more than one design region"),
        ]
        for change, expected in cases:
            ## PERTURB: one design field broken.
            hair = self.hair(m)
            hair["design"].update(change)
            ## ACT
            found = garments.problems(hair, m, r)
            ## ASSERT
            self.assertTrue(any(expected in p for p in found), (change, found))
        ## PERTURB: no design at all — reported as a missing field.
        hair = self.hair(m)
        del hair["design"]
        self.assertEqual(garments.problems(hair, m, r), ["hair fixture_hair lacks design"])
        ## PERTURB: a new hairstyle naming no builder variant.
        hair = self.hair(m)
        del hair["design"]["variant"]
        self.assertTrue(any("names the builder variant" in p for p in garments.problems(hair, m, r)))

    def test_a_hairstyle_version_builds_the_variant_it_was_approved_with(self):
        ## ARRANGE: Wolf's two shipped definitions and their v001 library copies (approved
        ## before design.variant existed), and a candidate naming its own variant.
        from character_modeling import asset_library
        shipped = {s: garments.load(CHARACTERS.parent / "garments" / ("wolf_hair_%s.garment.json" % s)) for s in ("ranger", "training")}
        library = {s: asset_library.payload("wolf_hair_%s" % s, "wolf_hair_%s.garment.json" % s, "v001") for s in ("ranger", "training")}
        candidate = copy.deepcopy(shipped["ranger"])
        candidate["design"]["variant"] = "F"
        ## ACT / ASSERT: v001 rebuilds D and E whatever the builder's default; a named
        ## variant wins; an unknown object without one fails closed.
        for source in (shipped, library):
            self.assertEqual((garments.hair_variant(source["ranger"]), garments.hair_variant(source["training"])), ("D", "E"))
        self.assertEqual(garments.hair_variant(candidate), "F")
        unnamed = dict(candidate, source={"object": "HairOther"}, design={})
        with self.assertRaisesRegex(ValueError, "names no design.variant"):
            garments.hair_variant(unnamed)


class OutfitPairing(unittest.TestCase):
    def test_a_mantle_over_its_gambeson_is_a_valid_outfit(self):
        ## ARRANGE
        m, r = manifest(), regions()
        ## ACT / ASSERT
        self.assertEqual(garments.outfit_problems([gambeson(m), mantle(m)], m, r), [])

    def test_a_required_underlayer_missing_or_an_incompatible_pair_is_refused(self):
        ## ARRANGE
        m, r = manifest(), regions()
        ## PERTURB: the mantle alone; then a jacket that refuses the mantle.
        alone = garments.outfit_problems([mantle(m)], m, r)
        jacket = gambeson(m)
        jacket.update({"id": "fixture_jacket", "incompatible_with": ["fixture_mantle"]})
        clash = garments.outfit_problems([jacket, mantle(m) | {"requires": []}], m, r)
        twice = garments.outfit_problems([gambeson(m), gambeson(m)], m, r)
        ## ASSERT
        self.assertTrue(any("requires fixture_gambeson" in p for p in alone), alone)
        self.assertTrue(any("cannot be worn with" in p for p in clash), clash)
        self.assertTrue(any("twice" in p for p in twice), twice)


class BodyMask(unittest.TestCase):
    def strip(self):
        ## A 1 x 6 strip of quads: vertices 0..13, faces left to right.
        faces = [(i, i + 1, i + 8, i + 7) for i in range(6)]
        return faces

    def test_the_mask_keeps_a_margin_ring_under_the_garment_edge(self):
        ## ARRANGE: every vertex of faces 1..4 hidden (columns 1..5).
        faces = self.strip()
        hidden = {1, 2, 3, 4, 5, 8, 9, 10, 11, 12}
        ## ACT
        none = garments.masked_faces(faces, hidden, margin_rings=0)
        one = garments.masked_faces(faces, hidden, margin_rings=1)
        ## ASSERT: without margin faces 1..4 go; one ring keeps 1 and 4 at the edge.
        self.assertEqual(none, [1, 2, 3, 4])
        self.assertEqual(one, [2, 3])

    def test_the_hole_left_by_the_mask_is_reported(self):
        ## ARRANGE
        faces = self.strip()
        ## ACT: remove faces 2 and 3.
        holes = garments.open_boundary_after_mask(faces, [2, 3])
        ## ASSERT: the two cut edges, between faces 1|2 and 3|4.
        self.assertEqual(holes, [(2, 9), (4, 11)])

    def test_the_hidden_set_is_the_union_of_every_garments_hides(self):
        ## ARRANGE
        m, r = manifest(), regions()
        ## ACT
        hidden = garments.hidden_vertices([gambeson(m), mantle(m)], r)
        ## ASSERT: exactly the upper torso and waist vertices.
        expected = set(r["regions"]["upper_torso"]["vertices"]) | set(r["regions"]["waist"]["vertices"])
        self.assertEqual(hidden, expected)


if __name__ == "__main__":
    unittest.main()
