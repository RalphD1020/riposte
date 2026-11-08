"""TEST-TRUTH: the heroic paneled mask (FACE-IDENTITY-001) as its own topology. Fixture:
the composition in the head's chart, and a flat construction surface where depth = lift
(ARRANGE); perturbation: head parameters (PERTURB); the production calls
`face_mask.panels`, `boundary_loop`, `refined`, `control_points` (ACT); contracts
(ASSERT): the panels tile the designed full-face boundary exactly once as one disc and
mirror; the boundary reaches the hairline, the temples, the sides, the jaw and under the
chin; the brow ridge is one line flowing into the rectangular bridge; brow over shelf over
eye (the hood); the nose peak is the forward point; the cheekbone is where five regions
meet; the lower face stays broad; refinement shares every panel edge; the architecture
parameters move the named vertices."""

from __future__ import annotations

import json
import math
import unittest
from pathlib import Path

from character_modeling import face_mask

MANIFEST = Path(__file__).resolve().parents[3] / "art-src" / "blender" / "characters" / "wolf" / "wolf.assembly.json"
## The default head's construction chart: height over half-width (0.2765 / 0.1084 m).
WOLF_ASPECT = 0.2765 / 0.1084


def wolf_marks():
    return json.loads(MANIFEST.read_text(encoding="utf-8"))["identity"]["face"]["marks"]


def chart_area(points):
    return 0.5 * sum(points[i][0] * points[(i + 1) % len(points)][1] - points[(i + 1) % len(points)][0] * points[i][1]
                     for i in range(len(points)))


class Topology(unittest.TestCase):
    def test_the_panels_tile_the_boundary_once_as_a_disc(self):
        controls = face_mask.control_points()
        panels = face_mask.panels()
        loop = face_mask.boundary_loop()
        areas = [chart_area([controls[n][:2] for n in corners]) for _r, corners in panels]
        self.assertTrue(all(a > 1e-4 for a in areas), "every panel wound and non-degenerate")
        outline = abs(chart_area([controls[n][:2] for n in loop]))
        self.assertAlmostEqual(sum(areas), outline, places=9)
        uses = {}
        for _r, (a, b, c) in panels:
            for edge in ((a, b), (b, c), (c, a)):
                uses[tuple(sorted(edge))] = uses.get(tuple(sorted(edge)), 0) + 1
        border = {tuple(sorted((loop[i], loop[(i + 1) % len(loop)]))) for i in range(len(loop))}
        self.assertEqual({e for e, k in uses.items() if k == 1}, border)
        self.assertTrue(all(k in (1, 2) for k in uses.values()))
        used = {n for _r, corners in panels for n in corners}
        self.assertEqual(used, set(controls))
        self.assertEqual(len(used) - len(uses) + len(panels), 1, "Euler characteristic of a disc")

    def test_the_composition_mirrors(self):
        panels = {(r, frozenset(c)) for r, c in face_mask.panels()}
        for region, corners in panels:
            self.assertIn((region, frozenset(face_mask.mirrored(n) for n in corners)), panels)


