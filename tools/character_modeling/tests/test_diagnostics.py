"""TEST-TRUTH: each test asserts its fixture (ARRANGE), the defect it adds
(PERTURB), the production diagnostic (ACT), and the reported category,
region, location, and new-versus-baseline status (ASSERT)."""

from __future__ import annotations

import math
import unittest

import fixtures
from character_modeling import anatomy, diagnostics, measurements, outline, regions
from character_modeling.mesh_data import FLAG_FACE_PANEL, FLAG_FACE_RIDGE, FLAG_FACE_V, MeshData


def torso_rows(mesh, z0, z1, step=0.01):
    rows = []
    for k in range(int(round((z1 - z0) / step)) + 1):
        z = z0 + k * step
        section = diagnostics.slice_section(mesh, (0.0, 0.0, z), (0.0, 0.0, 1.0), (1.0, 0.0, 0.0))
        section.update(s=round(z, 4), at=[0.0, 0.0, round(z, 4)])
        rows.append(section)
    return rows


def kinds(findings):
    return sorted({f["kind"] for f in findings})


class CleanCylinder(unittest.TestCase):
    def test_clean_capsule_has_no_reversal_shelf_crease_or_corner(self):
        mesh = fixtures.capsule()
        self.assertEqual(diagnostics.integrity(mesh)["boundary_edges"], 0)
        rows = torso_rows(mesh, 0.05, 0.55)
        self.assertTrue(all(abs(r["width"] - 0.2) < 0.002 for r in rows))
        labels = fixtures.uniform_labels(mesh, "chest")
        found = diagnostics.section_findings({"torso": rows})
        found += diagnostics.crease_findings(diagnostics.crease_clusters(mesh, labels))
        _out, corners = diagnostics.outlines(mesh, labels, views=("front", "side"))
        self.assertEqual(found + corners, [])


class SteppedCylinder(unittest.TestCase):
    def test_step_is_found_by_section_crease_and_outline_at_its_height(self):
        clean = fixtures.capsule()
        mesh = fixtures.stepped_capsule(step_z=0.3)
        widths = {round(r["s"], 2): r["width"] for r in torso_rows(mesh, 0.25, 0.35)}
        self.assertGreater(widths[0.31] - widths[0.29], 0.025)
        self.assertNotEqual(clean.mesh_hash(), mesh.mesh_hash())
        labels = fixtures.uniform_labels(mesh, "chest")
        shelf = diagnostics.section_findings({"torso": torso_rows(mesh, 0.05, 0.55)})
        creases = diagnostics.crease_findings(diagnostics.crease_clusters(mesh, labels))
        _out, corners = diagnostics.outlines(mesh, labels, views=("front",))
        self.assertIn("section_shelf", kinds(shelf))
        self.assertTrue(all(abs(f["at"][2] - 0.3) <= 0.015 for f in shelf))
        self.assertTrue(creases and all(abs(f["at"][2] - 0.3) <= 0.015 for f in creases))
        self.assertEqual({f["region"] for f in creases}, {"chest"})
        convex = [f for f in corners if f["kind"] == "outline_corner"]
        self.assertTrue(convex and all(abs(f["at"][2] - 0.3) <= 0.02 for f in convex))
        self.assertEqual({f["view"] for f in convex}, {"front"})


class BoxCorner(unittest.TestCase):
    def test_box_edges_and_corners_are_reported_outside_approved_features(self):
        mesh = fixtures.box()
        self.assertEqual(diagnostics.integrity(mesh)["components"], 1)
        self.assertEqual(diagnostics.integrity(mesh)["inconsistent_winding_edges"], 0)
        labels = fixtures.uniform_labels(mesh, "upper_arm")
        clusters = diagnostics.crease_clusters(mesh, labels)
        _out, corners = diagnostics.outlines(mesh, labels, views=("front",))
        self.assertEqual(len(clusters), 1)
        self.assertEqual(clusters[0]["edges"], 12)
        self.assertAlmostEqual(clusters[0]["peak_deg"], 90.0, places=3)
        self.assertEqual(len([c for c in corners if c["kind"] == "outline_corner"]), 4)
        for corner in corners:
            self.assertAlmostEqual(abs(corner["at"][0]), 0.1, delta=0.002)
            self.assertAlmostEqual(abs(corner["at"][2]), 0.1, delta=0.002)


