"""CHARACTER-SYMMETRY-001: the default foundation's bilateral-symmetry checks catch the failure
class the rejected F8 candidate showed (asymmetric legs/calves, off-midline seam, mirrored-weight
errors) and pass a genuinely symmetric mesh. The checks run on the neutral A-pose only."""
import unittest

from character_modeling import symmetry


def mirrored_block(half, z=0.0):
    """A symmetric vertex set: each off-axis point and its (-x, y, z) mirror, plus a seam vertex."""
    verts = [(0.0, 0.1, z)]  # centerline seam
    for x, y in half:
        verts.append((x, y, z))
        verts.append((-x, y, z))
    return verts


class Geometry(unittest.TestCase):
    def setUp(self):
        self.verts = mirrored_block([(0.2, 0.0), (0.4, 0.1), (0.15, -0.2), (0.33, 0.33)])

    def test_a_symmetric_mesh_passes(self):
        problems, stats = symmetry.mirror_problems(self.verts)
        self.assertEqual(problems, [])
        self.assertTrue(stats["symmetric"])
        self.assertEqual(stats["unmatched"], 0)
        self.assertEqual(stats["centerline"], 1)

    def test_a_moved_vertex_breaks_symmetry(self):
        # PERTURB: push one side's vertex 5 mm so its mirror no longer matches (like the
        # asymmetric calf bulge in the rejected candidate).
        broken = list(self.verts)
        broken[1] = (0.205, 0.0, 0.0)
        problems, stats = symmetry.mirror_problems(broken)
        self.assertTrue(any("no mirror counterpart" in p for p in problems))
        self.assertGreaterEqual(stats["unmatched"], 1)

    def test_an_off_midline_seam_vertex_is_caught(self):
        # A lone seam vertex pushed off the midline loses its self-match and has no partner.
        broken = list(self.verts)
        broken[0] = (0.0015, 0.1, 0.0)  # drifted off the midline (unmerged seam), no counterpart
        problems, stats = symmetry.mirror_problems(broken)
        self.assertTrue(any("no mirror counterpart" in p for p in problems))
        self.assertGreaterEqual(stats["unmatched"], 1)

    def test_a_seam_vertex_on_the_midline_matches_itself(self):
        # A single on-midline seam vertex is its own counterpart; symmetric.
        self.assertEqual(symmetry.mirror_problems([(0.0, 0.2, 0.1), (0.3, 0.0, 0.0), (-0.3, 0.0, 0.0)])[0], [])

    def test_tolerance_accepts_subtolerance_noise_and_rejects_above(self):
        near = list(self.verts)
        near[1] = (0.2 + 5e-4, 0.0, 0.0)  # within 1 mm
        self.assertEqual(symmetry.mirror_problems(near)[0], [])
        far = list(self.verts)
        far[1] = (0.2 + 3e-3, 0.0, 0.0)  # beyond 1 mm
        self.assertTrue(symmetry.mirror_problems(far)[0])


class Weights(unittest.TestCase):
    def test_mirrored_weights_pass_and_wrong_side_influence_fails(self):
        verts = [(0.0, 0.0, 0.0), (0.3, 0.0, 0.0), (-0.3, 0.0, 0.0)]
        good = [{"Spine": 1.0}, {"UpperArm.L": 0.8, "Chest": 0.2}, {"UpperArm.R": 0.8, "Chest": 0.2}]
        self.assertEqual(symmetry.weight_mirror_problems(verts, good, symmetry.mirror_bone_name)[0], [])
        bad = [{"Spine": 1.0}, {"UpperArm.L": 0.8, "Chest": 0.2}, {"UpperArm.L": 0.8, "Chest": 0.2}]
        problems, stats = symmetry.weight_mirror_problems(verts, bad, symmetry.mirror_bone_name)
        self.assertTrue(problems)
        self.assertEqual(stats["checked_pairs"], 2)

    def test_mirror_bone_name_convention(self):
        self.assertEqual(symmetry.mirror_bone_name("UpperArm.L"), "UpperArm.R")
        self.assertEqual(symmetry.mirror_bone_name("Forearm.R"), "Forearm.L")
        self.assertEqual(symmetry.mirror_bone_name("Spine"), "Spine")


class Seam(unittest.TestCase):
    """A seam vertex mirrors to itself whether or not the halves are joined, so the weld is a
    separate topology check."""

    def test_a_welded_strip_passes_and_split_halves_fail(self):
        # ARRANGE: two quads sharing a midline edge (welded).
        verts = [(-0.2, 0.0, 0.0), (0.0, 0.0, 0.0), (0.0, 0.0, 1.0), (-0.2, 0.0, 1.0), (0.2, 0.0, 0.0), (0.2, 0.0, 1.0)]
        welded = [(0, 1, 2, 3), (1, 4, 5, 2)]
        self.assertEqual(symmetry.centerline_seam_problems(verts, welded)[0], [])
        self.assertEqual(symmetry.mirror_problems(verts)[0], [])
        # PERTURB: the same halves mirrored but never merged (duplicate midline vertices).
        split = verts + [(0.0, 0.0, 0.0), (0.0, 0.0, 1.0)]
        halves = [(0, 1, 2, 3), (6, 4, 5, 7)]
        problems, stats = symmetry.centerline_seam_problems(split, halves)
        self.assertGreater(stats["open_seam_edges"], 0)
        self.assertEqual(stats["duplicate_seam_vertices"], 2)
        # The geometric mirror check cannot see this — which is why the weld check is separate.
        self.assertEqual(symmetry.mirror_problems(split)[0], [])


