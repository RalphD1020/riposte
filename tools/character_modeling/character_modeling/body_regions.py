"""The body's two authoring region views and their one vocabulary (CHARACTER-REGIONS-001).

How the body is shaped and how it moves are different questions, so the body has two region
views on the one production topology, both tied to the one rig contract and neither of them a
bone:

- **Deformation / fitting regions** (`DEFORMATION_REGIONS`): where the body deforms around
  which bones, where garments attach and what coverage hides. The segment regions are what
  `fitting_regions.py` writes per topology (`fitting_table`); the joint bands are the
  transitions deformation QA judges (elbow, wrist, hip, knee, ankle). A region lists the bones
  that may move it; the skin weights themselves stay the rig's deform vertex groups.
- **Muscle / shape regions** (`SHAPE_GROUPS`): the visible masses that carry the heroic
  physique (pectorals, deltoids, lats, glutes, quadriceps...), overlapping and smoothly
  weighted, each saying where the physique inputs reshape the mesh. They never carry bones or
  skin weights, and they are authoring groups, not anatomical taxonomy.

Layer A, the structural anatomy (`STRUCTURES`: rib cage, girdle, pelvis, limb segments...),
sets what a muscle attaches to; its joints come from `physique.py`, never from a mask.

In the Blender source a shape mask is `shape.<id>` and a fitting region `fit.<id>` (point
attributes or non-deforming vertex groups); bone names stay the deform groups. None of this
is exported to Godot: physique configurations are baked offline.

Every older name for the same area is an explicit alias (`ALIASES`), so `anatomy.py`'s
creation regions, `rig_regions.py` and the fitting tools can never mean different things by
`upper_arm` or `thigh`. Pure Python: no Blender.
"""

from __future__ import annotations

KIND = "body_regions"
SIDES = ("L", "R")
SHAPE_MASK_PREFIX = "shape."
FIT_MASK_PREFIX = "fit."

## The physique parameters a region responds to: the master's configuration parameters
## (`male_base.configuration.json`), never new sliders.
PHYSIQUE_PARAMETERS = ("mass", "definition", "upper_body", "chest", "shoulders", "waist", "arms", "legs")

## Segment regions, in the order the fitting records are written (centre, then the left
## side, then the right). id: (dominant bone families, bones that may influence it, physique
## parameters, neighbours, stressing clips). `{s}` is the side. This table is the one
## definition `fitting_regions.py` derives every fitting record from.
_CENTRE = (
    ## The head is its own object (HeadV2); the neck rings below it ride Neck and Head.
    ("head", (), ("Head",), (), ("neck",), ("idle", "death")),
    ("neck", ("Neck", "Head"), ("Neck", "Head", "Chest"), ("mass", "shoulders"), ("head", "upper_torso", "shoulder.L", "shoulder.R"), ("idle", "charge_support", "death")),
    ("upper_torso", ("Chest",), ("Chest", "Spine", "Shoulder.L", "Shoulder.R", "Neck"), ("mass", "chest", "upper_body", "definition"), ("neck", "shoulder.L", "shoulder.R", "waist"), ("charge_support", "swing_support", "overswing", "dash_forward")),
    ("waist", ("Spine",), ("Spine", "Chest", "Hips"), ("mass", "waist", "definition"), ("upper_torso", "pelvis"), ("dash_forward", "walk_forward", "death")),
    ("pelvis", ("Hips",), ("Hips", "Spine", "UpperLeg.L", "UpperLeg.R"), ("mass",), ("waist", "upper_leg.L", "upper_leg.R"), ("walk_forward", "dash_forward", "death")),
)
_SIDED = (
    ## The shoulder has no dominant family: it is every vertex the clavicle moves.
    ("shoulder", (), ("Shoulder.{s}", "Chest", "UpperArm.{s}"), ("mass", "shoulders", "upper_body"), ("upper_torso", "neck", "upper_arm.{s}"), ("charge_support", "swing_support", "overswing")),
    ("upper_arm", ("UpperArm.{s}",), ("UpperArm.{s}", "Shoulder.{s}", "Forearm.{s}"), ("mass", "arms", "upper_body"), ("shoulder.{s}", "forearm.{s}"), ("charge_support", "swing_support", "overswing")),
    ("forearm", ("Forearm.{s}",), ("Forearm.{s}", "UpperArm.{s}", "Hand.{s}"), ("mass", "arms"), ("upper_arm.{s}", "hand.{s}"), ("charge_support", "swing_support")),
    ("hand", ("Hand.{s}",), ("Hand.{s}", "Forearm.{s}"), (), ("forearm.{s}",), ("charge_support",)),
    ("upper_leg", ("UpperLeg.{s}",), ("UpperLeg.{s}", "Hips", "LowerLeg.{s}"), ("mass", "legs"), ("pelvis", "lower_leg.{s}"), ("walk_forward", "dash_forward", "death")),
    ("lower_leg", ("LowerLeg.{s}",), ("LowerLeg.{s}", "UpperLeg.{s}", "Foot.{s}"), ("mass", "legs"), ("upper_leg.{s}", "foot.{s}"), ("walk_forward", "dash_forward")),
    ("foot", ("Foot.{s}",), ("Foot.{s}", "LowerLeg.{s}"), (), ("lower_leg.{s}",), ("walk_forward",)),
)
SEGMENT_REGIONS = tuple(row[0] for row in _CENTRE + _SIDED)