class FullFace(unittest.TestCase):
    def test_the_boundary_is_the_whole_face_on_the_skull(self):
        controls = face_mask.control_points()
        loop = face_mask.boundary_loop()
        self.assertGreaterEqual(controls["hairline"][1], 0.88)
        self.assertLessEqual(min(controls[n][1] for n in loop), 0.04)
        self.assertGreaterEqual(max(controls[n][0] for n in loop), 0.85)
        sides = [controls[n] for n in loop if controls[n][0] > 0.85]
        self.assertTrue(any(0.45 <= p[1] <= 0.7 for p in sides), "wraps into the temples and the side plane")
        for name in loop:
            self.assertEqual(controls[name][2:], (0.0, 1.0), name)
        ## The upper architecture is planar geometry (follow 0); the lower mask is the
        ## construction surface itself (the original panel mask: lift 0, follow 1).
        for name in ("bridge_root", "bridge_top", "bridge_bottom", "nose_peak", "brow_inner", "brow_mid", "brow_outer",
                     "shelf_inner", "shelf_mid", "shelf_outer", "eye_inner", "eye_low", "eye_outer", "cheekbone",
                     "nose_side"):
            self.assertEqual(controls[name][3], 0.0, name)
        self.assertGreater(controls["cheekbone"][2], controls["eye_low"][2], "the cheekbone rises out of the eye")

    def test_a_continuous_perimeter_ring_turns_the_field_into_the_head(self):
        ## The original mask reads as a mask through one continuous turn around the face.
        controls = face_mask.control_points()
        names = set(face_mask.edges())
        ring = face_mask.RING
        for a, b in zip(ring, ring[1:]):
            self.assertIn(tuple(sorted((a, b))), names, (a, b))
        self.assertGreater(controls[ring[0]][1], controls["forehead"][1] + 0.03, "from above the forehead plate")
        self.assertGreater(controls["hairline"][1] - controls[ring[0]][1], 0.07, "a forehead band wide enough to blend")
        self.assertLessEqual(controls[ring[-1]][1], 0.1, "to the chin")
        self.assertEqual(controls[ring[0]][0], 0.0)
        self.assertEqual(controls[ring[-1]][0], 0.0)
        ## The ring is planar except where it passes the brow's tail (the brow is kept as is).
        for name in set(ring) - {"brow_tail"}:
            self.assertEqual(controls[name][3], 0.0, name)
        ## Outside the ring only the perimeter band, which ends on the boundary.
        band = [c for r, c in face_mask.PANELS if r == "perimeter"]
        loop = set(face_mask.BOUNDARY)
        self.assertTrue(all(any(n in loop for n in c) for c in band))
        ## The lower field is broad and quiet: planar, a few mm proud, under the features.
        lower = {n for r, c in face_mask.PANELS if r == "lower_mask" for n in c} - set(ring)
        for name in lower - {"nose_base", "nose_wing"}:
            self.assertEqual(controls[name][3], 0.0, name)
            self.assertLess(controls[name][2], controls["cheekbone"][2], name)