class DentedSurface(unittest.TestCase):
    def dent(self, v):
        d = math.dist(v, (0.1, 0.0, 0.0))
        return -0.006 * max(0.0, 1.0 - d / 0.025)

    def test_dent_is_ranked_then_corroborated_by_its_rim_crease(self):
        clean = fixtures.sphere(rings=64, sides=128)
        labels = fixtures.uniform_labels(clean, "back_upper")
        self.assertEqual(diagnostics.offset_dents(clean, labels), [])
        self.assertEqual(diagnostics.crease_clusters(clean, labels), [])
        mesh = fixtures.displaced(clean, self.dent)
        self.assertAlmostEqual(min(math.dist(v, (0, 0, 0)) for v in mesh.vertices), 0.094, places=4)
        dents = diagnostics.offset_findings(diagnostics.offset_dents(mesh, labels))
        creases = diagnostics.crease_findings(diagnostics.crease_clusters(mesh, labels))
        self.assertEqual(len(dents), 1)
        dent = dents[0]
        self.assertTrue(dent["experimental"])
        self.assertEqual((dent["kind"], dent["region"], dent["severity"]), ("offset_dent", "back_upper", "low"))
        self.assertLess(math.dist(dent["at"], (0.094, 0.0, 0.0)), 0.005)
        self.assertLess(dent["evidence"]["deepest_m"], -0.0015)
        self.assertTrue(creases and all(math.dist(f["at"], (0.095, 0.0, 0.0)) < 0.03 for f in creases))
        diagnostics.corroborate(dents + creases)
        self.assertEqual(dent["severity"], "medium")
        self.assertEqual(dent["evidence"]["corroborated_by"], ["crease_cluster"])

    def test_uncorroborated_dent_stays_low(self):
        mesh = fixtures.displaced(fixtures.sphere(rings=64, sides=128), self.dent)
        labels = fixtures.uniform_labels(mesh, "back_upper")
        dents = diagnostics.offset_findings(diagnostics.offset_dents(mesh, labels))
        self.assertEqual(len(dents), 1)
        diagnostics.corroborate(dents)
        self.assertEqual((dents[0]["severity"], dents[0]["evidence"]["corroborated_by"]), ("low", []))


class MirroredAsymmetry(unittest.TestCase):
    def test_one_side_widened_is_reported_with_its_worst_point(self):
        clean = fixtures.sphere()
        self.assertLess(diagnostics.symmetry(clean)["mirror_max_dev_m"], 1e-9)
        mesh = fixtures.sphere(radius_at=lambda z, a, r: r * (1.05 if math.sin(a) > 0.3 else 1.0))
        report = diagnostics.symmetry(mesh)
        self.assertGreater(report["mirror_max_dev_m"], 0.003)
        self.assertGreater(abs(report["mirror_worst_at"][0]), 0.02)

    def test_left_right_limb_sections_that_differ_are_reported(self):
        left = [{"s": 0.5, "width": 0.08, "depth": 0.07, "at": [0.3, 0.0, 1.3]}]
        right = [{"s": 0.5, "width": 0.087, "depth": 0.07, "at": [-0.3, 0.0, 1.3]}]
        self.assertGreater(abs(left[0]["width"] - right[0]["width"]), 0.002)
        found = diagnostics.section_findings({"upper_arm.L": left, "upper_arm.R": right})
        self.assertEqual([(f["kind"], f["region"], f["severity"]) for f in found],
                         [("section_asymmetry", "upper_arm", "high")])


