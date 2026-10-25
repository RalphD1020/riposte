"""Modeling pose for proportion studies.

This is not WolfRig's rest pose. Combat clips, grip stations, and bone
names stay on the character file. A mesh built here is a preview. Fitting
it to the production bind pose is a later, explicit step.
"""

from __future__ import annotations

import math

# Blender study space. Godot converts this on glTF import; do not rotate
# individual meshes to compensate.
UP = "+Z"
FORWARD = "-Y"
LEFT = "+X"
MIRROR_PLANE = "YZ"
FLOOR_Z = 0.0

# Middle of the usual 30–45° drop from a T-pose. Elbows stay straight so
# every sheet uses one arm convention.
POSE_ID = "relaxed-a-pose"
ARM_DROP_FROM_HORIZONTAL_DEG = 35.0
ARM_DROP_RADIANS = math.radians(ARM_DROP_FROM_HORIZONTAL_DEG)
ELBOWS = "straight"
LEGS = "straight-symmetric"


def a_pose_joints(landmarks, side):
    """Place one side in the modeling pose.

    ``landmarks`` carries widths and segment lengths taken from WolfRig.
    The returned points are offsets from the character origin. They are
    not written back onto the rig.
    """
    if side not in ("L", "R"):
        raise ValueError("side must be L or R")
    sign = 1.0 if side == "L" else -1.0
    required = (
        "shoulder_x", "shoulder_z", "hip_x", "hip_z",
        "upper_arm", "forearm", "hand", "thigh", "shin", "foot",
    )
    missing = [key for key in required if key not in landmarks]
    if missing:
        raise ValueError("landmarks missing %s" % ", ".join(missing))
    arm = (
        math.cos(ARM_DROP_RADIANS) * sign,
        0.0,
        -math.sin(ARM_DROP_RADIANS),
    )
    shoulder = (landmarks["shoulder_x"] * sign, 0.0, landmarks["shoulder_z"])
    elbow = _along(shoulder, arm, landmarks["upper_arm"])
    wrist = _along(elbow, arm, landmarks["forearm"])
    palm = _along(wrist, arm, landmarks["hand"])
    hip = (landmarks["hip_x"] * sign, 0.0, landmarks["hip_z"])
    knee = (hip[0], hip[1], hip[2] - landmarks["thigh"])
    ankle = (knee[0], knee[1], knee[2] - landmarks["shin"])
    toe = (ankle[0], ankle[1] - landmarks["foot"], ankle[2])
    return {
        "shoulder": shoulder,
        "elbow": elbow,
        "wrist": wrist,
        "palm": palm,
        "hip": hip,
        "knee": knee,
        "ankle": ankle,
        "toe": toe,
    }


def _along(origin, direction, distance):
    return tuple(origin[index] + direction[index] * distance for index in range(3))
