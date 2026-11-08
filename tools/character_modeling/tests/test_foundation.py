"""The default foundation (CHARACTER-FOUNDATION-001): one document, checked, character-free."""
import copy
import json
import unittest
from pathlib import Path

from character_modeling import appearance, asset_library, foundation, garments, variation

ROOT = Path(__file__).resolve().parents[3]
BLENDER = ROOT / "art-src" / "blender"
CHARACTERS = BLENDER / "characters"


def document():
    """The current approved foundation document (the library's current version)."""
    return foundation.load(asset_library.current_foundation_document())


def v001():
    """The superseded v001 document, kept in place for rollback: it predates the optional
    switches (ears, seat_neck, head_design)."""
    return foundation.load(CHARACTERS / "male_base.foundation.json")


REFERENCE = {"height_m": 1.8, "frame_build": 1.0, "muscularity": 1.0}


def current(kind):
    """The current foundation's record or regions."""
    return json.loads(Path(foundation.path_of(document(), kind, BLENDER)).read_text(encoding="utf-8"))


def wolf():
    return json.loads((CHARACTERS / "wolf" / "wolf.assembly.json").read_text(encoding="utf-8"))


class Document(unittest.TestCase):
    def test_the_shipped_foundation_is_consistent_and_resolves_the_reference(self):
        ## ARRANGE: the committed foundation.
        doc = document()
        ## ACT / ASSERT: no problems; the reference body is 1.80 m and 80 kg.
        self.assertEqual(foundation.problems(doc), [])
        self.assertEqual((doc["reference"]["height_m"], doc["reference"]["mass_kg"]), (1.8, 80.0))

    def test_the_foundation_owns_no_character(self):
        ## ARRANGE: the default identity is a palette and a face; nothing else.
        doc = document()
        ## ASSERT: no hair, no attire, no outfits; the face is the three default marks.
        self.assertEqual(set(doc["default_identity"]), {"skin_swatches", "palette", "face"})
        self.assertEqual(set(doc["default_identity"]["face"]["marks"]), set(foundation.FACE_MARKS))
        self.assertNotIn("outfits", doc)
        self.assertNotIn("garments", json.dumps(doc["resolution"]))

    def test_an_inconsistent_foundation_is_refused_with_its_reason(self):
        ## PERTURB: an unknown study, a missing switch, a coloured skin, a wrong reference mass.
        cases = {
            "unknown chest": (("resolution", "chest_study"), "no_such_chest", "not a chest study"),
            "unknown silhouette": (("resolution", "glute_study"), "no_such", "not a silhouette study"),
            "bad passes": (("resolution", "rig_weight_smooth_iterations"), -1, "count of passes"),
            "mass": (("reference", "mass_kg"), 95.0, "resolves to"),
        }
        for label, ((block, key), value, reason) in cases.items():
            doc = copy.deepcopy(document())
            doc[block][key] = value
            ## ACT / ASSERT
            self.assertTrue(any(reason in p for p in foundation.problems(doc)), label)
        doc = copy.deepcopy(document())
        del doc["resolution"]["chest_fit"]
        self.assertTrue(any("resolution lacks" in p for p in foundation.problems(doc)))
        doc = copy.deepcopy(document())
        doc["default_identity"]["palette"]["skin"] = {"srgb": [1, 0, 0], "roughness": 0.5}
        self.assertTrue(any("shared swatch" in p for p in foundation.problems(doc)))
        self.assertEqual(foundation.problems({"schema": "other"}), ["not a %s" % foundation.SCHEMA])