class Architecture(unittest.TestCase):
    def test_the_brow_ridge_flows_into_a_rectangular_bridge(self):
        names = set(face_mask.edges())
        ridge = ("bridge_top", "brow_inner", "brow_mid", "brow_outer", "brow_tail")
        for a, b in zip(ridge, ridge[1:]):
            self.assertIn(tuple(sorted((a, b))), names)
        top, bottom = face_mask.BRIDGE
        ## The front: four corners around the root (top centre) and the peak (bottom centre).
        for edge in ((top, bottom), (top, "bridge_root"), (bottom, "nose_peak"), ("bridge_root", "nose_peak"),
                     (top + ".R", bottom + ".R"), (top + ".R", "bridge_root"), (bottom + ".R", "nose_peak")):
            self.assertIn(tuple(sorted(edge)), names)
        front = [c for r, c in face_mask.panels() if r == "bridge" and "bridge_root" in c]
        self.assertEqual(len(front), 4)
        controls = face_mask.control_points()
        self.assertGreaterEqual(2 * controls[bottom][0], 0.15, "a broad bridge, not a thin ridge")
        self.assertLess(abs(controls[top][0] - controls[bottom][0]), 0.03, "rectangular: near-parallel sides")
        self.assertIn(tuple(sorted(("nose_peak", bottom))), names)
        self.assertIn(tuple(sorted(("nose_peak", "nose_base"))), names)

    def test_face_integration_moves_depth_and_follow_never_the_locked_features_anchors(self):
        ## ARRANGE: the foundation's mask study without and with face_integration.
        base = {"anime_face": 1.0, "ridge_straight": 0.8, "ridge_angle": 0.5, "edge_softness": -0.4, "anime_nose": 1.0}
        before = face_mask.control_points(base)
        ## ACT
        after = face_mask.control_points(dict(base, face_integration=1.0))
        ## ASSERT: no control vertex moves in the chart except the nose wings and base; the
        ## brow ridge, shelf and temple ring the locked brow lies on do not move at all.
        moved_chart = {n for n in before if before[n][:2] != after[n][:2]}
        self.assertEqual({n.replace(".R", "") for n in moved_chart}, {"nose_wing", "nose_base"})
        for line in face_mask.ANCHORS.values():
            for names in line:
                for n in names:
                    self.assertEqual(before[n][:2], after[n][:2], n)
        for n in ("brow_inner", "brow_mid", "brow_outer", "brow_tail", "shelf_inner", "shelf_mid", "shelf_outer",
                  "ring_temple", "bridge_top", "bridge_root"):
            self.assertEqual(before[n], after[n], n)
        ## The orbit is shallower but still hooded, the forehead ring follows the skull, the
        ## nose tip is still the face's forward point and projects no less.
        lift = {n: p[2] for n, p in after.items()}
        for shelf, eye in (("shelf_inner", "eye_inner"), ("shelf_mid", "eye_low"), ("shelf_outer", "eye_outer")):
            self.assertGreater(lift[eye], before[eye][2])
            self.assertGreater(lift[shelf], lift[eye])
        self.assertAlmostEqual(after["ring_forehead"][3], 0.6)
        self.assertEqual(max(lift, key=lift.get), "nose_peak")
        self.assertGreaterEqual(lift["nose_peak"], before["nose_peak"][2])
        ## PERTURB: a follow delta past 1 clamps (follow is a 0..1 share).
        self.assertEqual(face_mask.control_points(dict(base, face_integration=3.0))["ring_forehead"][3], 1.0)

    def test_the_brow_hoods_the_eye_and_the_nose_is_the_peak(self):
        lift = {n: p[2] for n, p in face_mask.control_points().items()}
        for brow, shelf, eye in (("brow_inner", "shelf_inner", "eye_inner"), ("brow_mid", "shelf_mid", "eye_low"),
                                 ("brow_outer", "shelf_outer", "eye_outer")):
            self.assertGreater(lift[brow], lift[shelf])
            self.assertGreater(lift[shelf], lift[eye])
        self.assertEqual(max(lift, key=lift.get), "nose_peak")
        self.assertGreater(lift["nose_peak"], lift["brow_inner"])
        self.assertGreater(lift["cheekbone"], lift["eye_outer"])

    def test_the_eye_landmarks_lie_in_the_eye_panels(self):
        controls = face_mask.control_points()
        eye = [c for r, c in face_mask.panels() if r == "eye"]

        def inside(p, corners):
            pts = [controls[n][:2] for n in corners]
            signs = [(pts[(i + 1) % 3][0] - pts[i][0]) * (p[1] - pts[i][1]) - (pts[(i + 1) % 3][1] - pts[i][1]) * (p[0] - pts[i][0])
                     for i in range(3)]
            return all(s >= 0 for s in signs)

        ## Wolf's eye mark (centre and corners, resolved from wolf.assembly.json) sits on the panels.
        mark = face_mask.resolve_mark(wolf_marks()["Eye"], WOLF_ASPECT)
        half = mark["width"] / 2.0
        for point in ((mark["x"], mark["z"]), (mark["x"] - half, mark["z"]), (mark["x"] + half, mark["z"])):
            self.assertTrue(any(inside(point, c) for c in eye), point)

    def test_the_cheekbone_is_a_convergence_vertex_and_the_lower_face_is_broad(self):
        meeting = {r for r, corners in face_mask.PANELS if "cheekbone" in corners}
        self.assertLessEqual({"eye", "shelf", "nose_side", "cheek", "temple"}, meeting)
        controls = face_mask.control_points()
        cheek_v = controls["cheekbone"][1]
        below = [c for _r, c in face_mask.PANELS if max(controls[n][1] for n in c) <= cheek_v]
        above = [c for _r, c in face_mask.PANELS if min(controls[n][1] for n in c) >= cheek_v]
        self.assertLess(len(below), len(above))


