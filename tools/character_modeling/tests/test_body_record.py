"""TEST-TRUTH: the body record's measurements, the regression between a baseline and a
candidate, and the frozen v1 baseline. Each test states its fixture (ARRANGE), the defect
it adds (PERTURB), the production call (ACT), and the contract (ASSERT)."""

from __future__ import annotations

import copy
import json
import unittest

from character_modeling import baseline_freeze, body_record


def box_torso():
    """A 0.4 m wide, 0.3 m deep box from 1.0 to 1.4 m riding Chest, and a 0.5 m left
    upper arm of radius 0.05 riding UpperArm.L."""
    points, dominant = [], []
    for z in (1.0, 1.4):
        for x, y in ((-0.2, -0.15), (0.2, -0.15), (0.2, 0.15), (-0.2, 0.15)):
            points.append((x, y, z))
            dominant.append("Chest")
    edges = [(i, i + 4) for i in range(4)]
    for t in (0.0, 0.5, 1.0):
        for x, z in ((0.05, 0.0), (-0.05, 0.0), (0.0, 0.05), (0.0, -0.05)):
            points.append((0.3 + t * 0.5, x, 1.3 + z))
            dominant.append("UpperArm.L")
    bones = {"UpperArm.L": ((0.3, 0.0, 1.3), (0.8, 0.0, 1.3)), "UpperArm.R": ((-0.3, 0.0, 1.3), (-0.8, 0.0, 1.3))}
    return points, edges, dominant, bones


def record():
    points, edges, dominant, bones = box_torso()
    island = body_record.head_island([(0.0, 0.0, 1.7), (0.05, 0.0, 1.75)], [{"Head": 1.0}, {"Head": 1.0}])
    configuration = {"bounds": {"min": [-0.2, -0.15, 0.0], "max": [0.2, 0.15, 1.8]},
                     "torso": body_record.torso_sections(points, edges, dominant, heights=(1.2,)),
                     "limbs": body_record.limb_girths(points, dominant, bones)}
    return {"topology": {"fingerprint": "a", "triangles": 2016, "vertices": 1025},
            "bones": {"Head": {"parent": "Neck", "head": [0, 0, 1.505], "tail": [0, 0, 1.8], "axes": [1, 0, 0, 0, 1, 0, 0, 0, 1]}},
            "head_island": island, "keys": {"mass_plus": {}, "mass_minus": {}},
            "configurations": {"default": configuration, "heavy": copy.deepcopy(configuration)}}


class Measurements(unittest.TestCase):
    def test_a_box_torso_and_a_round_arm_measure_as_built(self):
        ## ARRANGE / ACT
        points, edges, dominant, bones = box_torso()
        torso = body_record.torso_sections(points, edges, dominant, heights=(1.2, 2.0))
        limbs = body_record.limb_girths(points, dominant, bones)
        ## ASSERT: width and depth of the cut; no cut above the body; the arm's radius by station.
        self.assertEqual(torso["1.20"], {"width": 0.4, "depth": 0.3, "front": -0.15, "back": 0.15})
        self.assertNotIn("2.00", torso)
        self.assertEqual(sorted(limbs["UpperArm.L"]), ["0.0", "0.6", "1.0"])
        self.assertAlmostEqual(limbs["UpperArm.L"]["0.0"]["mean_r"], 0.05, places=4)
        self.assertNotIn("UpperArm.R", limbs)


class Regression(unittest.TestCase):
    def test_a_candidate_that_keeps_the_protected_parts_has_no_hard_problem(self):
        ## ARRANGE: the same rig, head island, keys, crown; a retopologized, sculpted body.
        baseline, candidate = record(), record()
        candidate["topology"] = {"fingerprint": "b", "triangles": 6400, "vertices": 3300}
        candidate["configurations"]["default"]["torso"]["1.20"]["width"] = 0.43
        ## PERTURB: the island's vertices listed in another order (a new topology numbers them anew).
        candidate["head_island"] = list(reversed(candidate["head_island"]))
        candidate["head_island"] = body_record.head_island([r[0] for r in candidate["head_island"]],
                                                           [r[1] for r in candidate["head_island"]])
        ## ACT
        hard, report = body_record.compare(baseline, candidate)
        ## ASSERT: nothing protected changed; the sculpt is reported as a measured delta.
        self.assertEqual(hard, [])
        self.assertTrue(report["topology"]["changed"])
        self.assertEqual(report["topology"]["triangles"], [2016, 6400])
        self.assertAlmostEqual(report["configurations"]["default"]["torso"]["1.20"]["width"], 0.03, places=4)

    def test_moving_a_joint_the_face_or_the_crown_or_losing_a_key_is_hard(self):
        ## PERTURB: a moved head joint, a moved face vertex, a reweighted one, a lost key,
        ## a lost configuration, a lower crown.
        baseline, candidate = record(), record()
        candidate["bones"]["Head"]["head"] = [0, 0, 1.51]
        candidate["head_island"][0][0][2] += 0.002
        candidate["head_island"][1][1]["Head"] = 0.9
        del candidate["keys"]["mass_minus"]
        del candidate["configurations"]["heavy"]
        candidate["configurations"]["default"]["bounds"]["max"][2] = 1.79
        ## ACT
        hard, _report = body_record.compare(baseline, candidate)
        ## ASSERT: each named.
        for word in ("bone Head head moved", "1 vertices moved", "1 vertices reweighted", "mass_minus", "heavy", "crown"):
            self.assertTrue(any(word in p for p in hard), word)


