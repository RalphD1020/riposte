"""Anatomical regions of the rig's deform groups (one table, never substring matching).

Every deform vertex group (a bone of the shared rig, `.L` / `.R` mirrored) belongs to one
region; the body systems ask for regions (the arm, the leg), never for names. An unknown
group is an error, so a renamed bone fails loudly instead of silently dropping out of a
region (the way a case-sensitive "Arm" match once missed every forearm).

Pure Python: no Blender.
"""

from __future__ import annotations

KIND = "rig_regions"
REGION = {
    "Root": "root", "SwordMount": "prop", "Hips": "pelvis", "Spine": "torso", "Chest": "torso", "Neck": "neck",
    "Head": "head", "Shoulder": "shoulder", "UpperArm": "upper_arm", "Forearm": "forearm", "Hand": "hand",
    "UpperLeg": "thigh", "LowerLeg": "calf", "Foot": "foot",
}
ARM = ("upper_arm", "forearm", "hand")
LEG = ("thigh", "calf", "foot")
SIDES = (".L", ".R")


def region_of(group):
    """The region of deform group `group` (exact bone name, `.L` / `.R` stripped)."""
    base = group[:-2] if group.endswith(SIDES) else group
    if base not in REGION:
        raise KeyError("rig_regions: unknown deform group %r (known: %s)" % (group, ", ".join(sorted(REGION))))
    return REGION[base]


def in_regions(group, regions):
    """Whether `group` belongs to one of `regions`."""
    return region_of(group) in regions
