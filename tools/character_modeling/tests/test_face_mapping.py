"""TEST-TRUTH: facial mapping (FACE-MAPPING-001) — the face surface chart, semantic
landmarks and attachments. Each test states its fixture (ARRANGE), the defect or change
it adds (PERTURB), the production call (ACT), and the contract (ASSERT). The fixture is a
synthetic convex mask: an ellipsoidal front, a wedge nose on the centre line, cheekbone
convexity, sampled the way the Blender adapter samples a head."""

from __future__ import annotations

import math
import unittest

from character_modeling import face_mapping

FRAME = {"low": 1.522, "height": 0.2765, "half_width": 0.1084}
IDENTITY = {"Eye": {"x": 0.335, "z": 0.536, "width": 0.36}, "Brow": {"x": 0.33, "z": 0.645, "width": 0.4}}


def mask_depth(x, z, nose=0.02, cheek=0.004):
    """y of the synthetic mask at (x, z): forward is -y."""
    ex, ez = x / 0.125, (z - 1.66) / 0.17
    y = -0.12 * math.sqrt(max(0.0, 1.0 - ex * ex - ez * ez))
    if 1.6 < z < 1.69:
        rise = nose * (1.69 - z) / 0.07 if z > 1.62 else nose * (z - 1.6) / 0.02
        y -= max(0.0, rise * (1.0 - abs(x) / 0.016))
    y -= cheek * math.exp(-0.5 * (((abs(x) - 0.065) / 0.012) ** 2 + ((z - 1.635) / 0.01) ** 2))
    if 1.535 < z < 1.56:
        y -= 0.004 * (1.0 - abs(x) / 0.03) if abs(x) < 0.03 else 0.0
    return y


def surface_data(steps=81, depth=mask_depth, frame=FRAME):
    us = [-0.95 + 1.9 * i / (steps - 1) for i in range(steps)]
    vs = [0.02 + 0.93 * j / (steps - 1) for j in range(steps)]
    positions, normals = [], []
    for v in vs:
        row_p, row_n = [], []
        for u in us:
            x, z = u * frame["half_width"], frame["low"] + v * frame["height"]
            h = 1e-4
            dy_dx = (depth(x + h, z) - depth(x - h, z)) / (2 * h)
            dy_dz = (depth(x, z + h) - depth(x, z - h)) / (2 * h)
            n = (dy_dx, -1.0, dy_dz)
            length = math.sqrt(sum(c * c for c in n))
            row_p.append((x, depth(x, z), z))
            row_n.append(tuple(c / length for c in n))
        positions.append(row_p)
        normals.append(row_n)
    return {"schema": face_mapping.SCHEMA, "u": us, "v": vs, "positions": positions, "normals": normals, "frame": frame}


class Chart(unittest.TestCase):
    def test_the_surface_refuses_another_schema_and_a_ragged_grid(self):
        ## ARRANGE
        good = surface_data(steps=9)
        ## PERTURB
        wrong = dict(good, schema="riposte.other")
        ragged = dict(good, positions=good["positions"][:-1])
        ## ACT / ASSERT
        face_mapping.FaceSurface(good)
        with self.assertRaises(ValueError):
            face_mapping.FaceSurface(wrong)
        with self.assertRaises(ValueError):
            face_mapping.FaceSurface(ragged)

    def test_tangents_are_orthonormal_to_the_normal_and_the_mask_is_convex(self):
        ## ARRANGE
        surface = face_mapping.FaceSurface(surface_data())
        ## ACT
        tu, tv = surface.tangents(0.3, 0.7)
        n = surface.normal(0.3, 0.7)
        ku, kv = surface.curvature(0.3, 0.7)
        ## ASSERT: unit, mutually orthogonal, horizontal toward +u, vertical upward, convex.
        for a in (tu, tv, n):
            self.assertAlmostEqual(math.sqrt(sum(c * c for c in a)), 1.0, places=6)
        self.assertAlmostEqual(sum(a * b for a, b in zip(tu, tv)), 0.0, places=6)
        self.assertAlmostEqual(sum(a * b for a, b in zip(tu, n)), 0.0, places=6)
        self.assertGreater(tu[0], 0.0)
        self.assertGreater(tv[2], 0.0)
        self.assertGreater(ku, 0.0)
        self.assertGreater(kv, 0.0)

    def test_a_point_outside_the_sampled_chart_is_refused(self):
        ## ARRANGE
        surface = face_mapping.FaceSurface(surface_data(steps=9))
        ## PERTURB / ACT / ASSERT
        with self.assertRaises(ValueError):
            surface.position(1.2, 0.5)