class FaceException(unittest.TestCase):
    def test_flagged_ridge_is_exempt_and_unflagged_ridge_is_reported(self):
        mesh, ridge = fixtures.roof()
        labels = fixtures.uniform_labels(mesh, "head_face")

        def ridge_clusters(m):
            return [c for c in diagnostics.crease_clusters(m, labels) if abs(c["centroid"][0]) < 0.004]

        bare = ridge_clusters(mesh)
        self.assertEqual(len(bare), 1)
        self.assertAlmostEqual(bare[0]["peak_deg"], 34.0, delta=0.5)
        flagged = MeshData(mesh.vertices, mesh.faces, {FLAG_FACE_RIDGE: ridge, FLAG_FACE_PANEL: range(len(ridge))})
        self.assertEqual(ridge_clusters(flagged), [])
        as_v = MeshData(mesh.vertices, mesh.faces, {FLAG_FACE_V: ridge})
        self.assertEqual(ridge_clusters(as_v), [])


class FaceRegression(unittest.TestCase):
    def head(self, perturb=None):
        mesh = fixtures.sphere(radius_at=perturb)
        normals, _ = mesh.face_normals()
        centres = [[sum(mesh.vertices[i][k] for i in f) / len(f) for k in range(3)] for f in mesh.faces]
        panel = [i for i, c in enumerate(centres) if c[1] < -0.05 and c[2] < 0.03]
        ridge = [i for i in panel if abs(centres[i][0]) < 0.006]
        return MeshData(mesh.vertices, mesh.faces, {FLAG_FACE_PANEL: panel, FLAG_FACE_RIDGE: ridge})

    def test_crown_hollow_above_the_face_is_reported_despite_face_flags(self):
        clean = self.head()
        labels = fixtures.uniform_labels(clean, "head_crown")
        self.assertEqual(diagnostics.crease_clusters(clean, labels), [])

        def hollow(z, angle, r):
            front = math.cos(angle) > 0.5
            return r - 0.005 if front and 0.045 <= z <= 0.06 else r

        mesh = self.head(hollow)
        self.assertTrue(mesh.face_flags[FLAG_FACE_RIDGE])
        found = diagnostics.crease_findings(diagnostics.crease_clusters(mesh, labels))
        self.assertTrue(found)
        self.assertEqual({f["region"] for f in found}, {"head_crown"})
        self.assertTrue(all(0.035 <= f["at"][2] <= 0.07 and f["at"][1] < 0 for f in found))

    def test_panel_sunk_into_the_head_is_reported_at_its_border(self):
        def sunk(z, angle, r):
            inside = math.cos(angle) > 0.6 and -0.06 < z < 0.02
            return r - 0.004 if inside else r

        mesh = self.head(sunk)
        labels = fixtures.uniform_labels(mesh, "head_face")
        found = diagnostics.crease_findings(diagnostics.crease_clusters(mesh, labels))
        self.assertTrue(found)
        self.assertEqual({f["region"] for f in found}, {"head_face"})
        self.assertTrue(all(f["at"][1] < -0.03 for f in found))


class JointProtrusion(unittest.TestCase):
    def test_tent_bump_on_the_shoulder_is_a_convex_outline_corner(self):
        clean = fixtures.capsule()
        labels = fixtures.uniform_labels(clean, "shoulder")
        _out, before = diagnostics.outlines(clean, labels, views=("front",))
        self.assertEqual(before, [])

        def bump(z, angle, r):
            d = math.hypot(z - 0.4, (angle - math.pi / 2.0) * r)
            return r + 0.012 * max(0.0, 1.0 - d / 0.015)

        mesh = fixtures.revolve(fixtures.capsule_profile(0.1, 0.0, 0.6, 0.005), 96, radius_at=bump)
        self.assertGreater(max(v[0] for v in mesh.vertices), 0.11)
        labels = fixtures.uniform_labels(mesh, "shoulder")
        _out, corners = diagnostics.outlines(mesh, labels, views=("front",))
        convex = [f for f in corners if f["kind"] == "outline_corner"]
        self.assertTrue(convex)
        self.assertTrue(any(math.dist(f["at"], (0.112, 0.0, 0.4)) < 0.01 for f in convex))
        self.assertEqual({f["region"] for f in convex}, {"shoulder"})


