"""TEST-TRUTH: profile schema v2 and migration, the region-to-rig contract,
Wolf's cross-language baseline, and the build manifest. Each test states its
fixture (ARRANGE), the defect it adds (PERTURB), the production call (ACT),
and the contract (ASSERT)."""

from __future__ import annotations

import copy
import json
import tempfile
import unittest
from pathlib import Path

from character_modeling import anatomy, baseline, definition, manifest
from character_modeling.parameters import BODY_BY_ID, BODY_INPUTS, BY_ID, SLIDERS


def pending_profile():
    return {
        "schema": definition.SCHEMA,
        "version": definition.VERSION,
        "id": "fixture",
        "label": "M",
        "title": "fixture",
        "status": "pending",
        "pose": "relaxed-a-pose",
        "body": definition.default_body(),
        "sliders": {slider.id: slider.default for slider in SLIDERS},
    }


def rig_bones():
    return [bone["name"] for bone in json.loads(baseline.RIG_CONTRACT.read_text(encoding="utf-8"))["bones"]]


class ProfileSchema(unittest.TestCase):
    def test_wolf_defaults_resolve_and_every_shipped_profile_is_current(self):
        profile = pending_profile()
        self.assertEqual(definition.validate(profile), [])
        resolved = definition.resolve(profile)
        self.assertEqual(resolved["body"], {"height_m": 1.8, "frame_build": 1.0, "muscularity": 1.0})
        self.assertEqual(resolved["body"]["height_m"], baseline.REFERENCE_HEIGHT_M)
        for path in sorted(definition.PROFILES.glob("*.json")):
            if path.name.endswith(".manifest.json"):
                continue
            self.assertEqual(json.loads(path.read_text(encoding="utf-8"))["version"], definition.VERSION, path.name)
            self.assertEqual(definition.load_profile(path)["body"], definition.default_body(), path.name)

    def test_bad_body_inputs_are_refused_by_name(self):
        base = pending_profile()
        cases = (
            ({"height_m": 2.01}, "body.height_m=2.01 is outside 1.6..2.0"),
            ({"frame_build": 0.84}, "body.frame_build=0.84 is outside 0.85..1.15"),
            ({"muscularity": True}, "body.muscularity must be a number"),
            ({"weight_kg": 90.0}, "unknown body input weight_kg"),
        )
        for change, expected in cases:
            profile = copy.deepcopy(base)
            profile["body"].update(change)
            self.assertIn(expected, definition.validate(profile))
        missing = copy.deepcopy(base)
        del missing["body"]["muscularity"]
        self.assertIn("missing body input muscularity", definition.validate(missing))
        self.assertIn("body must be an object", definition.validate(dict(base, body=None)))

    def test_body_inputs_are_independent_of_the_shape_sliders(self):
        self.assertFalse(set(BODY_BY_ID) & set(BY_ID))
        self.assertTrue(all(entry.affects for entry in BODY_INPUTS))
        frame = BODY_BY_ID["frame_build"].affects
        self.assertNotIn("strength_scale", frame, "a wider skeleton is not a stronger one")
        self.assertNotIn("turn_support_scale", frame, "breadth adds inertia, not turn torque")
        self.assertNotIn("push_radius_m", BODY_BY_ID["muscularity"].affects, "muscle is not the spacing footprint")


class Migration(unittest.TestCase):
    def test_version_one_migrates_to_wolf_and_is_not_mutated(self):
        legacy = pending_profile()
        del legacy["body"]
        legacy["version"] = 1
        snapshot = copy.deepcopy(legacy)
        migrated = definition.migrate(legacy)
        self.assertEqual(legacy, snapshot)
        self.assertEqual(migrated["version"], definition.VERSION)
        self.assertEqual(migrated["body"], definition.default_body())
        self.assertEqual(definition.validate(migrated), [])

    def test_unknown_version_fails_clearly_instead_of_being_reinterpreted(self):
        future = dict(pending_profile(), version=99)
        self.assertIs(definition.migrate(future), future)
        self.assertIn("version must be %s" % definition.VERSION, definition.validate(future))
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "future.json"
            path.write_text(json.dumps(future), encoding="utf-8")
            with self.assertRaises(ValueError):
                definition.load_profile(path)