class Apply(unittest.TestCase):
    def test_apply_sets_the_base_design_studies_and_default_face_on_a_copy(self):
        ## ARRANGE: a resolved configuration as variation.resolve returns it.
        doc = document()
        resolved = {"body": dict(REFERENCE), "parameters": {"mass": 0.0}}
        ## ACT
        out = foundation.apply(resolved, doc)
        ## ASSERT: every resolution key (the head study with the reference anchor's design
        ## studies on top), the mask study, the default marks; input untouched.
        design = doc["resolution"].get("head_design", {}).get("reference", {})
        for key in foundation.RESOLUTION_KEYS:
            self.assertEqual(out[key], dict(doc["resolution"][key], **design) if key == "head_study" else doc["resolution"][key])
        self.assertEqual(out["mask_study"], doc["base"]["mask_study"])
        self.assertIs(out["marks"], doc["default_identity"]["face"]["marks"])
        self.assertNotIn("marks", resolved)
        ## PERTURB: an identity's own marks replace the default face.
        own = {"Eye": {}}
        self.assertIs(foundation.apply(resolved, doc, own)["marks"], own)

    def test_an_optional_switch_is_off_when_absent_and_on_when_a_revision_names_it(self):
        ## ARRANGE: v001 predates `ears` (absent); the current revision names it.
        doc = v001()
        self.assertNotIn("ears", doc["resolution"])
        self.assertIs(foundation.apply({"body": dict(REFERENCE), "parameters": {"mass": 0.0}}, document())["ears"], True)
        resolved = {"body": {"height_m": 1.8}, "parameters": {"mass": 0.0}}
        ## ACT / ASSERT: absent resolves off, and the document stays consistent.
        self.assertIs(foundation.apply(resolved, doc)["ears"], False)
        self.assertEqual(foundation.problems(doc), [])
        ## PERTURB: a revision turns it on; then a non-boolean value.
        revised = copy.deepcopy(doc)
        revised["resolution"]["ears"] = True
        self.assertEqual(foundation.problems(revised), [])
        self.assertIs(foundation.apply(resolved, revised)["ears"], True)
        revised["resolution"]["ears"] = 1
        self.assertIn("ears is a switch (true or false)", foundation.problems(revised))
        ## The neck seating switch: absent off; named on; never anything but a boolean.
        self.assertIs(foundation.apply(resolved, doc)["seat_neck"], False)
        revised["resolution"]["ears"] = True
        revised["resolution"]["seat_neck"] = True
        self.assertEqual(foundation.problems(revised), [])
        self.assertIs(foundation.apply(resolved, revised)["seat_neck"], True)
        revised["resolution"]["seat_neck"] = "yes"
        self.assertIn("seat_neck is a switch (true or false)", foundation.problems(revised))

    def test_the_ear_flare_follows_the_build_only_with_a_head_design(self):
        ## ARRANGE: a lean body; the document without, then with, a head design.
        from character_modeling import ear
        doc = v001()
        lean = {"body": {"height_m": 1.8, "frame_build": 0.85, "muscularity": 0.8}, "parameters": {"mass": 0.0}}
        ## ACT / ASSERT: without a design the ear keeps its flare (earlier candidates rebuild
        ## exactly); with one, the lean anchor's.
        self.assertEqual(foundation.apply(lean, doc)["ear_flare_deg"], ear.FLARE_DEG)
        revised = copy.deepcopy(doc)
        revised["resolution"]["head_design"] = {"lean": {"lean_face": 1.0}}
        self.assertAlmostEqual(foundation.apply(lean, revised)["ear_flare_deg"],
                               ear.design_flare(variation.design_coordinate(lean["body"])))
        self.assertEqual(foundation.apply(lean, doc)["ear_scale"], 1.0)
        self.assertLess(foundation.apply(lean, revised)["ear_scale"], 1.0)
        ## PERTURB: the lower-contour mask study is a known base switch.
        revised["base"]["mask_study"]["lower_contour"] = 1.0
        self.assertEqual(foundation.problems(revised), [])

    def test_a_head_design_adds_its_anchored_studies_to_the_shared_head_study(self):
        ## ARRANGE: a revision with a three-anchor design over the shared head study.
        doc = copy.deepcopy(document())
        shared = dict(doc["resolution"]["head_study"])
        doc["resolution"]["head_design"] = {"lean": {"lean_face": 1.0}, "reference": {"reference_face": 1.0},
                                            "strongman": {"heroic_jaw": 1.0}}
        self.assertEqual(foundation.problems(doc), [])
        ## ACT: the reference and the strongman.
        reference = foundation.apply({"body": {"height_m": 1.8, "frame_build": 1.0, "muscularity": 1.0}}, doc)
        strong = foundation.apply({"body": {"height_m": 1.8, "frame_build": 1.15, "muscularity": 1.25}}, doc)
        ## ASSERT: the shared studies everywhere, each anchor's own on top, zero studies dropped.
        self.assertEqual(reference["head_study"], dict(shared, reference_face=1.0))
        self.assertEqual(strong["head_study"], dict(shared, heroic_jaw=1.0))
        ## PERTURB: an unknown anchor and an unknown study are refused.
        doc["resolution"]["head_design"] = {"giant": {"heroic_jaw": 1.0}, "lean": {"no_such_study": 1.0}}
        problems = foundation.problems(doc)
        self.assertTrue(any("anchor giant" in p for p in problems))
        self.assertTrue(any("no_such_study" in p for p in problems))