class ResolutionStability(unittest.TestCase):
    def test_step_is_found_at_both_study_resolutions(self):
        coarse = fixtures.stepped_capsule(ring_step=0.01, sides=48)
        fine = fixtures.stepped_capsule(ring_step=0.007, sides=64)
        self.assertNotEqual(coarse.stats(), fine.stats())
        found = []
        for mesh in (coarse, fine):
            labels = fixtures.uniform_labels(mesh, "chest")
            found.append(diagnostics.crease_findings(diagnostics.crease_clusters(mesh, labels)))
        self.assertTrue(found[0] and found[1])
        self.assertEqual(diagnostics.persistence(found[0], found[1]), [True] * len(found[0]))


class HiddenGeometry(unittest.TestCase):
    def test_creases_on_buried_vertices_are_not_reported(self):
        mesh = fixtures.box()
        labels = fixtures.uniform_labels(mesh, "neck")
        self.assertEqual(len(diagnostics.crease_clusters(mesh, labels)), 1)
        top = [i for i, v in enumerate(mesh.vertices) if v[2] > 0.0]
        buried = MeshData(mesh.vertices, mesh.faces, hidden=top)
        clusters = diagnostics.crease_clusters(buried, labels)
        self.assertEqual(len(clusters), 1)
        self.assertEqual(clusters[0]["edges"], 4)
        self.assertAlmostEqual(clusters[0]["peak_at"][2], -0.1)
        merged = MeshData.merged([buried, fixtures.box(0.05)])
        self.assertEqual(merged.hidden, set(top))


class Integrity(unittest.TestCase):
    def test_open_flipped_duplicated_and_split_meshes(self):
        closed = fixtures.box()
        self.assertEqual(diagnostics.integrity(closed),
                         {"boundary_edges": 0, "nonmanifold_edges": 0, "inconsistent_winding_edges": 0,
                          "degenerate_faces": 0, "components": 1})
        opened = MeshData(closed.vertices, closed.faces[:-1])
        self.assertEqual(diagnostics.integrity(opened)["boundary_edges"], 4)
        flipped = MeshData(closed.vertices, closed.faces[:-1] + [tuple(reversed(closed.faces[-1]))])
        self.assertEqual(diagnostics.integrity(flipped)["inconsistent_winding_edges"], 4)
        doubled = MeshData(closed.vertices, closed.faces + [closed.faces[0]])
        self.assertEqual(diagnostics.integrity(doubled)["nonmanifold_edges"], 4)
        two = MeshData.merged([closed, fixtures.box(0.1)])
        self.assertEqual(diagnostics.integrity(two)["components"], 2)
        self.assertEqual(diagnostics.integrity_findings(diagnostics.integrity(two), 1)[0]["evidence"],
                         {"components": 2})


class ControlDiffAndReproduction(unittest.TestCase):
    def report(self, mesh):
        labels = fixtures.uniform_labels(mesh, "chest")
        out, corners = diagnostics.outlines(mesh, labels, views=("front",))
        findings = diagnostics.crease_findings(diagnostics.crease_clusters(mesh, labels)) + corners
        return {"stats": mesh.stats(), "mesh_hash": mesh.mesh_hash(), "outlines": out,
                "measurements": {"width": 0.2}, "findings": findings}

    def test_existing_defect_new_defect_and_resolved_defect(self):
        control = self.report(fixtures.stepped_capsule(step_z=0.3))
        self.assertTrue(control["findings"])

        def two_steps(z):
            return 0.10 if z < 0.3 else (0.115 if z < 0.45 else 0.13)

        candidate = self.report(fixtures.capsule(radius_of_z=two_steps))
        result = diagnostics.diff(control["findings"], candidate["findings"])
        self.assertTrue(result["existing"])
        self.assertTrue(all(abs(f["at"][2] - 0.3) <= 0.02 for f in result["existing"]))
        self.assertTrue(result["new"])
        self.assertTrue(all(abs(f["at"][2] - 0.45) <= 0.02 for f in result["new"]))
        healed = self.report(fixtures.capsule())
        resolved = diagnostics.diff(control["findings"], healed["findings"])
        self.assertEqual(resolved["new"], [])
        self.assertEqual(len(resolved["resolved"]), len(control["findings"]))

    def test_rebuild_reproduces_exactly_and_a_moved_vertex_does_not(self):
        control = self.report(fixtures.capsule())
        self.assertEqual(diagnostics.reproduce(control, self.report(fixtures.capsule())), [])
        mesh = fixtures.capsule()
        moved = MeshData([(v[0] + (0.0005 if i == 100 else 0.0), v[1], v[2]) for i, v in enumerate(mesh.vertices)], mesh.faces)
        self.assertEqual([p["check"] for p in diagnostics.reproduce(control, self.report(moved))], ["mesh_hash"])
        coarse = self.report(fixtures.capsule(sides=40))
        coarse["measurements"] = {"width": 0.21}
        checks = [p["check"] for p in diagnostics.reproduce(control, coarse)]
        self.assertEqual(checks[:2], ["topology", "mesh_hash"])
        self.assertIn("measurements", checks)

    def test_protected_measurement_tolerances(self):
        control = {"head": {"nose_y": -0.1353, "ridge_rows": 67}, "span": 0.9094}
        same = {"head": {"nose_y": -0.1355, "ridge_rows": 67}, "span": 0.9094}
        moved = {"head": {"nose_y": -0.1300, "ridge_rows": 60}, "span": 0.9094}
        tolerances = {"head.nose_y": 0.0005, "head.ridge_rows": 0, "span": 0.002}
        self.assertEqual(diagnostics.compare_measurements(control, same, tolerances), [])
        paths = [v["path"] for v in diagnostics.compare_measurements(control, moved, tolerances)]
        self.assertEqual(paths, ["head.nose_y", "head.ridge_rows"])


