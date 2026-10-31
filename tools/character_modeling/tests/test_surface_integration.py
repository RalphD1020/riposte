"""TEST-TRUTH: Character Surface Integration on synthetic measurements and the shipped
declarations. Each test states its fixture (ARRANGE), the defect it adds (PERTURB), the
production call (ACT), and the contract (ASSERT). Real files: the base's surface
regions, its fitting regions (for the rig's bone names) and Wolf's two hairstyles."""

from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path

from character_modeling import surface_integration as si

ROOT = Path(__file__).resolve().parents[3]
CHARACTERS = ROOT / "art-src" / "blender" / "characters"
GARMENTS = ROOT / "art-src" / "blender" / "garments"
CALIBRATION = CHARACTERS / "male_base.surface_calibration.json"
## The rig frame the shipped regions are drawn on (WolfRig's rest joints, metres).
LANDMARKS = {"Neck": ((0.0, 0.0, 1.41), (0.0, 0.0, 1.505)), "Head": ((0.0, 0.0, 1.505), (0.0, 0.0, 1.8)),
             "Chest": ((0.0, 0.0, 1.18), (0.0, 0.0, 1.39))}


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def surfaces():
    return load(CHARACTERS / "male_base.surfaces.json")


def rig_bones():
    return {b for region in load(CHARACTERS / "male_base.regions.json")["regions"].values() for b in region["bones"]}


def hair(style):
    return load(GARMENTS / ("wolf_hair_%s.garment.json" % style))


def nape_lock(follow):
    """A lock down the back of the head: the body's radius from the axis widens to the
    occiput (0.105 m), narrows to the nape hollow (0.036 m) and flares over the
    trapezius; the hair starts 0.012 m off the skull and makes `follow` of the narrowing."""
    body = [0.08, 0.1, 0.105, 0.09, 0.06, 0.036, 0.05]
    narrowing = 0.105 - 0.036
    hair = [b + 0.012 for b in body[:3]] + [0.117 - follow * narrowing * s for s in (0.3, 0.7, 1.0)] + [0.07]
    return list(zip(hair, body))


class Regions(unittest.TestCase):
    def test_points_are_named_by_rig_band_and_sector_never_by_vertex(self):
        ## ARRANGE: points round a head on the shipped regions.
        regions = surfaces()
        ## ACT / ASSERT: crown, back of the skull, nape hollow, jaw, trapezius.
        self.assertEqual(si.classify((0.0, 0.02, 1.78), LANDMARKS, regions), "scalp")
        self.assertEqual(si.classify((0.0, 0.1, 1.64), LANDMARKS, regions), "occiput")
        self.assertEqual(si.classify((0.0, 0.036, 1.58), LANDMARKS, regions), "nape")
        self.assertEqual(si.classify((0.06, -0.05, 1.55), LANDMARKS, regions), "jaw")
        self.assertEqual(si.classify((0.1, 0.03, 1.38), LANDMARKS, regions), "trapezius")
        ## PERTURB: the same point mirrored is the same region (sectors are symmetric).
        self.assertEqual(si.classify((-0.06, -0.05, 1.55), LANDMARKS, regions), "jaw")
        ## ...and a point on no declared band is no region.
        self.assertIsNone(si.classify((0.4, 0.0, 1.0), LANDMARKS, regions))

    def test_the_shipped_regions_sit_on_the_rig(self):
        ## ACT / ASSERT
        self.assertEqual(si.region_problems(surfaces(), rig_bones()), [])

    def test_the_head_and_neck_interfaces_group_declared_regions(self):
        ## ARRANGE / ACT / ASSERT: the shipped interfaces are valid.
        regions = surfaces()
        self.assertEqual(regions["interfaces"]["head_to_neck"], ["jaw", "nape", "neck_side", "throat"])
        ## PERTURB: an interface naming a region that does not exist, and one dropped.
        regions["interfaces"]["neck_to_shoulder"].append("clavicle_notch")
        del regions["interfaces"]["head_to_neck"]
        problems = si.region_problems(regions, rig_bones())
        self.assertTrue(any("unknown regions ['clavicle_notch']" in p for p in problems))
        self.assertTrue(any("interface head_to_neck names its regions" in p for p in problems))

    def test_a_region_on_an_unknown_bone_or_backwards_sector_is_refused(self):
        ## PERTURB: a bone outside the rig, a reversed sector, a duplicate name.
        regions = surfaces()
        regions["regions"][0]["bone"] = "Tail"
        regions["regions"][1]["sector"] = [180.0, 100.0]
        regions["regions"].append(copy.deepcopy(regions["regions"][2]))
        ## ACT
        problems = si.region_problems(regions, rig_bones())
        ## ASSERT
        self.assertTrue(any("Tail" in p for p in problems))
        self.assertTrue(any("sector" in p for p in problems))
        self.assertTrue(any("uniquely" in p for p in problems))