class VariantGeneration(unittest.TestCase):
    """Three approval scopes: a variant switch is set by variant generation (its own
    version), never turned on in the canonical foundation."""

    def test_variants_set_their_switches_over_the_foundations_defaults(self):
        ## ARRANGE: the document (face response off) and a variants version turning it on.
        doc = document()
        on = {"schema": foundation.VARIANT_SCHEMA, "foundation": doc["id"], "settings": {"face_response": True}}
        ## ACT
        resolved = foundation.apply({"body": dict(REFERENCE)}, doc, variants=on)
        ## ASSERT: the switch from variant generation, every canonical key from the document.
        self.assertTrue(resolved["face_response"])
        self.assertFalse(foundation.apply({"body": dict(REFERENCE)}, doc)["face_response"])
        self.assertEqual(resolved["chest_study"], doc["resolution"]["chest_study"])

    def test_variant_generation_fails_closed_outside_its_scope(self):
        doc = document()
        ## PERTURB: a canonical switch, another foundation, a non-boolean, the wrong schema.
        cases = {
            "not variant switches": {"schema": foundation.VARIANT_SCHEMA, "foundation": doc["id"], "settings": {"chest_fit": True}},
            "not %s" % doc["id"]: {"schema": foundation.VARIANT_SCHEMA, "foundation": "character.other", "settings": {}},
            "true or false": {"schema": foundation.VARIANT_SCHEMA, "foundation": doc["id"], "settings": {"face_response": 1}},
            "not a %s" % foundation.VARIANT_SCHEMA: {"schema": "other"},
        }
        for reason, variants in cases.items():
            with self.assertRaisesRegex(ValueError, reason):
                foundation.apply({"body": dict(REFERENCE)}, doc, variants=variants)
        ## A variant switch turned on in the canonical document is refused.
        canonical = copy.deepcopy(doc)
        canonical["resolution"]["face_response"] = True
        self.assertTrue(any("set by variant generation" in p for p in foundation.problems(canonical)))


class Characters(unittest.TestCase):
    def test_wolf_is_built_on_the_current_foundation_at_the_reference_with_his_refined_face(self):
        ## ARRANGE: Wolf's manifest and the current foundation.
        doc, character = document(), wolf()
        block = character["foundation"]
        ## ACT
        marks = foundation.character_marks(doc, character)
        ## ASSERT: consistent; the current document; the reference body; clean-shaven; the
        ## default face with exactly his refinement (library wolf_face) laid over it.
        self.assertEqual(foundation.character_problems(doc, character), [])
        self.assertEqual(asset_library.canonical(BLENDER / block["definition"]), asset_library.current_foundation_document())
        self.assertEqual(block["body"], {k: doc["reference"][k] for k in ("height_m", "frame_build", "muscularity")})
        self.assertNotIn("facial_hair", block)
        self.assertEqual(block["face_refine"], asset_library.payload("wolf_face", "wolf_face.json")["face_refine"])
        default = doc["default_identity"]["face"]["marks"]
        for name, mark in marks.items():
            refined = block["face_refine"].get(name, {})
            for key, value in mark.items():
                expected = refined.get(key, default[name][key])
                if isinstance(expected, dict) and isinstance(default[name].get(key), dict):
                    expected = dict(default[name][key], **expected)
                self.assertEqual(value, expected, "%s.%s" % (name, key))

    def test_a_character_on_another_foundation_or_face_mode_is_refused(self):
        doc = document()
        ## PERTURB: another foundation id, an unknown face mode, no foundation at all.
        character = wolf()
        character["foundation"]["id"] = "character.other"
        character["foundation"]["face"] = "borrowed"
        problems = foundation.character_problems(doc, character)
        ## ASSERT
        self.assertTrue(any("not %s" % doc["id"] in p for p in problems))
        self.assertTrue(any("foundation.face" in p for p in problems))
        bare = wolf()
        del bare["foundation"]
        self.assertTrue(foundation.character_problems(doc, bare))

    def test_a_garment_targets_the_foundation_body_fingerprint(self):
        ## ARRANGE: the foundation's record and a garment fitted to it.
        doc, character = document(), wolf()
        record = current("record")
        target = foundation.garment_target(doc, record, character)
        regions = {"regions": {"upper_torso": {"physique": ["mass"]}}, "clearance_m": {"fitted": [0.003, 0.02]}}
        garment = {"schema": garments.SCHEMA, "type": "garment", "id": "fixture_shirt", "base_id": doc["id"],
                   "base_topology_fingerprint": record["objects"]["BodyV2"]["sha256"],
                   "skeleton_id": doc["skeleton"]["id"], "rig_contract_sha256": doc["skeleton"]["contract_sha256"],
                   "category": "fitted", "regions": ["upper_torso"], "source": {"blend": "x", "object": "Shirt"},
                   "deformation": {"method": "skinned", "max_influences": 4, "physique": "keys"},
                   "supported_configurations": list(character["physique"]["supported_configurations"]),
                   "materials": ["fabric"], "layer": 1, "coverage": {"hides": ["upper_torso"]}}
        ## ACT / ASSERT: compatible with the foundation...
        self.assertEqual(garments.problems(garment, target, regions), [])
        ## PERTURB: ...and refused when fitted to v1's base.
        stale = dict(garment, base_id="character.male_base")
        self.assertTrue(garments.problems(stale, target, regions))