## Joint bands: the transitions between two segments, judged in deformation QA on the
## runtime's final poses (the clips alone are not the envelope). id: (the two segments it
## joins, the bones it bends between, the runtime states that stress it). Not written into
## the fitting records; on a production topology they are `fit.<id>` selections.
JOINT_BANDS = {
    "elbow": (("upper_arm", "forearm"), ("UpperArm.{s}", "Forearm.{s}"), ("guard", "cut", "death")),
    "wrist": (("forearm", "hand"), ("Forearm.{s}", "Hand.{s}"), ("guard", "cut", "grip")),
    "hip": (("pelvis", "upper_leg"), ("Hips", "UpperLeg.{s}"), ("lunge", "death", "ring_fall")),
    "knee": (("upper_leg", "lower_leg"), ("UpperLeg.{s}", "LowerLeg.{s}"), ("lunge", "death", "dash")),
    "ankle": (("lower_leg", "foot"), ("LowerLeg.{s}", "Foot.{s}"), ("walk", "dash", "death")),
}
DEFORMATION_REGIONS = SEGMENT_REGIONS + tuple(JOINT_BANDS)
SIDED_REGIONS = frozenset(row[0] for row in _SIDED) | frozenset(JOINT_BANDS)

## Layer A: the structures muscles attach to. Their joints and lengths are `physique.py`'s.
STRUCTURES = ("rib_cage", "spine", "shoulder_girdle", "pelvis", "arm_segments", "leg_segments", "neck_head")

## Layer B: the muscle / shape groups. id: (structures it sits on, deformation regions it
## spans, neighbouring shape groups, physique parameters that reshape it, detail priority).
## Priority "primary" is where the silhouette lives and detail is spent first.
SHAPE_GROUPS = {
    "trapezius": (("shoulder_girdle", "spine", "neck_head"), ("neck", "upper_torso", "shoulder"), ("deltoids", "lats"), ("mass", "shoulders", "upper_body", "definition"), "secondary"),
    "pectorals": (("rib_cage", "shoulder_girdle"), ("upper_torso", "shoulder"), ("deltoids", "abdominals", "lats"), ("mass", "chest", "upper_body", "definition"), "primary"),
    "lats": (("rib_cage", "spine", "shoulder_girdle"), ("upper_torso", "waist", "shoulder"), ("trapezius", "pectorals", "obliques", "deltoids"), ("mass", "upper_body", "definition"), "primary"),
    "abdominals": (("rib_cage", "spine", "pelvis"), ("upper_torso", "waist"), ("pectorals", "obliques"), ("mass", "waist", "definition"), "secondary"),
    "obliques": (("rib_cage", "pelvis"), ("waist", "pelvis"), ("abdominals", "lats", "gluteals"), ("mass", "waist", "definition"), "secondary"),
    "deltoids": (("shoulder_girdle",), ("shoulder", "upper_arm"), ("pectorals", "trapezius", "lats", "biceps_brachialis", "triceps"), ("mass", "shoulders", "upper_body", "definition"), "primary"),
    "biceps_brachialis": (("arm_segments",), ("upper_arm", "elbow"), ("deltoids", "triceps", "forearm_flexors", "forearm_extensors"), ("mass", "arms", "definition"), "primary"),
    "triceps": (("arm_segments",), ("upper_arm", "elbow"), ("deltoids", "biceps_brachialis", "forearm_extensors"), ("mass", "arms", "definition"), "primary"),
    "forearm_flexors": (("arm_segments",), ("forearm", "elbow", "wrist"), ("biceps_brachialis", "forearm_extensors"), ("mass", "arms"), "secondary"),
    "forearm_extensors": (("arm_segments",), ("forearm", "elbow", "wrist"), ("biceps_brachialis", "triceps", "forearm_flexors"), ("mass", "arms"), "secondary"),
    "gluteals": (("pelvis",), ("pelvis", "hip"), ("obliques", "quadriceps", "hamstrings_adductors"), ("mass", "legs", "definition"), "primary"),
    "quadriceps": (("leg_segments", "pelvis"), ("upper_leg", "hip", "knee"), ("gluteals", "hamstrings_adductors", "tibialis_anterior"), ("mass", "legs", "definition"), "primary"),
    "hamstrings_adductors": (("leg_segments", "pelvis"), ("upper_leg", "hip", "knee"), ("gluteals", "quadriceps", "gastrocnemius_soleus"), ("mass", "legs"), "secondary"),
    "gastrocnemius_soleus": (("leg_segments",), ("lower_leg", "knee", "ankle"), ("hamstrings_adductors", "tibialis_anterior"), ("mass", "legs", "definition"), "primary"),
    "tibialis_anterior": (("leg_segments",), ("lower_leg", "ankle"), ("quadriceps", "gastrocnemius_soleus"), ("mass", "legs"), "secondary"),
}
SHAPE_GROUP_IDS = tuple(SHAPE_GROUPS)

