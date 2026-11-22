"""Applies a `character_modeling.pose_suite` sample to a WolfRig armature (POSE-SUITE-001).

One applier for every consumer: the coverage envelope (`male_base_v2_variation`), the
deformation audit and the review captures. Angles are world-space deltas from the rest
pose; a child bone's delta is set in its own rest frame, so it composes with its parent's
(the clavicle's share of a raise carries the upper arm with it)."""

import math

from mathutils import Matrix, Vector

FRONT = Vector((0.0, -1.0, 0.0))


def _set(pb, world):
    pb.rotation_mode = "QUATERNION"
    rest = pb.bone.matrix_local.to_3x3()
    pb.rotation_quaternion = (rest.inverted() @ world @ rest).to_quaternion()


def reset(rig):
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.location = (0.0, 0.0, 0.0)


def apply(rig, sample):
    """Rest, then the sample's arms and torso twist."""
    reset(rig)
    bones = rig.pose.bones
    for side, arm in sample.get("arms", {}).items():
        sign = 1.0 if side == "L" else -1.0
        elevate, share = arm.get("elevate", 0.0), arm.get("clavicle", 0.0)
        clavicle = bones.get("Shoulder.%s" % side)
        if clavicle is not None and share:
            _set(clavicle, Matrix.Rotation(math.radians(-sign * elevate * share), 3, "Y"))
        else:
            share = 0.0
        upper = bones.get("UpperArm.%s" % side)
        if upper is not None:
            _set(upper, Matrix.Rotation(math.radians(arm.get("forward", 0.0)), 3, "X")
                 @ Matrix.Rotation(math.radians(-sign * elevate * (1.0 - share)), 3, "Y"))
        fore = bones.get("Forearm.%s" % side)
        if fore is not None and arm.get("bend"):
            along = (fore.bone.matrix_local.to_3x3() @ Vector((0.0, 1.0, 0.0))).normalized()
            axis = along.cross(FRONT).normalized()
            _set(fore, Matrix.Rotation(math.radians(arm["bend"]), 3, axis))
    twist = sample.get("twist", 0.0)
    for name in ("Spine", "Chest"):
        if twist and bones.get(name) is not None:
            _set(bones[name], Matrix.Rotation(math.radians(twist * 0.5), 3, "Z"))
    head = sample.get("head") or {}
    if head:
        from character_modeling.pose_suite import NECK_SHARE
        for name, share in (("Neck", NECK_SHARE), ("Head", 1.0 - NECK_SHARE)):
            if bones.get(name) is not None:
                _set(bones[name], Matrix.Rotation(math.radians(head.get("yaw", 0.0) * share), 3, "Z")
                     @ Matrix.Rotation(math.radians(head.get("pitch", 0.0) * share), 3, "X"))