class Independence(unittest.TestCase):
    """The foundation stays character-independent: resolving variants and layering characters
    never mutates it, and a second character consumes it without inheriting Wolf's layers."""

    def _resolved(self, h, f, m):
        configuration = json.loads((CHARACTERS / "male_base.v2.configuration.json").read_text(encoding="utf-8"))
        return variation.resolve({"body": {"height_m": h, "frame_build": f, "muscularity": m}}, configuration)

    def test_resolving_variants_and_layering_wolf_never_mutate_the_foundation(self):
        ## ARRANGE: the foundation document, frozen as text before anything reads it.
        doc = document()
        before = json.dumps(doc, sort_keys=True)
        character = wolf()
        character["foundation"]["face_refine"] = {"Brow": {"height": 0.06}}
        ## ACT: a variant resolved with the face response, Wolf's refined face, the response
        ## applied to it, and his appearance plan.
        resolved = foundation.apply(self._resolved(2.0, 1.15, 1.25), doc)
        marks = foundation.character_marks(doc, character)
        variation.responded_marks(marks, variation.face_response(resolved))
        variation.responded_marks(resolved["marks"], variation.face_response(resolved))
        ## ASSERT: the document is unchanged, its default face unrefined.
        self.assertEqual(json.dumps(doc, sort_keys=True), before)
        self.assertNotEqual(marks["Brow"]["height"], doc["default_identity"]["face"]["marks"]["Brow"]["height"])

    def test_the_reference_variant_keeps_the_approved_face_and_others_resolve_their_own(self):
        ## ARRANGE: the default face at the reference and at two other variants.
        doc = document()
        default = doc["default_identity"]["face"]["marks"]
        ## ACT
        faces = {(h, f, m): variation.responded_marks(default, variation.face_response(self._resolved(h, f, m)))
                 for h, f, m in ((1.8, 1.0, 1.0), (1.6, 0.85, 0.8), (2.0, 1.15, 1.25))}
        ## ASSERT: the reference face is the approved one exactly; each other variant differs
        ## from it and from the other.
        self.assertEqual(faces[(1.8, 1.0, 1.0)], default)
        self.assertNotEqual(faces[(1.6, 0.85, 0.8)], default)
        self.assertNotEqual(faces[(2.0, 1.15, 1.25)], default)
        self.assertNotEqual(faces[(1.6, 0.85, 0.8)], faces[(2.0, 1.15, 1.25)])

    def test_a_second_character_uses_the_foundation_without_wolfs_layers(self):
        ## ARRANGE: a second character on the foundation: another body, the default face, no
        ## facial hair, an outfit with no hairstyle.
        doc = document()
        record = current("record")
        regions = current("regions")
        other = wolf()
        other.update(id="character.fixture_second", outfits={"bare": {"collections": [], "body_mask": None, "garments": []}})
        other["foundation"] = {"id": doc["id"], "body": {"height_m": 1.7, "frame_build": 0.9, "muscularity": 1.1}, "face": "default"}
        ## ACT
        plan = appearance.resolve(other, "bare", {}, regions, foundation.garment_target(doc, record, other))
        ## ASSERT: valid on the foundation; the default face; nothing of Wolf's in its plan.
        self.assertEqual(foundation.character_problems(doc, other), [])
        self.assertIs(foundation.character_marks(doc, other), doc["default_identity"]["face"]["marks"])
        self.assertEqual(plan["components"], [])
        self.assertEqual(plan["visibility"]["hidden_regions"], {})
        self.assertEqual(plan["foundation_fingerprint"], record["objects"]["BodyV2"]["sha256"])


if __name__ == "__main__":
    unittest.main()
