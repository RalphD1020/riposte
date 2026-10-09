"""Contract checks for Riposte's Blender sources. Each returns a list of
problems; an empty list is a pass. The numbers here restate the physical
baseline the game already owns — a mismatch means the art drifted from the
rules, never that the rules should move.
"""

import bpy
from mathutils import Vector

import riposte_blocks as rb

FIGHTER_BONES = [
    "Root", "Hips", "Spine", "Chest", "Neck", "Head",
    "Shoulder.L", "UpperArm.L", "Forearm.L", "Hand.L",
    "Shoulder.R", "UpperArm.R", "Forearm.R", "Hand.R",
    "UpperLeg.L", "LowerLeg.L", "Foot.L", "UpperLeg.R", "LowerLeg.R", "Foot.R",
]
FIGHTER_MATERIALS = ["fabric", "leather", "metal", "hair", "skin", "side_accent"]
FIGHTER_ACTIONS = [
    "idle", "walk_forward", "walk_backward", "orbit_cw", "orbit_ccw",
    "dash_forward", "run_through", "dash_back", "dash_left", "dash_right",
    "charge_support", "swing_support", "overswing", "recovery",
    "hurt_light", "stagger", "hurt_heavy", "death", "death_stab", "flourish",
]
FIGHTER_TRIANGLES = 2000
FIGHTER_HEIGHT = (1.70, 1.85)
WEAPON_MARKERS = {
    "GripOffhand": 0.15,
    "GripDominant": 0.225,
    "TrailStart": 0.25,
    "TrailEnd": 1.22,
    "Tip": 1.22,
}
WEAPON_TRIANGLES = 400
ARENA_RADIUS = 8.27
ARENA_TRIANGLES = 5000
TOLERANCE = 1e-3
## The fighter's dominant clothing must read against the arena floor at the
## same 3:1 the theme's WORLD_READS hold (UX-001). Linear luminance of the
## floor token #8a7f6c.
FLOOR_LUMINANCE = 0.2126 * 0.2542 + 0.7152 * 0.2122 + 0.0722 * 0.1499
WORLD_READ_MIN = 3.0


def _luminance(mat):
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    r, g, b, _a = bsdf.inputs["Base Color"].default_value
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def _contrast(a, b):
    hi, lo = max(a, b), min(a, b)
    return (hi + 0.05) / (lo + 0.05)


def _meshes():
    return [o for o in bpy.data.objects if o.type == "MESH"]


def _material_names(objects):
    names = set()
    for obj in objects:
        for slot in obj.material_slots:
            if slot.material is not None:
                names.add(slot.material.name)
    return names


def validate_fighter():
    problems = []
    rig = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    if rig is None:
        return ["no armature"]
    bones = {b.name for b in rig.data.bones}
    problems += ["missing bone %s" % b for b in FIGHTER_BONES if b not in bones]
    meshes = _meshes()
    materials = _material_names(meshes)
    problems += ["missing material slot %s" % m for m in FIGHTER_MATERIALS if m not in materials]
    fabric = bpy.data.materials.get("fabric")
    if fabric is not None:
        ratio = _contrast(_luminance(fabric), FLOOR_LUMINANCE)
        if ratio < WORLD_READ_MIN:
            problems.append("fabric reads %.2f:1 against the floor, needs %.1f:1" % (ratio, WORLD_READ_MIN))
    actions = {a.name for a in bpy.data.actions}
    problems += ["missing action %s" % a for a in FIGHTER_ACTIONS if a not in actions]
    for obj in meshes:
        groups = [g.name for g in obj.vertex_groups]
        if len(groups) != 1 or groups[0] not in bones:
            problems.append("%s must be bound rigidly to exactly one bone (has %s)" % (obj.name, groups))
    if not any(o.name.startswith("SideAccent") for o in meshes):
        problems.append("no SideAccent* piece for side affiliation")
    if "Head" not in {o.name for o in meshes}:
        problems.append("no Head (the facing read)")
    tris = rb.triangle_count(meshes)
    if tris > FIGHTER_TRIANGLES:
        problems.append("triangles %d over budget %d" % (tris, FIGHTER_TRIANGLES))
    lo, hi = rb.world_bounds(meshes)
    if not FIGHTER_HEIGHT[0] <= hi.z - lo.z <= FIGHTER_HEIGHT[1]:
        problems.append("height %.3f outside %s" % (hi.z - lo.z, FIGHTER_HEIGHT))
    if abs(lo.z) > 0.02:
        problems.append("feet at %.3f, not on the floor" % lo.z)
    return problems


def validate_weapon():
    problems = []
    for name, distance in WEAPON_MARKERS.items():
        marker = bpy.data.objects.get(name)
        if marker is None or marker.type != "EMPTY":
            problems.append("missing marker %s" % name)
            continue
        at = marker.matrix_world.translation
        if abs(-at.y - distance) > TOLERANCE or abs(at.x) > TOLERANCE or abs(at.z) > TOLERANCE:
            problems.append("%s at %s, expected %.3f m down -Y" % (name, tuple(round(v, 4) for v in at), distance))
    blade = [o for o in _meshes() if o.name.startswith("Blade")]
    if not blade:
        problems.append("no Blade* mesh")
    else:
        lo, _hi = rb.world_bounds(blade)
        if abs(-lo.y - WEAPON_MARKERS["Tip"]) > TOLERANCE:
            problems.append("blade tip at %.4f, expected %.3f" % (-lo.y, WEAPON_MARKERS["Tip"]))
    tris = rb.triangle_count(_meshes())
    if tris > WEAPON_TRIANGLES:
        problems.append("triangles %d over budget %d" % (tris, WEAPON_TRIANGLES))
    return problems


def validate_arena():
    problems = []
    top = bpy.data.objects.get("PlatformTop")
    if top is None:
        return ["no PlatformTop"]
    lo, hi = rb.world_bounds([top])
    radius = max(hi.x, -lo.x, hi.y, -lo.y)
    if abs(radius - ARENA_RADIUS) > TOLERANCE:
        problems.append("platform radius %.4f, rules say %.2f" % (radius, ARENA_RADIUS))
    if abs(hi.z) > TOLERANCE:
        problems.append("platform top at %.4f, expected 0" % hi.z)
    tris = rb.triangle_count(_meshes())
    if tris > ARENA_TRIANGLES:
        problems.append("triangles %d over budget %d" % (tris, ARENA_TRIANGLES))
    return problems


VALIDATORS = {"fighter": validate_fighter, "weapon": validate_weapon, "arena": validate_arena}


def manifest(asset_id, kind):
    meshes = _meshes()
    lo, hi = rb.world_bounds(meshes)
    rig = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    return {
        "asset_id": asset_id,
        "kind": kind,
        "version": 1,
        "bounds": {"min": [round(v, 4) for v in lo], "max": [round(v, 4) for v in hi]},
        "bone_names": [b.name for b in rig.data.bones] if rig else [],
        "animation_names": sorted(a.name for a in bpy.data.actions),
        "attachment_names": sorted(o.name for o in bpy.data.objects if o.type == "EMPTY"),
        "material_slots": sorted(_material_names(meshes)),
        "triangle_count": rb.triangle_count(meshes),
        "color_targets": sorted(o.name for o in meshes if o.name.startswith("SideAccent")),
    }
