"""TEST-TRUTH: the production body. Each test states the profile it builds
(ARRANGE), what it changes (PERTURB), the builder or check it calls (ACT), and
the contract it holds (ASSERT):

- PRODUCTION-TOPOLOGY: fixed topology across profiles, deterministic.
- PRODUCTION-BODY: the named flesh seams (torso–shoulder, shoulder–upper
  arm, torso–pelvis, pelvis–leg), one component because the nude body has
  no intentional island, outward, within budget. The rejected loft is five
  manifold tubes: torso–shoulder and pelvis–leg are the missing seams.
- PRODUCTION-WEIGHTS: at most four normalized influences on real WolfRig
  bones; more than two only at the shoulder and the pelvis/groin (replaces
  "at most two"); weights come from per-vertex deformation regions, the
  girdle rides the clavicle and the arm, the trapezius never the neck bone.
- PRODUCTION-SHOULDER: the region checks pass on the body and fail on the
  frozen rejected mesh (the negative fixture).
- WolfRig geometry: crown, floor and lead foot (preserved).
"""

from __future__ import annotations

import copy
import json
import pathlib
import unittest

from character_modeling import anatomy, baseline, definition, diagnostics, production, production_checks
from character_modeling.mesh_data import MeshData

RIG = json.loads(baseline.RIG_CONTRACT.read_text(encoding="utf-8"))
BONES = {bone["name"] for bone in RIG["bones"]}
TRIANGLE_BUDGET = 2400  # the hero's cap (tools/blender/validate_assets.py)
REJECTED = pathlib.Path(__file__).parent / "fixtures" / "rejected_shoulder.json"


def wolf():
    return definition.load_profile(definition.PROFILES / "male_base.json")


def thicker():
    resolved = copy.deepcopy(wolf())
    style = resolved["style"]
    style["chest"] *= 1.2
    style["thigh"] = (style["thigh"][0] * 1.1, style["thigh"][1])
    style["shoulders"] *= 1.05
    return resolved


def rejected():
    data = json.loads(REJECTED.read_text(encoding="utf-8"))
    data["weights"] = [tuple((bone, w) for bone, w in weights) for weights in data["weights"]]
    data["faces"] = [tuple(face) for face in data["faces"]]
    return data


class FixedTopology(unittest.TestCase):
    def test_every_profile_shares_vertex_count_and_faces(self):
        base = production.build(wolf(), RIG)
        other = production.build(thicker(), RIG)
        self.assertEqual(len(base["vertices"]), len(other["vertices"]))
        self.assertEqual(base["faces"], other["faces"])
        self.assertEqual(base["pieces"], other["pieces"])
        self.assertEqual(base["sockets"], other["sockets"])
        self.assertNotEqual(base["vertices"], other["vertices"], "the shape moved")

    def test_the_same_profile_builds_the_same_mesh(self):
        self.assertEqual(production.build(wolf(), RIG), production.build(wolf(), RIG))