class FrozenBaseline(unittest.TestCase):
    def test_the_v1_baseline_is_intact(self):
        ## ACT / ASSERT: every frozen file re-hashes to its recorded sha256; nothing extra.
        self.assertEqual(baseline_freeze.verify("v1"), [])

    def test_the_v1_baseline_holds_the_protected_sources_and_the_record(self):
        ## ARRANGE
        with open(baseline_freeze.BASELINES / "v1" / "baseline.json", encoding="utf-8") as handle:
            files = json.load(handle)["files"]
        with open(baseline_freeze.BASELINES / "v1" / "body_record.json", encoding="utf-8") as handle:
            frozen = json.load(handle)
        ## ASSERT: the master, the attire, both hair definitions, the seven configurations, the record.
        froms = {entry["from"] for entry in files.values()}
        for rel in baseline_freeze.SOURCES + baseline_freeze.EXPORTS:
            self.assertIn(rel, froms)
        self.assertEqual(frozen["topology"]["fingerprint"], "ea08f9e93cef77ba1c687d9286bbe216b4590109d6f710b783f38611ff75ac5d")
        self.assertEqual(sorted(frozen["configurations"]),
                         ["default", "extreme_heavy", "extreme_lean", "heavy", "heavy_half", "lean", "lean_half"])
        self.assertEqual(len(frozen["keys"]), 16)

    def test_a_changed_or_extra_file_breaks_a_baseline(self):
        ## ARRANGE: a scratch baseline of one file.
        import tempfile
        from pathlib import Path
        with tempfile.TemporaryDirectory() as scratch:
            target = Path(scratch) / "vX"
            target.mkdir()
            (target / "a.txt").write_text("frozen", encoding="utf-8")
            manifest = {"schema": baseline_freeze.SCHEMA, "version": "vX",
                        "files": {"a.txt": {"from": "x", "sha256": baseline_freeze.sha256(target / "a.txt")}}}
            (target / "baseline.json").write_text(json.dumps(manifest), encoding="utf-8")
            ## ACT
            intact = baseline_freeze.verify("vX", scratch)
            ## PERTURB: the file edited, and a file slipped in.
            (target / "a.txt").write_text("edited", encoding="utf-8")
            (target / "b.txt").write_text("new", encoding="utf-8")
            broken = baseline_freeze.verify("vX", scratch)
        ## ASSERT
        self.assertEqual(intact, [])
        self.assertTrue(any("a.txt changed" in p for p in broken))
        self.assertTrue(any("b.txt is not part" in p for p in broken))


if __name__ == "__main__":
    unittest.main()


def ring(centre, radius, axis, sides=64):
    """`sides` points of a circle of `radius` about `centre`, perpendicular to `axis` (x or z)."""
    import math
    out = []
    for k in range(sides):
        a = 2.0 * math.pi * k / sides
        c, s = radius * math.cos(a), radius * math.sin(a)
        out.append((centre[0], centre[1] + c, centre[2] + s) if axis == "x" else (centre[0] + c, centre[1] + s, centre[2]))
    return out


class TapeGirths(unittest.TestCase):
    def test_a_tape_reads_the_circumference_and_skips_the_head(self):
        import math
        ## ARRANGE: a 0.18 m-radius chest ring at the chest station, a 0.06 m upper-arm ring
        ## across UpperArm.L at its middle, and a head ring at the neck station.
        chest = ring((0.0, 0.0, 1.27), 0.18, "z")
        arm = ring((0.45, 0.0, 1.30), 0.06, "x")
        head = ring((0.0, 0.0, 1.545), 0.09, "z")
        neck = ring((0.0, 0.0, 1.545), 0.06, "z")
        points = chest + arm + neck + head
        bones = {"UpperArm.L": ((0.3, 0.0, 1.30), (0.6, 0.0, 1.30)), "Forearm.L": ((0.6, 0.0, 1.3), (0.9, 0.0, 1.3)),
                 "UpperLeg.L": ((0.1, 0.0, 0.9), (0.1, 0.0, 0.45)), "LowerLeg.L": ((0.1, 0.0, 0.45), (0.1, 0.0, 0.05))}
        head_indices = range(len(points) - len(head), len(points))
        ## ACT
        out = body_record.tape_girths(points, bones, head_indices)
        ## ASSERT: the hull of a 64-gon is its circumference within 0.1 %.
        self.assertAlmostEqual(out["chest"], round(2 * math.pi * 18.0, 1), delta=0.2)
        self.assertAlmostEqual(out["upper_arm"], round(2 * math.pi * 6.0, 1), delta=0.1)
        self.assertAlmostEqual(out["neck"], round(2 * math.pi * 6.0, 1), delta=0.1)
        ## PERTURB: without the exclusion the head's ring is read as the neck.
        self.assertAlmostEqual(body_record.tape_girths(points, bones)["neck"], round(2 * math.pi * 9.0, 1), delta=0.1)
        self.assertEqual(body_record.tape_ratios({"chest": 112.0}, "default"), {"chest": 1.0})