class Declarations(unittest.TestCase):
    def test_both_hairstyles_declare_valid_relationships(self):
        ## ACT / ASSERT
        for style in ("ranger", "training"):
            self.assertEqual(si.relationship_problems(hair(style), surfaces()), [], style)

    def test_a_component_must_say_how_it_meets_the_body(self):
        ## PERTURB: no surfaces block; then an unknown region, relationship, severity,
        ## source and design region.
        bare = hair("ranger")
        del bare["surfaces"]
        wrong = hair("training")
        wrong["surfaces"]["relationships"].append({"region": "elbow", "relationship": "glue", "severity": "fatal",
                                                   "source": "cape", "design_regions": ["tail"]})
        ## ACT
        missing = si.relationship_problems(bare, surfaces())
        problems = si.relationship_problems(wrong, surfaces())
        ## ASSERT
        self.assertEqual(len(missing), 1)
        self.assertIn("surfaces.relationships", missing[0])
        for word in ("unknown region", "relationship must be", "source is", "severity must be", "['tail']"):
            self.assertTrue(any(word in p for p in problems), word)

    def test_a_garment_source_is_a_valid_declaration(self):
        ## PERTURB: Training's hair declared against a future gambeson.
        component = hair("training")
        component["surfaces"]["relationships"].append({"region": "trapezius", "relationship": "drape",
                                                       "source": "garment:ranger_gambeson", "design_regions": ["rear_mass"]})
        ## ACT / ASSERT
        self.assertEqual(si.relationship_problems(component, surfaces()), [])


class Conformity(unittest.TestCase):
    def test_hair_following_the_nape_is_measured_by_its_share_of_the_narrowing(self):
        ## ARRANGE / ACT
        result = si.conformity(nape_lock(0.6))
        ## ASSERT: 0.6 of the 0.069 m narrowing; the gap left in the hollow.
        self.assertAlmostEqual(result["follow"], 0.6, places=2)
        self.assertAlmostEqual(result["narrowing_m"], 0.069, places=3)
        self.assertAlmostEqual(result["gap_at_narrowest_m"], 0.117 - 0.6 * 0.069 - 0.036, places=3)

    def test_a_vertical_panel_follows_nothing_and_a_column_stands_away(self):
        ## PERTURB: hair that does not narrow; hair that moves away as the nape narrows.
        ## ACT / ASSERT
        self.assertAlmostEqual(si.conformity(nape_lock(0.0))["follow"], 0.0, places=3)
        self.assertLess(si.conformity(nape_lock(-0.4))["follow"], 0.0)

    def test_no_narrowing_no_judgement(self):
        ## ARRANGE: a body that only widens down the lock (a shoulder, not a nape).
        ## ACT / ASSERT
        self.assertIsNone(si.conformity([(0.06, 0.05), (0.07, 0.06), (0.08, 0.07)]))
        self.assertIsNone(si.conformity([(0.06, 0.05)]))