class OneBody(unittest.TestCase):
    def test_one_connected_closed_outward_body_inside_the_budget(self):
        mesh = production.build(wolf(), RIG)
        report = diagnostics.integrity(MeshData(mesh["vertices"], mesh["faces"]))
        seams = production_checks.flesh_seams(mesh)
        self.assertEqual(report, {"boundary_edges": 0, "nonmanifold_edges": 0, "inconsistent_winding_edges": 0,
                                  "degenerate_faces": 0, "components": 1})
        self.assertTrue(all(seams[name] for name in production_checks.FLESH_SEAMS), seams)
        self.assertEqual(seams["intentional_separate"], ())
        self.assertEqual(seams["components"], 1, "no intentional island, so one component")
        census = production_checks.component_census(mesh)
        self.assertEqual(len(census), 1, "watertight is not the same claim as one surface")
        self.assertEqual(census[0][1], len(mesh["faces"]))
        self.assertEqual([name for name, _first, _end in mesh["pieces"]],
                         ["Torso", "Arm.L", "Arm.R", "Leg.L", "Leg.R"])
        self.assertGreater(production.volume(mesh), 0.0)
        self.assertLessEqual(production.triangle_count(mesh["faces"]), TRIANGLE_BUDGET)

    def test_a_flipped_arm_breaks_winding_and_a_flipped_body_inverts_volume(self):
        mesh = production.build(wolf(), RIG)
        _name, first, end = mesh["pieces"][1]
        arm_flipped = [tuple(reversed(face)) if all(first <= i < end for i in face) else face for face in mesh["faces"]]
        report = diagnostics.integrity(MeshData(mesh["vertices"], arm_flipped))
        self.assertGreater(report["inconsistent_winding_edges"], 0)
        all_flipped = dict(mesh, faces=[tuple(reversed(face)) for face in mesh["faces"]])
        self.assertLess(production.volume(all_flipped), 0.0)

    def test_the_rejected_ring_loft_is_five_manifold_pieces_missing_two_seams(self):
        # Component count alone does not say which connection failed. Each
        # tube is manifold. The torso never shares an edge with an arm or a
        # leg; the deltoid cap still meets the upper arm inside the arm tube,
        # and the chest still meets the pelvis inside the torso tube.
        data = rejected()
        report = diagnostics.integrity(MeshData(data["vertices"], data["faces"]))
        seams = production_checks.flesh_seams(data)
        self.assertEqual(report["boundary_edges"] + report["nonmanifold_edges"], 0, "each piece is manifold")
        self.assertEqual(report["components"], 5)
        self.assertEqual(len(production_checks.component_census(data)), 5,
                         "five watertight tubes are not one connected body")
        self.assertFalse(seams["torso_shoulder"])
        self.assertFalse(seams["pelvis_leg"])
        self.assertTrue(seams["shoulder_upper_arm"])
        self.assertTrue(seams["torso_pelvis"])
        self.assertEqual(seams["intentional_separate"], ())

    def test_opening_the_shoulder_weld_is_caught(self):
        mesh = production.build(wolf(), RIG)
        self.assertTrue(production_checks.flesh_seams(mesh)["torso_shoulder"])
        socket = set(mesh["sockets"]["L"]) | set(mesh["sockets"]["R"])
        arm_start = mesh["pieces"][1][1]

        def weld(face):
            return any(index in socket for index in face) and any(index >= arm_start for index in face)

        opened = dict(mesh, faces=[face for face in mesh["faces"] if not weld(face)])
        self.assertFalse(production_checks.flesh_seams(opened)["torso_shoulder"])


class Topology(unittest.TestCase):
    def test_a_loop_that_shares_no_edge_with_the_surface_is_refused(self):
        body = production._Body()
        for position in ((0, 0, 0), (1, 0, 0), (0, 1, 0), (5, 5, 5), (6, 5, 5), (5, 6, 5)):
            body.vertex(position, (("Hips", 1.0),))
        body.face(0, 1, 2)
        self.assertEqual(body.oriented([2, 1, 0]), [2, 1, 0], "faces run 0->1->2, so the loop runs back")
        self.assertEqual(body.oriented([0, 1, 2]), [2, 1, 0])
        with self.assertRaises(ValueError):
            body.oriented([3, 4, 5])

    def test_sockets_and_leg_loops_match_the_limb_resolution(self):
        mesh = production.build(wolf(), RIG)
        torso = mesh["pieces"][0]
        for side, loop in mesh["sockets"].items():
            self.assertEqual(len(loop), production.AROUND, side)
            self.assertTrue(all(torso[1] <= index < torso[2] for index in loop))
        self.assertEqual(2 * production.SOCKET_HALF_COLS * 2 + 4, production.AROUND, "socket boundary is a limb ring")
        self.assertEqual(production.TORSO_AROUND // 2 + 1 + production.CROTCH_CHAIN, production.AROUND,
                         "half the pelvis opening plus the crotch chain is a limb ring")