class SoftEdges(unittest.TestCase):
    """The bridge and the brow ridge are softened, semi-angular edges, on both sides."""

    def test_the_soft_points_are_the_bridge_and_ridge_edges_on_both_sides(self):
        ## ARRANGE
        points, _triangles = face_mask.refined()
        ## ACT
        keys = face_mask.soft_keys(points)
        ## ASSERT: every soft edge's REFINE + 1 points on each side, nothing else.
        names = {name for key in keys for name, _k in key}
        self.assertEqual(names, {n for e in face_mask.soft_edges() for n in e})
        for a, b in face_mask.soft_edges():
            on = [k for k in keys if {n for n, _k in k} <= {a, b}]
            self.assertEqual(len(on), face_mask.REFINE + 1, (a, b))
        self.assertIn((("bridge_top.R", face_mask.REFINE),), keys)

    def test_the_lower_contour_edges_are_the_chin_and_border_never_the_brow_or_boundary(self):
        ## ARRANGE: the refined mask and its boundary loop.
        points, _triangles = face_mask.refined()
        boundary_edges = {frozenset(e) for e in zip(face_mask.BOUNDARY, face_mask.BOUNDARY[1:])}
        ## ACT
        lower = face_mask.soft_keys(points, face_mask.LOWER_SOFT_EDGES)
        ## ASSERT: the chin's point and the border's corners round; no brow or bridge point,
        ## and no edge of the boundary loop (the seam to the skull is held).
        self.assertIn((("chin", face_mask.REFINE),), lower)
        self.assertIn((("chin_ring.R", face_mask.REFINE),), lower)
        self.assertFalse(lower & face_mask.soft_keys(points))
        self.assertFalse({frozenset(e) for e in face_mask.LOWER_SOFT_EDGES} & boundary_edges)
        ## PERTURB: a named amount and pass count override the study's.
        tri = [("t", ((("a", 0),), (("b", 0),), (("c", 0),)))]
        start = {(("a", 0),): (0.0, 0.0, 1.0), (("b", 0),): (1.0, 0.0, 0.0), (("c", 0),): (0.0, 1.0, 0.0)}
        moved = face_mask.soften(start, tri, {(("a", 0),)}, amount=0.5, passes=1)
        self.assertAlmostEqual(moved[(("a", 0),)][2], 0.5)

    def test_soften_rounds_a_crest_without_flattening_it_and_keeps_fixed_points(self):
        ## ARRANGE: a strip folded 90 degrees along its middle row (the crest).
        rows, columns = 5, 4
        key = lambda r, c: ((str(r), c),)
        positions = {key(r, c): (float(c), 0.0, float(r)) if r <= 2 else (float(c), float(r - 2), 2.0)
                     for r in range(rows) for c in range(columns)}
        triangles = []
        for r in range(rows - 1):
            for c in range(columns - 1):
                triangles.append(("strip", (key(r, c), key(r, c + 1), key(r + 1, c))))
                triangles.append(("strip", (key(r, c + 1), key(r + 1, c + 1), key(r + 1, c))))
        crest = {key(2, c) for c in range(columns)}
        fixed = {key(2, 0)}

        def angle(p):
            a, b, c = p[key(1, 1)], p[key(2, 1)], p[key(3, 1)]
            u = [a[i] - b[i] for i in range(3)]
            v = [c[i] - b[i] for i in range(3)]
            dot = sum(x * y for x, y in zip(u, v))
            return math.degrees(math.acos(dot / math.sqrt(sum(x * x for x in u) * sum(y * y for y in v))))
        self.assertAlmostEqual(angle(positions), 90.0, places=9)
        ## ACT
        soft = face_mask.soften(positions, triangles, crest, fixed)
        ## ASSERT: the crest opens (rounded) but still turns (semi-angular); fixed stays.
        self.assertGreater(angle(soft), 100.0)
        self.assertLess(angle(soft), 160.0)
        self.assertEqual(soft[key(2, 0)], positions[key(2, 0)])
        self.assertNotEqual(soft[key(2, 1)], positions[key(2, 1)])
        self.assertEqual(soft[key(0, 1)], positions[key(0, 1)], "two rows away from the crest never moves")