class Evaluate(unittest.TestCase):
    NAPE = {"region": "nape", "relationship": "drape", "severity": "warning", "design_regions": ["rear_mass"]}

    def test_a_draping_lock_that_follows_raises_nothing(self):
        ## ARRANGE: clear of the body, following the nape.
        measured = {"distances": [0.01, 0.015, 0.02, 0.03], "locks": {"Fall.01": nape_lock(0.6)}}
        ## ACT
        report, findings = si.evaluate(self.NAPE, measured)
        ## ASSERT: measured, uncalibrated (no bound), nothing flagged.
        self.assertEqual(findings, [])
        self.assertEqual(report["separation"]["count"], 4)
        self.assertIsNone(report["p90_bound_m"])
        self.assertAlmostEqual(report["conformity"]["Fall.01"]["follow"], 0.6, places=2)

    def test_a_column_is_a_warning_whatever_the_calibration(self):
        ## PERTURB: one lock standing away from the narrowing nape.
        measured = {"distances": [0.02, 0.05, 0.09], "locks": {"Fall.01": nape_lock(0.6), "Fall.02": nape_lock(-0.3)}}
        ## ACT
        _report, findings = si.evaluate(self.NAPE, measured)
        ## ASSERT
        self.assertEqual([(f["metric"], f["severity"], f["value"]) for f in findings], [("nape_conformity", "warning", ["Fall.02"])])

    def test_uncalibrated_separation_never_flags_and_calibrated_does(self):
        ## ARRANGE: hair floating 0.05-0.09 m over the nape.
        measured = {"distances": [0.05, 0.07, 0.09]}
        calibration = {"metrics": {"drape.p90_separation_m": {"value": 0.03, "margin": 1.25},
                                   "drape.min_follow": {"value": 0.5}}}
        ## ACT
        _r, uncalibrated = si.evaluate(self.NAPE, measured)
        _r, calibrated = si.evaluate(self.NAPE, dict(measured, locks={"Fall.01": nape_lock(0.3)}), calibration)
        ## ASSERT: no invented threshold; with one, separation and weak following are named.
        self.assertEqual(uncalibrated, [])
        self.assertEqual(sorted(f["metric"] for f in calibrated), ["nape_conformity", "separation"])
        self.assertTrue(all(f["severity"] == "warning" for f in calibrated))

    def test_penetration_at_rest_takes_the_declared_severity(self):
        ## PERTURB: a vertex 3 mm inside the side of the neck.
        rel = {"region": "neck_side", "relationship": "clearance", "severity": "hard", "design_regions": ["side_locks"]}
        ## ACT
        _r, findings = si.evaluate(rel, {"distances": [0.01, -0.003]})
        _r, tolerated = si.evaluate(rel, {"distances": [0.01, -0.0004]})
        ## ASSERT: mesh tolerance is not contact.
        self.assertEqual([(f["metric"], f["severity"]) for f in findings], [("penetration", "hard")])
        self.assertEqual(tolerated, [])

    def test_a_root_standing_off_the_scalp_is_hard_once_calibrated(self):
        ## ARRANGE: the shipped calibration (approved Ranger B's scalp cap).
        rel = {"region": "scalp", "relationship": "attach", "severity": "hard", "design_regions": ["scalp"]}
        calibration = load(CALIBRATION)
        ## ACT
        _r, seated = si.evaluate(rel, {"distances": [0.004, 0.012]}, calibration)
        ## PERTURB: a cap lifted 0.03 m off the scalp (a helmet).
        report, lifted = si.evaluate(rel, {"distances": [0.004, 0.03]}, calibration)
        ## ASSERT
        self.assertEqual(seated, [])
        self.assertAlmostEqual(report["max_gap_bound_m"], 0.015, places=4)
        self.assertEqual([(f["metric"], f["severity"]) for f in lifted], [("root_gap", "hard")])

    def test_nothing_on_a_region_is_fine_to_clear_and_suspicious_to_drape(self):
        ## ARRANGE: no measured part near the region.
        clear = {"region": "nape", "relationship": "clearance", "design_regions": ["rear_tie"]}
        ## ACT
        _r, cleared = si.evaluate(clear, {"distances": []})
        _r, draped = si.evaluate(self.NAPE, {"distances": []})
        ## ASSERT
        self.assertEqual(cleared, [])
        self.assertEqual([(f["metric"], f["severity"]) for f in draped], [("coverage", "advisory")])


class Deformation(unittest.TestCase):
    def test_envelope_failures_are_counted_by_anatomical_region(self):
        ## ARRANGE: failures nearest body vertices classified at rest; one on the arm.
        region_of = {10: "nape", 11: "nape", 12: "jaw", 13: None}
        failures = [{"nearest_body": 10}, {"nearest_body": 11}, {"nearest_body": 12}, {"nearest_body": 13}]
        ## ACT / ASSERT
        self.assertEqual(si.attribute(failures, region_of), {"jaw": 1, "nape": 2, "unclassified": 1})


if __name__ == "__main__":
    unittest.main()