class SkinWeights(unittest.TestCase):
    def test_at_most_four_normalized_real_bones(self):
        mesh = production.build(wolf(), RIG)
        self.assertEqual(len(mesh["weights"]), len(mesh["vertices"]))
        for weights in mesh["weights"]:
            self.assertGreaterEqual(len(weights), 1)
            self.assertLessEqual(len(weights), production.INFLUENCE_LIMIT)
            self.assertAlmostEqual(sum(w for _bone, w in weights), 1.0, places=12)
            self.assertTrue(all(w >= production.PRUNE_WEIGHT for _bone, w in weights), weights)
            self.assertLessEqual({bone for bone, _w in weights}, BONES)
        used = {bone for weights in mesh["weights"] for bone, _w in weights}
        self.assertNotIn("Root", used)
        self.assertNotIn("SwordMount", used, "the display-sword mount is never skinned")

    def test_more_than_two_influences_only_at_the_shoulder_and_pelvis(self):
        mesh = production.build(wolf(), RIG)
        blended = [weights for weights in mesh["weights"] if len(weights) > 2]
        self.assertGreater(len(blended), 0, "the shoulder and groin do blend")
        for weights in blended:
            bones = {bone for bone, _w in weights}
            self.assertTrue(any(b.startswith(("UpperArm.", "Shoulder.", "UpperLeg.")) for b in bones), weights)

    def test_normalize_prunes_limits_and_breaks_ties_by_name(self):
        weights = production.normalize_weights(
            [("Chest", 0.3), ("Spine", 0.3), ("UpperArm.L", 0.2), ("Shoulder.L", 0.19), ("Neck", 0.01), ("Hips", 0.2)])
        self.assertEqual([bone for bone, _w in weights], ["Chest", "Spine", "Hips", "UpperArm.L"])
        self.assertAlmostEqual(sum(w for _bone, w in weights), 1.0, places=12)

    def test_every_vertex_carries_a_deformation_region(self):
        mesh = production.build(wolf(), RIG)
        self.assertEqual(len(mesh["regions"]), len(mesh["vertices"]))
        self.assertNotIn("", mesh["regions"])
        for region in ("acromial", "axilla", "pectoral", "latissimus", "trapezius", "deltoid", "deltoid_outer",
                       "pelvis_opening", "glute", "crotch"):
            self.assertIn(region, mesh["regions"])

    def test_the_trapezius_is_chest_and_clavicle_never_the_neck_bone(self):
        mesh = production.build(wolf(), RIG)
        neck_root_x = mesh["landmarks"].neck_root[0]
        for v, region, weights in zip(mesh["vertices"], mesh["regions"], mesh["weights"]):
            if region != "trapezius":
                continue
            self.assertEqual(weights[0][0], "Chest", "the ridge is chest mass")
            if abs(v[0]) >= neck_root_x - 1e-9:
                self.assertNotIn("Neck", dict(weights), "a head turn must not drag the shoulder top")
        torso = mesh["pieces"][0]
        acromion_z = mesh["landmarks"].shoulders["L"].acromion[2]
        chest_front = [mesh["weights"][i] for i in range(torso[1], torso[2])
                       if abs(mesh["vertices"][i][0]) < 0.01 and abs(mesh["vertices"][i][2] - acromion_z) < 1e-9]
        self.assertTrue(chest_front and all(dict(w).get("Chest") == 1.0 for w in chest_front),
                        "the upper chest at the acromion is chest, not neck")

    def test_a_static_chest_shell_socket_is_caught(self):
        mesh = production.build(wolf(), RIG)
        weights = list(mesh["weights"])
        for index in mesh["sockets"]["L"]:
            weights[index] = (("Chest", 1.0),)
        findings = production_checks.shoulder_findings(dict(mesh, weights=weights), mesh["landmarks"])
        self.assertIn("girdle_mapping", findings, "an arm swinging out of a static chest is the reported defect")

    def test_the_socket_rides_clavicle_and_arm_and_the_crotch_rides_both_legs(self):
        mesh = production.build(wolf(), RIG)
        for side, loop in mesh["sockets"].items():
            for index in loop:
                self.assertIn("UpperArm." + side, dict(mesh["weights"][index]))
                self.assertIn("Shoulder." + side, dict(mesh["weights"][index]))
        torso_end = mesh["pieces"][0][2]
        crotch = [w for w in mesh["weights"][torso_end - production.CROTCH_CHAIN:torso_end]]
        for weights in crotch:
            self.assertEqual({bone for bone, _w in weights}, {"Hips", "UpperLeg.L", "UpperLeg.R"})

    def test_elbows_and_knees_have_even_joint_loops(self):
        mesh = production.build(wolf(), RIG)
        for side in ("L", "R"):
            for upper, lower in (("UpperArm", "Forearm"), ("UpperLeg", "LowerLeg")):
                pair = {upper + "." + side, lower + "." + side}
                ring = [w for w in mesh["weights"] if {b for b, _ in w} == pair and abs(w[0][1] - 0.5) < 1e-12]
                self.assertGreaterEqual(len(ring), production.AROUND, "%s.%s loop" % (upper, side))