## Older names for the same area -> the canonical region. `anatomy.REGIONS` (the v1 creation
## regions) and `rig_regions` names; a descriptive muscle word is never a deformation id.
ALIASES = {
    "head_face": "head", "head_crown": "head", "head_jaw": "head",
    "chest": "upper_torso", "back_upper": "upper_torso",
    "abdomen": "waist", "back_lower": "waist",
    "glute": "pelvis",
    "thigh": "upper_leg", "calf": "lower_leg",
}


def canonical(name):
    """The canonical deformation region of `name` (a region id, `.L`/`.R` kept, or an alias).
    Raises on an unknown name so a typo never silently falls out of a region."""
    base, side = (name[:-2], name[-2:]) if name[-2:] in (".L", ".R") else (name, "")
    base = ALIASES.get(base, base)
    if base not in DEFORMATION_REGIONS:
        raise KeyError("body_regions: unknown region %r (known: %s; aliases: %s)" % (
            name, ", ".join(DEFORMATION_REGIONS), ", ".join(sorted(ALIASES))))
    if side and base not in SIDED_REGIONS:
        raise KeyError("body_regions: %r is a centre region and has no side" % name)
    return base + side


def shape_mask(group):
    """The Blender source's mask name for shape group `group` (e.g. `shape.pectorals`)."""
    if group not in SHAPE_GROUPS:
        raise KeyError("body_regions: unknown shape group %r" % group)
    return SHAPE_MASK_PREFIX + group


def fit_mask(region):
    """The Blender source's selection name for a deformation region (e.g. `fit.upper_arm.L`)."""
    return FIT_MASK_PREFIX + canonical(region)


def _expand(value, side):
    return tuple(item.format(s=side) for item in value)


def fitting_table():
    """{region id: (dominant families, bones, physique, neighbours, clips)} for every segment
    region, sides expanded, in the order the fitting records are written."""
    table = {row[0]: row[1:] for row in _CENTRE}
    for side in SIDES:
        for region, *spec in _SIDED:
            table["%s.%s" % (region, side)] = tuple(_expand(value, side) for value in spec)
    return table


def problems():
    """What is inconsistent in the vocabulary itself (empty when sound)."""
    out = []
    segments = set(SEGMENT_REGIONS)
    for alias, target in ALIASES.items():
        if alias in DEFORMATION_REGIONS:
            out.append("alias %s shadows a canonical region" % alias)
        if target not in DEFORMATION_REGIONS:
            out.append("alias %s points at unknown region %s" % (alias, target))
    for band, (joins, _bones, _states) in JOINT_BANDS.items():
        out += ["joint band %s joins unknown segment %s" % (band, s) for s in joins if s not in segments]
    for group, (structures, regions, neighbours, physique, priority) in SHAPE_GROUPS.items():
        out += ["shape group %s sits on unknown structure %s" % (group, s) for s in structures if s not in STRUCTURES]
        out += ["shape group %s spans unknown region %s" % (group, r) for r in regions if r not in DEFORMATION_REGIONS]
        out += ["shape group %s reads unknown parameter %s" % (group, p) for p in physique if p not in PHYSIQUE_PARAMETERS]
        for other in neighbours:
            if other not in SHAPE_GROUPS:
                out.append("shape group %s neighbours unknown group %s" % (group, other))
            elif group not in SHAPE_GROUPS[other][2]:
                out.append("shape groups %s and %s are not mutual neighbours" % (group, other))
        if priority not in ("primary", "secondary"):
            out.append("shape group %s has priority %r" % (group, priority))
    for region in fitting_table().values():
        for physique in region[2]:
            if physique not in PHYSIQUE_PARAMETERS:
                out.append("fitting region reads unknown parameter %s" % physique)
    return out
