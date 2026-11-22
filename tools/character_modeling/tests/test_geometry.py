"""CHARACTER-BUILD-001: the canonical geometry digest proves exactly what it claims — face
re-ordering is invisible, but winding, vertex movement past the precision, and face
multiplicity are not. It is a geometry digest, never a general asset serializer."""
import unittest

from character_modeling import geometry


def quad(vertices, faces, materials=("mat",)):
    return geometry.mesh_digest(vertices, faces, materials)


class CanonicalDigest(unittest.TestCase):
    def setUp(self):
        # ARRANGE: a two-quad strip, each face carrying (material, region, rim) metadata.
        self.verts = [(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (1.0, 1.0, 0.0), (0.0, 1.0, 0.0),
                      (2.0, 0.0, 0.0), (2.0, 1.0, 0.0)]
        self.faces = [((0, 1, 2, 3), (0, 0, 0)), ((1, 4, 5, 2), (0, 1, 0))]

    def digest(self, verts=None, faces=None, materials=("mat",)):
        return quad(verts or self.verts, faces if faces is not None else self.faces, materials)

    def test_face_array_reordering_leaves_the_digest_unchanged(self):
        # PERTURB: the same faces in the opposite array order. ASSERT: equal (serialization
        # order is not part of the identity).
        self.assertEqual(self.digest(faces=list(reversed(self.faces))), self.digest())

    def test_vertex_renumbering_leaves_the_digest_unchanged(self):
        # PERTURB: a face written starting from a different vertex (same winding). ASSERT: equal.
        rotated = [((2, 3, 0, 1), (0, 0, 0)), ((1, 4, 5, 2), (0, 1, 0))]
        self.assertEqual(self.digest(faces=rotated), self.digest())

    def test_reversing_face_winding_changes_the_digest(self):
        # PERTURB: reverse one face's winding. ASSERT: different (front/back matters).
        flipped = [((3, 2, 1, 0), (0, 0, 0)), ((1, 4, 5, 2), (0, 1, 0))]
        self.assertNotEqual(self.digest(faces=flipped), self.digest())

    def test_moving_a_vertex_past_the_precision_changes_the_digest_but_below_it_does_not(self):
        below = list(self.verts)
        below[2] = (1.0 + 10 ** (-(geometry.PRECISION + 1)), 1.0, 0.0)  # a tenth of a rounding step
        self.assertEqual(self.digest(verts=below), self.digest())
        above = list(self.verts)
        above[2] = (1.0 + 10 ** (-geometry.PRECISION) * 5, 1.0, 0.0)  # five rounding steps
        self.assertNotEqual(self.digest(verts=above), self.digest())

    def test_removing_or_duplicating_a_face_changes_the_digest(self):
        self.assertNotEqual(self.digest(faces=self.faces[:1]), self.digest())
        self.assertNotEqual(self.digest(faces=self.faces + self.faces[:1]), self.digest())

    def test_duplicate_faces_are_preserved_not_collapsed(self):
        # ASSERT: two identical faces are not de-duplicated (one vs two differ).
        one = [((0, 1, 2, 3), (0, 0, 0))]
        two = [((0, 1, 2, 3), (0, 0, 0)), ((0, 1, 2, 3), (0, 0, 0))]
        self.assertNotEqual(quad(self.verts, two), quad(self.verts, one))
        self.assertEqual(len(geometry.canonical_faces(self.verts, two)), 2)

    def test_material_and_face_metadata_are_part_of_identity(self):
        # PERTURB: same surface, different material names / different per-face region.
        self.assertNotEqual(self.digest(materials=("other",)), self.digest())
        regioned = [((0, 1, 2, 3), (0, 9, 0)), ((1, 4, 5, 2), (0, 1, 0))]
        self.assertNotEqual(self.digest(faces=regioned), self.digest())

    def test_the_digest_is_stable_across_calls(self):
        self.assertEqual(self.digest(), self.digest())


if __name__ == "__main__":
    unittest.main()