class ProfileShapes(unittest.TestCase):
    def test_single_belly_passes_and_double_belly_and_dip_are_reported(self):
        belly = [0.06 + 0.02 * math.sin(math.pi * k / 12) for k in range(13)]
        self.assertEqual(diagnostics.zigzag(belly, 0.0015), [(6, "max")])
        double = [0.06 + 0.01 * abs(math.sin(2 * math.pi * k / 12)) for k in range(13)]
        rows = [{"s": k / 12, "width": w, "depth": 0.07, "at": [0.3, 0.0, 1.3 - 0.02 * k]} for k, w in enumerate(double)]
        found = diagnostics.section_findings({"upper_arm.L": rows})
        self.assertEqual(sorted(f["kind"] for f in found), ["section_dip", "section_extra_belly"])
        self.assertTrue(all(f["region"] == "upper_arm" for f in found))
        self.assertEqual([f["evidence"]["station"] for f in found if f["kind"] == "section_dip"], [0.5])


class RegionsAndControls(unittest.TestCase):
    def test_regions_blend_at_boundaries_and_name_both_sides(self):
        lm = fixtures.landmarks()
        self.assertEqual(anatomy.validate_landmarks(lm), [])
        self.assertEqual(anatomy.classify((0.0, -0.12, 1.25), lm)[:2], ("chest", 1.0))
        self.assertEqual(anatomy.classify((0.0, 0.12, 1.2), lm)[0], "back_lower")
        self.assertEqual(anatomy.classify((0.12, 0.1, 1.38), lm)[0], "back_upper")
        self.assertEqual(anatomy.classify((0.35, 0.0, 1.35), lm)[0], "upper_arm")
        self.assertEqual(anatomy.classify((0.1, 0.0, 0.3), lm)[0], "calf")
        self.assertEqual(anatomy.classify((0.0, 0.0, 1.7), lm, part=anatomy.PART_HEAD, on_face=True)[0], "head_face")
        self.assertEqual(anatomy.classify((0.05, 0.0, 1.62), lm, part=anatomy.PART_HEAD)[0], "head_jaw")
        self.assertEqual(anatomy.classify((0.05, 0.0, 1.8), lm, part=anatomy.PART_HEAD)[0], "head_crown")
        region, confidence, neighbour = anatomy.classify((0.0, -0.1, 1.105), lm)
        self.assertEqual((region, neighbour), ("chest", "abdomen"))
        self.assertLess(confidence, 0.8)
        self.assertEqual(anatomy.label((region, confidence, neighbour)), "chest / abdomen")
        broken = dict(lm, hip_z=1.2)
        self.assertTrue(anatomy.validate_landmarks(broken))

    def test_controls_default_to_one_and_muscularity_stays_disabled(self):
        resolved = anatomy.resolve_controls()
        self.assertEqual(set(resolved.values()), {1.0})
        self.assertEqual(anatomy.resolve_controls({"lat_flare": 1.05})["lat_flare"], 1.05)
        self.assertEqual(anatomy.validate_controls({"muscularity": 1.0}), [])
        self.assertTrue(anatomy.validate_controls({"muscularity": 1.05}))
        self.assertTrue(anatomy.validate_controls({"lat_flare": 1.3}))
        self.assertTrue(anatomy.validate_controls({"bulk": 1.0}))
        with self.assertRaises(ValueError):
            anatomy.resolve_controls({"arm_fullness": True})