class MarkAnchors(unittest.TestCase):
    """FACE-MAPPING-001: identity marks sit on the mask's own features. An eye's whole outline
    lies inside the recessed eye panel; a brow is attached by its bottom contour on the
    ridge's crest at every column, its top contour its own design; the approved asymmetry,
    the brow-eye separation and the bridge's clearance hold in every expression study."""

    @staticmethod
    def line_v(names, u):
        """The oracle: a control line's height at |u| (piecewise linear, level past its ends)."""
        points = [face_mask.control_points()[n][:2] for n in names]
        u = abs(u)
        if u <= points[0][0]:
            return points[0][1]
        for (u0, v0), (u1, v1) in zip(points, points[1:]):
            if u <= u1:
                return v0 + (v1 - v0) * (u - u0) / (u1 - u0)
        return points[-1][1]

    def test_the_eye_is_centred_in_the_recess_and_its_aperture_inside_it(self):
        ## ARRANGE: Wolf's eye; the recess's top (shelf) and bottom (eye panel) lines.
        top, bottom = face_mask.ANCHORS["eye_recess"]
        ## ACT
        mark = face_mask.resolve_mark(wolf_marks()["Eye"], WOLF_ASPECT)
        ## ASSERT: centred at the recess's mid-height, both lid margins inside it.
        self.assertAlmostEqual(mark["z"], 0.5 * (self.line_v(top, mark["x"]) + self.line_v(bottom, mark["x"])), places=9)
        for x, y in mark["upper"] + mark["lower"]:
            u, v = mark["x"] + x * mark["width"], mark["z"] + y * mark["height"]
            self.assertTrue(self.line_v(bottom, u) < v < self.line_v(top, u), (x, y, u, v))

    def test_the_brow_bottom_contour_rides_the_crest_at_every_column(self):
        ## ARRANGE: Wolf's brow; the crest line.
        (crest,) = face_mask.ANCHORS["brow_ridge"]
        brow = wolf_marks()["Brow"]
        controls = face_mask.control_points()
        self.assertEqual(brow["inner"], face_mask.RIDGE_START, "fixture: Wolf's brow starts where the ridge meets the nose")
        ## ACT
        mark = face_mask.resolve_mark(brow, WOLF_ASPECT)
        ## ASSERT: the span runs from the ridge's start (the bridge's top corner) to the
        ## authored outer end, and a column sits on every bend of the ridge inside it.
        self.assertAlmostEqual(mark["x"] - mark["width"] / 2.0, controls["bridge_top"][0], places=12)
        self.assertAlmostEqual(mark["x"] + mark["width"] / 2.0, brow["x"] + brow["width"] / 2.0, places=12)
        us = [r[1] for r in mark["columns"]["L"]]
        for bend in ("brow_inner", "brow_mid"):
            self.assertIn(round(controls[bend][0], 12), [round(u, 12) for u in us])
        self.assertEqual(us, sorted(us))
        ## ASSERT: per side, each column's bottom is the crest at its u (the neutral brow sits
        ## on the ridge); its top is the profile's thickness above it, turned by that side's tilt.
        for side, rows in mark["columns"].items():
            turn = math.tan(math.radians(brow["tilt_deg"] + brow["tilt_by_side"][side]))
            self.assertGreaterEqual(len(rows), face_mask.COLUMNS)
            for t, u, bottom, top, anchor in rows:
                self.assertAlmostEqual(anchor, self.line_v(crest, u), places=9)
                self.assertAlmostEqual(u, mark["x"] + t * mark["width"], places=12)
                self.assertAlmostEqual(bottom, self.line_v(crest, u) + brow["lift"], places=9)
                self.assertAlmostEqual(top - bottom, face_mask._interpolate(brow["profile"], t) * brow["height"]
                                       + turn * t * mark["width"] / WOLF_ASPECT, places=9)
                self.assertGreater(top, bottom)
        ## The design: a natural brow, a full head at the bridge, the arch its thickest, the
        ## tail tapered under a third of the arch.
        rows = mark["columns"]["L"]
        thickness = [r[3] - r[2] for r in rows]
        arch = max(range(len(rows)), key=lambda i: thickness[i])
        self.assertTrue(0.0 < rows[arch][0] < 0.4, rows[arch][0])
        self.assertGreater(thickness[0], 0.5 * thickness[arch])
        self.assertLess(thickness[-1], thickness[arch] / 3.0)

    def test_the_approved_asymmetry_survives_and_is_the_only_left_right_difference(self):
        ## ARRANGE
        brow = wolf_marks()["Brow"]
        ## PERTURB: no asymmetry.
        even = dict(brow, tilt_by_side={"L": 0.0, "R": 0.0})
        ## ACT
        mark, level = face_mask.resolve_mark(brow, WOLF_ASPECT), face_mask.resolve_mark(even, WOLF_ASPECT)
        ## ASSERT: the sides' top contours differ at their ends (by the 4 degree spread),
        ## never at the centre, and their bottoms never (both on the ridge); without the
        ## asymmetry they are mirror images.
        left, right = mark["columns"]["L"], mark["columns"]["R"]
        centre = min(range(len(left)), key=lambda i: abs(left[i][0]))
        self.assertAlmostEqual(left[centre][0], 0.0, places=12)
        self.assertAlmostEqual(left[centre][3], right[centre][3], places=12)
        self.assertGreater(left[-1][3] - right[-1][3], 0.0)
        self.assertEqual([r[2] for r in left], [r[2] for r in right])
        self.assertEqual(level["columns"]["L"], level["columns"]["R"])

    def test_neutral_brows_clear_the_bridge_and_the_eyes(self):
        ## ARRANGE
        controls = face_mask.control_points()
        ## ACT
        brow = face_mask.resolve_mark(wolf_marks()["Brow"], WOLF_ASPECT)
        eye = face_mask.resolve_mark(wolf_marks()["Eye"], WOLF_ASPECT)
        ## ASSERT: never on the bridge's front (it starts at the bridge's top corner, where
        ## the ridge meets the nose); the lowest brow point above the eye's upper lid.
        eye_top = eye["z"] + max(y for _x, y in eye["upper"]) * eye["height"]
        for rows in brow["columns"].values():
            self.assertGreaterEqual(rows[0][1], controls["bridge_top"][0] - 1e-12)
            self.assertGreater(min(r[2] for r in rows), eye_top)

    def test_the_anime_face_study_narrows_the_nose_to_a_pointed_wedge(self):
        ## ARRANGE: the approved mask and the anime-face study.
        approved = face_mask.control_points()
        ## PERTURB
        anime = face_mask.control_points({"anime_face": 1.0})
        ## ACT / ASSERT: the bridge about half as wide, its front lower; the tip stands forward
        ## of the bridge's bottom corners (a pointed wedge, not a block); the brow lower; the
        ## eye panel larger; the boundary never moves.
        self.assertLess(anime["bridge_top"][0], 0.6 * approved["bridge_top"][0])
        self.assertLess(anime["bridge_bottom"][0], 0.5 * approved["bridge_bottom"][0])
        self.assertGreater(anime["nose_peak"][2] - anime["bridge_bottom"][2], approved["nose_peak"][2] - approved["bridge_bottom"][2])
        self.assertLess(anime["brow_mid"][2], approved["brow_mid"][2])
        self.assertLess(anime["eye_low"][1], approved["eye_low"][1])
        self.assertGreater(anime["shelf_mid"][1], approved["shelf_mid"][1])
        for name in face_mask.BOUNDARY:
            self.assertEqual(anime[name], approved[name])

    def test_the_ridge_studies_are_zero_on_the_approved_mask(self):
        ## ARRANGE: the approved mask (no parameters) and a straight-ridge study.
        approved = face_mask.control_points()
        ## PERTURB
        straight = face_mask.control_points({"ridge_straight": 1.0, "ridge_angle": 0.5})
        ## ACT / ASSERT: zero studies are the approved CONTROL exactly; a straight ridge puts
        ## the mid vertex on the line from the inner to the outer vertex; an angled ridge
        ## descends outward; the centre line and the boundary never move.
        for name, value in face_mask.CONTROL.items():
            self.assertEqual(approved[name], value)
        (ui, vi), (um, vm), (uo, vo) = (straight[n][:2] for n in ("brow_inner", "brow_mid", "brow_outer"))
        self.assertLess(abs(vm - (vi + (vo - vi) * (um - ui) / (uo - ui))), 0.004)
        self.assertLess(vo, approved["brow_outer"][1])
        for name in face_mask.BOUNDARY + ("bridge_root", "nose_peak"):
            self.assertEqual(straight[name], approved[name])

    def test_an_unanchored_mark_is_unchanged(self):
        ## ARRANGE
        plain = {"x": 0.3, "z": 0.5, "width": 0.2, "tilt_deg": 4.0}
        ## ACT / ASSERT
        self.assertEqual(face_mask.resolve_mark(plain, WOLF_ASPECT), plain)


