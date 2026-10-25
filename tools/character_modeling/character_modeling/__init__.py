"""Character-model definitions for studies and, later, a creator.

This module does not build meshes, export GLBs, or read Wolf's character
file. Callers resolve a profile, then a Blender study or a future tool
turns that resolution into geometry.
"""

from .definition import load_profile, load_studies, resolve, self_check, validate
from .parameters import BY_ID, SLIDERS, UI_IDS
from .pose import ARM_DROP_FROM_HORIZONTAL_DEG, POSE_ID, a_pose_joints

__all__ = (
    "ARM_DROP_FROM_HORIZONTAL_DEG",
    "BY_ID",
    "POSE_ID",
    "SLIDERS",
    "UI_IDS",
    "a_pose_joints",
    "load_profile",
    "load_studies",
    "resolve",
    "self_check",
    "validate",
)