class Landmarks(unittest.TestCase):
    def test_the_geometric_landmarks_land_on_the_designed_features(self):
        ## ARRANGE
        surface = face_mapping.FaceSurface(surface_data())
        ## ACT
        marks = face_mapping.derive_landmarks(surface, IDENTITY)
        ## ASSERT: the tip is the forward-most point at the nose's peak, the chin below it,
        ## the cheekbone at the convexity, every landmark present and mirrored.
        tip_z = FRAME["low"] + marks["nose_tip"][1] * FRAME["height"]
        self.assertAlmostEqual(tip_z, 1.62, delta=0.006)
        self.assertLess(marks["chin_apex"][1], marks["nose_tip"][1])
        cheek_x = marks["cheekbone_apex.L"][0] * FRAME["half_width"]
        self.assertAlmostEqual(cheek_x, 0.065, delta=0.01)
        self.assertGreater(marks["nose_lateral.L"][0] * FRAME["half_width"], 0.004)
        self.assertEqual(face_mapping.landmark_problems(marks), [])

    def test_an_unmirrored_or_missing_landmark_is_hard(self):
        ## ARRANGE
        marks = face_mapping.derive_landmarks(face_mapping.FaceSurface(surface_data()), IDENTITY)
        ## PERTURB
        marks["eye_centre.R"] = (marks["eye_centre.R"][0] - 0.02, marks["eye_centre.R"][1])
        del marks["temple.L"]
        marks["nose_tip"] = (0.01, marks["nose_tip"][1])
        ## ACT
        problems = face_mapping.landmark_problems(marks)
        ## ASSERT
        found = {(p["landmark"], p["message"]) for p in problems}
        self.assertIn(("eye_centre", "left and right are not mirrored"), found)
        self.assertIn(("temple.L", "missing"), found)
        self.assertIn(("nose_tip", "off the centre line"), found)


class Attachments(unittest.TestCase):
    BROW = {"landmark": "brow_apex.L", "region": "brow_surface", "tangent_offset_m": (0.002, 0.0),
            "normal_offset_m": 0.0015, "orientation": "follow_surface"}

    def test_a_component_follows_the_surface_not_a_vertex(self):
        ## ARRANGE: the same mask sampled at two resolutions (two topologies)
        coarse = face_mapping.FaceSurface(surface_data(steps=61))
        fine = face_mapping.FaceSurface(surface_data(steps=121))
        ## ACT
        a = face_mapping.resolve(coarse, face_mapping.derive_landmarks(coarse, IDENTITY), self.BROW)
        b = face_mapping.resolve(fine, face_mapping.derive_landmarks(fine, IDENTITY), self.BROW)
        ## ASSERT: the frame is the same component on the same surface, offset outward
        gap = math.dist(a["origin"], b["origin"])
        self.assertLess(gap, 0.0005)
        surface_point = coarse.position(*a["uv"])
        lift = sum((o - s) * n for o, s, n in zip(a["origin"], surface_point, a["normal"]))
        self.assertAlmostEqual(lift, 0.0015, places=6)

    def test_a_component_moves_with_a_different_head(self):
        ## ARRANGE: Wolf's brow on the reference mask
        reference = face_mapping.FaceSurface(surface_data())
        ## PERTURB: a broader brow ridge (another head profile)
        heavy = face_mapping.FaceSurface(surface_data(depth=lambda x, z: mask_depth(x, z) - 0.004 * math.exp(-0.5 * ((z - 1.70) / 0.01) ** 2)))
        ## ACT
        a = face_mapping.resolve(reference, face_mapping.derive_landmarks(reference, IDENTITY), self.BROW)
        b = face_mapping.resolve(heavy, face_mapping.derive_landmarks(heavy, IDENTITY), self.BROW)
        ## ASSERT: same place on the chart, carried forward onto the new surface
        self.assertAlmostEqual(a["uv"][0], b["uv"][0], places=3)
        self.assertLess(b["origin"][1], a["origin"][1] - 0.001)

    def test_outside_its_region_buried_or_unmirrored_is_hard(self):
        ## ARRANGE
        surface = face_mapping.FaceSurface(surface_data())
        marks = face_mapping.derive_landmarks(surface, IDENTITY)
        right = dict(self.BROW, landmark="brow_apex.R")
        ## PERTURB
        attachments = {
            "Brow.L": dict(self.BROW, tangent_offset_m=(0.0, 0.0)),
            "Brow.R": dict(right, tangent_offset_m=(0.0, 0.004)),
            "Eye.L": {"landmark": "eye_centre.L", "region": "eye_opening", "normal_offset_m": -0.002},
            "Cheek.L": {"landmark": "cheekbone_apex.L", "region": "eye_opening"},
            "Lid.L": {"landmark": "eye_centre.L", "orientation": "billboard"},
            "Gone.L": {"landmark": "eyelash.L"},
        }
        ## ACT
        problems, frames = face_mapping.attachment_problems(surface, marks, attachments)
        ## ASSERT
        text = {(p["component"], p["message"].split(" ")[0]) for p in problems}
        self.assertIn(("Eye.L", "buried"), text)
        self.assertIn(("Cheek.L", "outside"), text)
        self.assertIn(("Brow", "pair"), text)
        self.assertIn(("Lid.L", "unknown"), text)
        self.assertIn(("Gone.L", "landmark"), text)
        self.assertIn("Brow.L", frames)

    def test_a_clean_mirrored_set_raises_nothing(self):
        ## ARRANGE
        surface = face_mapping.FaceSurface(surface_data())
        marks = face_mapping.derive_landmarks(surface, IDENTITY)
        attachments = {"Brow.L": self.BROW, "Brow.R": dict(self.BROW, landmark="brow_apex.R"),
                       "Eye.L": {"landmark": "eye_centre.L", "region": "eye_opening", "normal_offset_m": 0.001},
                       "Eye.R": {"landmark": "eye_centre.R", "region": "eye_opening", "normal_offset_m": 0.001}}
        ## PERTURB: none
        ## ACT
        problems, _frames = face_mapping.attachment_problems(surface, marks, attachments)
        ## ASSERT
        self.assertEqual(problems, [])


if __name__ == "__main__":
    unittest.main()
