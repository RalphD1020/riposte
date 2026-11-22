"""RETOPOLOGY-REFERENCE-001: a production retopology is fitted only to the pinned processed,
symmetric default body. The raw BodyV2 sculpt (the wrong-stage input the F8 junctions were first
fitted to), any other geometry, a different rig rest, and a scene whose clips are missing or do
not move the rig are rejected before any fitting."""
import unittest

from character_modeling import retopology_reference as ref

CLIPS = ("idle", "walk_forward", "death")
BONES = [("Hips", None, (0.0, 0.0, 0.89), (0.0, 0.0, 1.03)), ("UpperLeg.L", "Hips", (0.12, 0.04, 0.89), (0.12, 0.04, 0.4)),
         ("UpperLeg.R", "Hips", (-0.12, 0.04, 0.89), (-0.12, 0.04, 0.4))]


def body(depth=0.37):
    """A small symmetric closed 'body': a box whose front-to-back depth is `depth`."""
    v = [(x, y, z) for z in (0.0, 1.6) for y in (-depth / 2, depth / 2) for x in (-0.2, 0.2)]
    f = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return v, f


def observation(source="RetopoTarget", depth=0.37, bones=BONES, motion=None):
    v, f = body(depth)
    return ref.observe(v, f, source, bones, motion if motion is not None else {c: 0.2 for c in CLIPS})


class Reference(unittest.TestCase):
    def setUp(self):
        ## ARRANGE: the pin taken from the approved processed default.
        self.pin = ref.pin(observation(), {"foundation": "male_base_foundation"}, CLIPS)

    def test_the_pinned_reference_is_accepted(self):
        ## ACT / ASSERT: the same reference observed again has no problems.
        self.assertEqual(ref.problems(self.pin, observation()), [])

    def test_the_raw_sculpt_is_rejected_before_fitting(self):
        ## PERTURB: the raw BodyV2 sculpt, symmetrized, 3 cm deeper (the defect that happened).
        raw = observation(source="BodyV2_sym", depth=0.401)
        ## ACT
        found = ref.problems(self.pin, raw)
        ## ASSERT: named as the raw sculpt AND as not the pinned geometry.
        self.assertTrue(any("raw sculpt" in p for p in found), found)
        self.assertTrue(any("not the pinned processed default" in p for p in found), found)

    def test_a_renamed_raw_sculpt_is_still_rejected_by_its_geometry(self):
        ## PERTURB: the wrong geometry under the right object name (a name proves nothing).
        disguised = observation(source="RetopoTarget", depth=0.401)
        ## ACT / ASSERT
        self.assertTrue(any("not the pinned processed default" in p for p in ref.problems(self.pin, disguised)))

    def test_a_moved_vertex_is_a_different_body(self):
        ## PERTURB: one vertex moved 1 mm (a different body revision).
        v, f = body()
        v[0] = (v[0][0], v[0][1] - 0.001, v[0][2])
        moved = ref.observe(v, f, "RetopoTarget", BONES, {c: 0.2 for c in CLIPS})
        ## ACT / ASSERT
        self.assertTrue(any("not the pinned processed default" in p for p in ref.problems(self.pin, moved)))

    def test_a_different_rig_rest_is_rejected(self):
        ## PERTURB: the knee 2 cm higher (another skeleton).
        other = [BONES[0], ("UpperLeg.L", "Hips", (0.12, 0.04, 0.89), (0.12, 0.04, 0.42)), BONES[2]]
        ## ACT / ASSERT
        self.assertTrue(any("rest" in p for p in ref.problems(self.pin, observation(bones=other))))

    def test_missing_and_motionless_clips_are_rejected(self):
        ## PERTURB: `death` absent (lost to a name collision) and `idle` present but evaluating to
        ## the rest pose (an armature that exists proves nothing).
        motion = {"idle": 0.0, "walk_forward": 0.2}
        ## ACT
        found = ref.problems(self.pin, observation(motion=motion))
        ## ASSERT
        self.assertTrue(any("missing" in p and "death" in p for p in found), found)
        self.assertTrue(any("not moving" in p and "idle" in p for p in found), found)

    def test_an_asymmetric_target_is_rejected(self):
        ## PERTURB: one side 5 mm wider (the unsymmetrized approved sculpt).
        v, f = body()
        v = [(x + 0.005 if x > 0 else x, y, z) for x, y, z in v]
        lopsided = ref.observe(v, f, "RetopoTarget", BONES, {c: 0.2 for c in CLIPS})
        ## ACT / ASSERT
        self.assertTrue(any("symmetric" in p for p in ref.problems(self.pin, lopsided)))


if __name__ == "__main__":
    unittest.main()
