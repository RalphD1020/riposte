"""Character-model definitions and diagnostics for studies and, later, a creator.

This module does not build meshes, export GLBs, or read Wolf's character
file. Callers resolve a profile, then a Blender study or a future tool
turns that resolution into geometry. ``diagnostics`` reads a captured mesh
and reports evidence; it never changes geometry.
"""

from . import diagnostics, measurements
from .anatomy import CONTROLS, REGIONS, resolve_controls, validate_controls
from .definition import load_profile, load_studies, resolve, self_check, validate
from .parameters import BY_ID, SLIDERS, UI_IDS
from .pose import ARM_DROP_FROM_HORIZONTAL_DEG, POSE_ID, a_pose_joints

__all__ = (
    "ARM_DROP_FROM_HORIZONTAL_DEG",
    "BY_ID",
    "CONTROLS",
    "POSE_ID",
    "REGIONS",
    "SLIDERS",
    "UI_IDS",
    "a_pose_joints",
    "diagnostics",
    "load_profile",
    "measurements",
    "load_studies",
    "resolve",
    "resolve_controls",
    "self_check",
    "validate",
    "validate_controls",
)