class Shoulder(unittest.TestCase):
    def test_the_cap_and_the_proximal_arm_share_the_span_and_the_shaft_stays_on_the_bone(self):
        # The shelf was a 17 cm-tall disc whose outer face sat past the arm.
        # The cap is shorter, and its outer face meets the first shaft ring
        # on the span. The shaft past the handoff stays on the bone.
        mesh = production.build(wolf(), RIG)
        span = mesh["landmarks"].sizes["shoulders"]
        arm = next(piece for piece in mesh["pieces"] if piece[0] == "Arm.L")
        cap = arm[1] + production.AROUND
        proximal = cap + production.AROUND
        shaft = proximal + production.AROUND
        n = production.AROUND
        joint = mesh["landmarks"].shoulders["L"].gh_center

        def xs(start):
            return [mesh["vertices"][i][0] for i in range(start, start + n)]

        cap_x, proximal_x = xs(cap), xs(proximal)
        cap_z = [mesh["vertices"][i][2] for i in range(cap, cap + n)]
        self.assertLess(abs(max(cap_x) - max(proximal_x)), 0.02, "outer faces meet")
        self.assertAlmostEqual(max(cap_x), span, delta=1e-6)
        self.assertLess(max(cap_z) - min(cap_z), 0.14, "the cap is shorter than the old 17 cm pad")
        elbow = anatomy.rig_points(RIG)["UpperArm.L"][1]
        cx = sum(xs(shaft)) / n
        self.assertAlmostEqual(cx, joint[0] + (elbow[0] - joint[0]) * 0.62, delta=0.015)
        self.assertEqual(joint, anatomy.rig_points(RIG)["UpperArm.L"][0])

    def test_a_rear_deltoid_that_juts_and_collapses_is_caught(self):
        # The defect seen from behind: the cap centred on the joint reached
        # 4 cm behind the socket and fell 7 cm in one ring.
        mesh = production.build(wolf(), RIG)
        self.assertIsNone(production_checks.depth_contour_finding(mesh))
        arm = next(piece for piece in mesh["pieces"] if piece[0] == "Arm.L")
        jutting = [tuple(v) for v in mesh["vertices"]]
        for index in range(arm[1], arm[1] + production.AROUND):
            x, y, z = jutting[index]
            jutting[index] = (x, y + 0.05 if y > 0.0 else y, z)
        findings = production_checks.shoulder_findings(dict(mesh, vertices=jutting), mesh["landmarks"])
        self.assertIn("depth_contour", findings)
        self.assertIn("back", findings["depth_contour"])

    def test_a_cap_flared_past_the_arm_is_caught(self):
        mesh = production.build(wolf(), RIG)
        arm = next(piece for piece in mesh["pieces"] if piece[0] == "Arm.L")
        cap = arm[1] + production.AROUND
        flared = [tuple(v) for v in mesh["vertices"]]
        for index in range(cap, cap + production.AROUND):
            x, y, z = flared[index]
            flared[index] = (x + 0.05, y, z)
        findings = production_checks.shoulder_findings(dict(mesh, vertices=flared), mesh["landmarks"])
        self.assertIn("outer_contour", findings)

    def test_the_body_passes_every_shoulder_region_check(self):
        mesh = production.build(wolf(), RIG)
        self.assertEqual(production_checks.shoulder_findings(mesh, mesh["landmarks"]), {})

    def test_the_rejected_mesh_fails_the_checks_that_describe_its_defect(self):
        findings = production_checks.shoulder_findings(rejected(), anatomy.derive_anatomy(wolf(), RIG))
        self.assertEqual(set(findings),
                         {"torso_shoulder", "pelvis_leg", "neck_intrusion", "mantle", "socket"}, findings)

    def test_an_arm_pushed_into_the_neck_is_an_intrusion(self):
        mesh = production.build(wolf(), RIG)
        _name, first, end = mesh["pieces"][1]
        pushed = list(mesh["vertices"])
        for index in range(first, first + production.AROUND):
            x, y, z = pushed[index]
            pushed[index] = (0.17, y, z + 0.08)
        findings = production_checks.shoulder_findings(dict(mesh, vertices=pushed), mesh["landmarks"])
        self.assertIn("neck_intrusion", findings)

    def test_a_dropped_mantle_is_caught(self):
        mesh = production.build(wolf(), RIG)
        anatomy = mesh["landmarks"]
        dropped = [(x, y, min(z, anatomy.shoulders["L"].gh_center[2])) if 1.3 < z < 1.5 else (x, y, z)
                   for x, y, z in mesh["vertices"]]
        self.assertIn("mantle", production_checks.shoulder_findings(dict(mesh, vertices=dropped), anatomy))