class ProtectedMeasurements(unittest.TestCase):
    def test_every_entry_is_classified_documented_and_owned(self):
        for entry in measurements.REGISTRY:
            self.assertIn(entry.cls, measurements.HARD_CLASSES | measurements.SOFT_CLASSES)
            self.assertIn(entry.status, ("calibrated", "provisional", "advisory"))
            self.assertTrue(entry.owner and entry.method and entry.rationale)
            self.assertGreaterEqual(entry.tolerance, 0)

    def test_hard_tolerances_exclude_the_phase_owned_invariant(self):
        full = measurements.hard_tolerances()
        self.assertIn("body.deltoid_span_m", full)
        self.assertNotIn("body.deltoid_span_m", measurements.hard_tolerances(exclude=("body.deltoid_span_m",)))
        self.assertIn("head_landmarks.integrity.mirror_max_dev_m", full)

    def test_body_span_tolerance_is_at_least_one_voxel(self):
        span = measurements.BY_PATH["body.deltoid_span_m"]
        self.assertGreaterEqual(span.tolerance, measurements.VOXEL_M)
        nose = measurements.BY_PATH["head_landmarks.mask_fit.face.nose_tip.y"]
        self.assertLess(nose.tolerance, measurements.VOXEL_M)  # skull loft, not remeshed


class ThresholdStatus(unittest.TestCase):
    def test_every_finding_carries_a_status_and_the_probe_is_advisory(self):
        self.assertEqual(regions.status("offset_dent"), "advisory")
        self.assertEqual(regions.status("integrity"), "calibrated")
        self.assertEqual(regions.status("crease_cluster"), "provisional")
        mesh = fixtures.box()
        cap = {"figure": "t", "parts": [{"vertices": [list(v) for v in mesh.vertices],
                                         "faces": [list(f) for f in mesh.faces], "role": "body"}],
               "landmarks": fixtures.landmarks()}
        report = diagnostics.scan(cap, include_offsets=False, include_outlines=False)
        self.assertTrue(all("status" in f for f in report["findings"]))


class OutlineProjection(unittest.TestCase):
    def test_projected_square_area_and_counter_clockwise_loop(self):
        mesh = fixtures.box(0.2)
        raster = outline.project(mesh, "front", 0.002)
        self.assertAlmostEqual(raster.area(), 0.04, delta=0.0015)
        loop = outline.outer_loop(raster)
        area = 0.5 * sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(loop, loop[1:] + loop[:1]))
        self.assertGreater(area, 0.038)
        self.assertEqual(len(outline.sample_points(loop, 16)), 16)
        out, _ = diagnostics.outlines(mesh, fixtures.uniform_labels(mesh, "chest"), views=("front",), cell=0.002)
        self.assertAlmostEqual(out["front"]["area_m2"], 0.04, delta=0.0003)
        # Within one cell per side.
        self.assertAlmostEqual(out["front"]["perimeter_m"], 0.8, delta=4 * 0.002 * 2)

    def test_unknown_face_flag_and_bad_index_are_refused(self):
        with self.assertRaises(ValueError):
            MeshData([(0, 0, 0), (1, 0, 0), (0, 1, 0)], [(0, 1, 2)], {"cheek": [0]})
        with self.assertRaises(ValueError):
            MeshData([(0, 0, 0), (1, 0, 0), (0, 1, 0)], [(0, 1, 3)])


if __name__ == "__main__":
    unittest.main()