class RegionContract(unittest.TestCase):
    def test_creation_anchors_are_not_the_deformation_candidates(self):
        # The contract changed: a region used to name the one bone it "rides".
        # Anchors are the joints the surface is built around. Deform candidates
        # are the bones that may influence it. A shoulder is not UpperArm, and
        # it is not only the clavicle.
        self.assertEqual(anatomy.validate_region_contract(rig_bones()), [])
        self.assertEqual(anatomy.validate_deform_ownership(), [])
        self.assertEqual(tuple(region.id for region in anatomy.REGION_DEFINITIONS), anatomy.REGIONS)
        shoulder = anatomy.REGION_BY_ID["shoulder"]
        self.assertEqual(shoulder.anchors, ("Shoulder.L", "Shoulder.R"))
        self.assertEqual(set(shoulder.deform_bones), {"Shoulder.L", "Shoulder.R", "UpperArm.L", "UpperArm.R", "Chest"})
        self.assertNotEqual(set(shoulder.anchors), set(shoulder.deform_bones))
        self.assertEqual(shoulder.max_influences, 4)
        self.assertEqual(shoulder.construction, "socket weld and deltoid cap")
        self.assertIn("deltoid_fullness", shoulder.controls)
        self.assertIn("UpperArm.L.tail", anatomy.REGION_BY_ID["upper_arm"].protected_landmarks)
        for region in anatomy.REGION_DEFINITIONS:
            self.assertLessEqual(set(region.anchors), set(region.deform_bones))
            self.assertLessEqual(region.max_influences, 4)

    def test_a_renamed_bone_or_one_sided_neighbor_is_reported(self):
        renamed = [name.replace("UpperArm", "Bicep") for name in rig_bones()]
        problems = anatomy.validate_region_contract(renamed)
        self.assertIn("upper_arm anchors unknown bone UpperArm.L", problems)
        self.assertIn("upper_arm deforms with unknown bone UpperArm.L", problems)
        self.assertIn("upper_arm protects unknown landmark UpperArm.L.head", problems)
        original = anatomy.REGION_BY_ID["hand"].neighbors
        try:
            anatomy.REGION_BY_ID["hand"].neighbors = ("forearm", "calf")
            problems = anatomy.validate_region_contract(rig_bones())
        finally:
            anatomy.REGION_BY_ID["hand"].neighbors = original
        self.assertIn("hand and calf must name each other as neighbors", problems)


class WolfBaseline(unittest.TestCase):
    def test_python_reference_matches_physical_baseline_in_gdscript(self):
        self.assertEqual(baseline.game_baseline(), baseline.reference())
        self.assertEqual(baseline.reference()["height_m"], 1.8)
        self.assertEqual(baseline.reference()["mass_kg"], 80.0)

    def test_a_retuned_gdscript_constant_is_caught(self):
        text = baseline.PHYSICAL_BASELINE_GD.read_text(encoding="utf-8")
        self.assertIn("const FIGHTER_HEIGHT_M := 1.80", text)
        with tempfile.TemporaryDirectory() as folder:
            drifted = Path(folder) / "physical_baseline.gd"
            drifted.write_text(text.replace("const FIGHTER_HEIGHT_M := 1.80", "const FIGHTER_HEIGHT_M := 1.75"), encoding="utf-8")
            self.assertNotEqual(baseline.game_baseline(drifted), baseline.reference())
            renamed = Path(folder) / "renamed.gd"
            renamed.write_text(text.replace("FIGHTER_MASS_KG", "BODY_MASS_KG"), encoding="utf-8")
            with self.assertRaises(ValueError):
                baseline.game_baseline(renamed)


class BuildManifest(unittest.TestCase):
    def setUp(self):
        self.path = definition.PROFILES / "male_base.manifest.json"
        self.data = json.loads(self.path.read_text(encoding="utf-8"))

    def test_the_model_a_manifest_is_valid_and_pins_its_profile(self):
        self.assertEqual(manifest.validate(self.data, definition.PROFILES), [])
        self.assertEqual(self.data["study"]["label"], "A")
        self.assertEqual(self.data["status"], "pending")
        self.assertEqual(manifest.load_manifest(self.path)["model"], "male_base_a")

    def test_a_changed_profile_wrong_baseline_or_self_acceptance_is_refused(self):
        with tempfile.TemporaryDirectory() as folder:
            profile = Path(folder) / self.data["profile"]
            original = (definition.PROFILES / self.data["profile"]).read_bytes()
            profile.write_bytes(original.replace(b"\n", b"\r\n"))
            self.assertEqual(manifest.validate(self.data, folder), [], "CRLF checkout keeps the hash")
            profile.write_bytes(original.replace(b'"shoulder_breadth": 3.0', b'"shoulder_breadth": 3.1'))
            self.assertIn("profile male_base.json changed since the manifest was written",
                          manifest.validate(self.data, folder))
        heavy = copy.deepcopy(self.data)
        heavy["physical_baseline"]["mass_kg"] = 90.0
        self.assertIn("physical_baseline.mass_kg must be Wolf's 80.0", manifest.validate(heavy, definition.PROFILES))
        accepted = dict(self.data, status="accepted")
        self.assertIn("status must be study or pending until a person accepts the build",
                      manifest.validate(accepted, definition.PROFILES))
        partial = {key: value for key, value in self.data.items() if key != "validation"}
        self.assertIn("validation is required", manifest.validate(partial, definition.PROFILES))


if __name__ == "__main__":
    unittest.main()