class Skeleton(unittest.TestCase):
    def rig(self):
        return {"Hips": {"head": (0.0, 0.0, 0.9), "tail": (0.0, 0.0, 1.0), "parent": None},
                "UpperArm.L": {"head": (0.25, 0.0, 1.4), "tail": (0.5, 0.0, 1.2), "parent": "Hips"},
                "UpperArm.R": {"head": (-0.25, 0.0, 1.4), "tail": (-0.5, 0.0, 1.2), "parent": "Hips"},
                "Forearm.L": {"head": (0.5, 0.0, 1.2), "tail": (0.7, 0.0, 1.0), "parent": "UpperArm.L"},
                "Forearm.R": {"head": (-0.5, 0.0, 1.2), "tail": (-0.7, 0.0, 1.0), "parent": "UpperArm.R"}}

    def test_a_mirrored_rest_skeleton_passes(self):
        problems, stats = symmetry.bone_mirror_problems(self.rig())
        self.assertEqual(problems, [])
        self.assertEqual(stats["pairs"], 2)

    def test_an_asymmetric_rest_pose_is_caught(self):
        # PERTURB: a guard-like rest that bends only the right forearm toward the centreline.
        rig = self.rig()
        rig["Forearm.R"]["tail"] = (-0.45, -0.25, 1.05)
        problems, stats = symmetry.bone_mirror_problems(rig)
        self.assertTrue(any("Forearm.L and Forearm.R" in p for p in problems))
        self.assertGreater(stats["worst_joint_offset_m"], 0.1)

    def test_parents_centre_bones_and_missing_counterparts(self):
        rig = self.rig()
        rig["Forearm.R"]["parent"] = "Hips"
        rig["Hips"]["head"] = (0.02, 0.0, 0.9)
        del rig["UpperArm.R"]
        problems, _ = symmetry.bone_mirror_problems(rig)
        for expected in ("parent Hips does not mirror", "centre bone Hips", "UpperArm.L has no counterpart"):
            self.assertTrue(any(expected in p for p in problems), (expected, problems))


class RestOrientation(unittest.TestCase):
    """Rest ORIENTATION (roll) symmetry: the geometric local-axis check joint positions miss."""

    def roll_rig(self):
        # A centre bone with an in-plane roll axis, and a mirrored pair whose roll axes reflect.
        return {"Spine": {"roll_axis": (0.0, -1.0, 0.0)},
                "UpperArm.L": {"roll_axis": (0.3, 0.0, 0.954)},
                "UpperArm.R": {"roll_axis": (-0.3, 0.0, 0.954)}}

    def test_mirrored_roll_axes_pass(self):
        problems, stats = symmetry.bone_rest_orientation_problems(self.roll_rig())
        self.assertEqual(problems, [])
        self.assertEqual(stats["pairs"], 1)
        self.assertTrue(stats["symmetric"])

    def test_a_rolled_counterpart_is_caught(self):
        # PERTURB: the right arm keeps a left-like roll (not reflected) — the twist risk.
        rig = self.roll_rig()
        rig["UpperArm.R"]["roll_axis"] = (0.3, 0.0, 0.954)
        problems, stats = symmetry.bone_rest_orientation_problems(rig)
        self.assertTrue(any("UpperArm.L and UpperArm.R" in p for p in problems))
        self.assertGreater(stats["worst_orientation_deg"], 1.0)

    def test_a_centre_bone_tilted_off_the_midline_plane_is_caught(self):
        rig = self.roll_rig()
        rig["Spine"]["roll_axis"] = (0.3, -0.954, 0.0)  # roll axis leans in X -> not mirror-invariant
        problems, _ = symmetry.bone_rest_orientation_problems(rig)
        self.assertTrue(any("centre bone Spine" in p for p in problems))

    def test_bones_without_a_roll_axis_are_skipped(self):
        # Positions-only callers (plain bone_mirror_problems rigs) are unaffected.
        bare = {"UpperArm.L": {"head": (0.25, 0.0, 1.4)}, "UpperArm.R": {"head": (-0.25, 0.0, 1.4)}}
        problems, stats = symmetry.bone_rest_orientation_problems(bare)
        self.assertEqual(problems, [])
        self.assertEqual(stats["pairs"], 0)


if __name__ == "__main__":
    unittest.main()