class Refinement(unittest.TestCase):
    def test_refinement_shares_every_panel_edge(self):
        n = 3
        points, triangles = face_mask.refined(n)
        vertices, edges, faces = len(face_mask.control_points()), len(face_mask.edges()), len(face_mask.panels())
        self.assertEqual(len(points), vertices + edges * (n - 1) + faces * (n - 1) * (n - 2) // 2)
        self.assertEqual(len(triangles), faces * n * n)
        for key, (weights, swell, _region) in points.items():
            self.assertAlmostEqual(sum(weights.values()), 1.0, places=12)
            self.assertEqual(swell > 0.0, len(key) == 3, key)


class Parameters(unittest.TestCase):
    def test_the_architecture_follows_the_head(self):
        base = face_mask.control_points()
        strong = face_mask.control_points({"nose_projection": 1.0})
        self.assertAlmostEqual(strong["nose_peak"][2] - base["nose_peak"][2], 0.005, places=12)
        wide = face_mask.control_points({"cheekbone_width": 0.5})
        self.assertGreater(wide["cheekbone"][0], base["cheekbone"][0])
        self.assertAlmostEqual(wide["cheekbone.R"][0], -wide["cheekbone"][0], places=12)
        self.assertEqual(wide["nose_peak"], base["nose_peak"])


if __name__ == "__main__":
    unittest.main()