class Pelvis(unittest.TestCase):
    def test_the_glutes_cover_the_thigh_tops_and_the_hip_has_one_outer_face(self):
        mesh = production.build(wolf(), RIG)
        self.assertEqual(production_checks.pelvis_findings(mesh, production.TORSO_AROUND), {})
        glute = mesh["landmarks"].pelvis["L"].glute
        seat = max(v[1] for v in mesh["vertices"][:3 * production.TORSO_AROUND])
        self.assertGreater(seat, glute[1], "the seat sits behind the glute landmark")

    def test_a_flat_seat_is_caught(self):
        # The pre-glute body: plain ellipses, the rear thigh 2 cm behind them.
        mesh = production.build(wolf(), RIG)
        n = production.TORSO_AROUND
        flat = [tuple(v) for v in mesh["vertices"]]
        for index in range(3 * n):
            x, y, z = flat[index]
            if y > 0.0:
                flat[index] = (x, min(y, 0.119), z)
        findings = production_checks.pelvis_findings(dict(mesh, vertices=flat), n)
        self.assertIn("seat", findings)

    def test_a_thigh_stepped_in_from_the_hip_is_caught(self):
        mesh = production.build(wolf(), RIG)
        leg = next(piece for piece in mesh["pieces"] if piece[0] == "Leg.L")
        stepped = [tuple(v) for v in mesh["vertices"]]
        for index in range(leg[1], leg[1] + production.AROUND):
            x, y, z = stepped[index]
            stepped[index] = (x - 0.04, y, z)
        findings = production_checks.pelvis_findings(dict(mesh, vertices=stepped), production.TORSO_AROUND)
        self.assertIn("hip_outer", findings)

    def test_a_thigh_stepped_away_from_the_pelvis_is_a_ledge(self):
        # The pre-flow lead thigh: its first ring's back 10.8 cm in front of
        # the glute, a shelf under the seat.
        mesh = production.build(wolf(), RIG)
        self.assertNotIn("hip_ledge", production_checks.pelvis_findings(mesh, production.TORSO_AROUND))
        leg = next(piece for piece in mesh["pieces"] if piece[0] == "Leg.R")
        shelved = [tuple(v) for v in mesh["vertices"]]
        ring = range(leg[1], leg[1] + production.AROUND)
        back = max(shelved[i][1] for i in ring)
        for index in ring:
            x, y, z = shelved[index]
            shelved[index] = (x, y - 0.08 if y > back - 0.05 else y, z)
        findings = production_checks.pelvis_findings(dict(mesh, vertices=shelved), production.TORSO_AROUND)
        self.assertIn("hip_ledge", findings)
        self.assertIn("Leg.R back", findings["hip_ledge"])

    def test_the_rejected_loft_has_no_welded_pelvis(self):
        self.assertIn("seat", production_checks.pelvis_findings(rejected(), production.TORSO_AROUND))


class WolfGeometry(unittest.TestCase):
    def test_crown_feet_and_stance_follow_wolfrig(self):
        mesh = production.build(wolf(), RIG)
        points = anatomy.rig_points(RIG)
        zs = [v[2] for v in mesh["vertices"]]
        self.assertAlmostEqual(max(zs), points["Head"][1][2], places=12)
        self.assertAlmostEqual(max(zs), baseline.REFERENCE_HEIGHT_M, places=12)
        self.assertGreaterEqual(min(zs), 0.0)
        self.assertLess(min(zs), 0.03, "soles on the floor")
        legs = {name: (first, end) for name, first, end in mesh["pieces"]}
        lead = min(mesh["vertices"][i][1] for i in range(*legs["Leg.R"]))
        rear = min(mesh["vertices"][i][1] for i in range(*legs["Leg.L"]))
        self.assertLess(lead, rear, "the right foot leads (forward is -Y)")

    def test_the_rig_joints_are_never_moved(self):
        mesh = production.build(wolf(), RIG)
        points = anatomy.rig_points(RIG)
        for side in ("L", "R"):
            self.assertEqual(mesh["landmarks"].shoulders[side].gh_center, points["UpperArm." + side][0])
            self.assertEqual(mesh["landmarks"].pelvis[side].hip, points["UpperLeg." + side][0])


if __name__ == "__main__":
    unittest.main()
