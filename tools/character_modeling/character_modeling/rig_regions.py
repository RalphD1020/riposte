"""Anatomical regions of the rig's deform groups (one table, never substring matching).

Every deform vertex group (a bone of the shared rig, `.L` / `.R` mirrored) belongs to one
region; the body systems ask for regions (the arm, the leg), never for names. An unknown
group is an error, so a renamed bone fails loudly instead of silently dropping out of a
region (the way a case-sensitive "Arm" match once missed every forearm). Region ids are the
canonical deformation regions of `body_regions` (CHARACTER-REGIONS-001); `root` and `prop`
are the two non-body bones.

Pure Python: no Blender.
"""

from __future__ import annotations

from . import body_regions

KIND = "rig_regions"
NON_BODY = ("root", "prop")
REGION = {
    "Root": "root", "SwordMount": "prop", "Hips": "pelvis", "Spine": "waist", "Chest": "upper_torso", "Neck": "neck",
    "Head": "head", "Shoulder": "shoulder", "UpperArm": "upper_arm", "Forearm": "forearm", "Hand": "hand",
    "UpperLeg": "upper_leg", "LowerLeg": "lower_leg", "Foot": "foot",
}
TORSO = ("upper_torso", "waist")
ARM = ("upper_arm", "forearm", "hand")
LEG = ("upper_leg", "lower_leg", "foot")
SIDES = (".L", ".R")

_STRAY = sorted(r for r in REGION.values() if r not in NON_BODY and r not in body_regions.SEGMENT_REGIONS)
if _STRAY:
    raise ImportError("rig_regions: regions %s are not canonical body_regions segments" % _STRAY)


def region_of(group):
    """The region of deform group `group` (exact bone name, `.L` / `.R` stripped)."""
    base = group[:-2] if group.endswith(SIDES) else group
    if base not in REGION:
        raise KeyError("rig_regions: unknown deform group %r (known: %s)" % (group, ", ".join(sorted(REGION))))
    return REGION[base]


def in_regions(group, regions):
    """Whether `group` belongs to one of `regions` (canonical ids or `body_regions` aliases)."""
    wanted = {r if r in NON_BODY else body_regions.canonical(r) for r in regions}
    return region_of(group) in wanted
