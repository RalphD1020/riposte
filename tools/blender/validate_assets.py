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
    "SwordMount",
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
    "victory_combo", "victory_idle", "ring_fall_a", "ring_fall_b", "ring_fall_c",
]
## Cinematic clips that carry the display sword on SwordMount.
FIGHTER_SWORD_CLIPS = ["victory_combo", "victory_idle"]
## PRES-STANCE-001: the right foot leads by at least this much (m, along the
## facing −Y) in the rest skeleton and through every live-footwork clip.
LEAD_MIN_REST = 0.06
LEAD_CLIPS = ["idle", "walk_forward", "walk_backward", "orbit_cw", "orbit_ccw", "dash_forward", "dash_back", "dash_left", "dash_right"]
## PRES-LOCO-001: support clips move only the upper body; below the spine they
## hold the idle stance exactly, so a stationary charge is idle legs under a
## charged torso and footwork always comes from movement.
SUPPORT_CLIPS = ["charge_support", "swing_support", "overswing", "recovery"]
STANCE_BONES = ["Hips", "UpperLeg.L", "LowerLeg.L", "Foot.L", "UpperLeg.R", "LowerLeg.R", "Foot.R"]
## PRES-TERMINAL-001: a ring fall raises a hand above its shoulder within
## ~0.25 s (frame 16 at 60 fps).
RING_FALL_CLIPS = ["ring_fall_a", "ring_fall_b", "ring_fall_c"]
RING_FALL_ARMS_UP_BY = 16
## The layered costume (bib, harness, fur tufts, pauldron, knee caps, boot toes, hair locks) is past the old 2000.
## 2400 is the hero's cap. The crowd stays on its own budget.
FIGHTER_TRIANGLES = 2400
FIGHTER_HEIGHT = (1.70, 1.85)
## The usable handle and the hands on it mirror PhysicalBaseline
## (POMMEL_SHOULDER_M, GUARD_UNDERSIDE_M, GRIP_*_M): off hand just above the
## pommel, dominant hand just under the guard, both on the handle.
POMMEL_SHOULDER = 0.030
GUARD_UNDERSIDE = 0.2315
HAND_HALF_WIDTH = 0.035
WEAPON_MARKERS = {
    "GripOffhand": POMMEL_SHOULDER + HAND_HALF_WIDTH + 0.005,
    "GripDominant": GUARD_UNDERSIDE - HAND_HALF_WIDTH - 0.010,
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


def _keys_bone(act, bone_name):
    """True when the action keys `bone_name` (layered or legacy fcurves)."""
    marker = 'pose.bones["%s"]' % bone_name
    curves = list(getattr(act, "fcurves", []) or [])
    for layer in getattr(act, "layers", []) or []:
        for strip in layer.strips:
            for bag in getattr(strip, "channelbags", []) or []:
                curves += list(bag.fcurves)
    return any(c.data_path.startswith(marker) for c in curves)


def _pose_at(rig, act, frame):
    """Evaluate `act` on `rig` at `frame`; returns the pose bones (armature
    space). `act` None evaluates the rest pose."""
    rig.animation_data_create()
    rig.animation_data.action = act
    if act is not None and hasattr(rig.animation_data, "action_slot") and getattr(act, "slots", None):
        rig.animation_data.action_slot = act.slots[0]
    if act is None:
        for pose_bone in rig.pose.bones:
            pose_bone.rotation_euler = (0, 0, 0)
            pose_bone.rotation_quaternion = (1, 0, 0, 0)
            pose_bone.location = (0, 0, 0)
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()
    return rig.pose.bones


def _lead(bones):
    return bones["Foot.L"].head.y - bones["Foot.R"].head.y


def _frames(act):
    start, end = (int(v) for v in act.frame_range)
    return range(start, end + 1)


def validate_motion(rig):
    """The footwork, support, and ring-fall contracts, measured on the posed
    skeleton rather than read from authoring constants."""
    problems = []
    if _lead(_pose_at(rig, None, 1)) < LEAD_MIN_REST:
        problems.append("rest skeleton must stand right foot forward by %.2f m" % LEAD_MIN_REST)
    for name in LEAD_CLIPS:
        act = bpy.data.actions.get(name)
        if act is None:
            continue
        worst = min(_lead(_pose_at(rig, act, f)) for f in _frames(act))
        if worst <= 0.0:
            problems.append("%s lets the right foot fall behind (lead %.3f m)" % (name, worst))
    idle = bpy.data.actions.get("idle")
    if idle is not None:
        stance = {b: _pose_at(rig, idle, 1)[b].matrix.copy() for b in STANCE_BONES}
        for name in SUPPORT_CLIPS:
            act = bpy.data.actions.get(name)
            if act is None:
                continue
            for f in _frames(act):
                bones = _pose_at(rig, act, f)
                moved = [b for b in STANCE_BONES if (bones[b].matrix.translation - stance[b].translation).length > 1e-4 or bones[b].matrix.to_quaternion().rotation_difference(stance[b].to_quaternion()).angle > 1e-3]
                if moved:
                    problems.append("%s moves the stance (%s) at frame %d — support clips move only the upper body" % (name, ", ".join(moved), f))
                    break
    for name in RING_FALL_CLIPS:
        act = bpy.data.actions.get(name)
        if act is None:
            continue
        raised = False
        for f in range(1, RING_FALL_ARMS_UP_BY + 1):
            bones = _pose_at(rig, act, f)
            if any(bones["Hand." + t].tail.z > bones["Shoulder." + t].tail.z for t in ("L", "R")):
                raised = True
                break
        if not raised:
            problems.append("%s must raise a hand above the shoulder by frame %d" % (name, RING_FALL_ARMS_UP_BY))
    for act in bpy.data.actions:
        if _keys_bone(act, "Root"):
            problems.append("%s keys Root — no root motion; the presentation root owns travel" % act.name)
    _pose_at(rig, None, 1)
    return problems


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
    for name in FIGHTER_SWORD_CLIPS:
        act = bpy.data.actions.get(name)
        if act is not None and not _keys_bone(act, "SwordMount"):
            problems.append("%s must carry the display sword on SwordMount" % name)
    for obj in meshes:
        groups = [g.name for g in obj.vertex_groups]
        if len(groups) != 1 or groups[0] not in bones:
            problems.append("%s must be bound rigidly to exactly one bone (has %s)" % (obj.name, groups))
    if not any(o.name.startswith("SideAccent") for o in meshes):
        problems.append("no SideAccent* piece for side affiliation")
    if "HeadSkin" not in {o.name for o in meshes}:
        problems.append("no HeadSkin (the facing read)")
    ## glTF puts objects and bones in one node namespace and Godot renames a
    ## clashing bone on import (Head -> Head_2), so every by-name bone lookup
    ## — the kinetic chain, the head clearance proxy — would silently miss.
    ## Godot node names cannot hold ".", so only an undotted name can clash.
    problems += ["object %s shares a bone's name" % o.name for o in bpy.data.objects if o.name in bones and "." not in o.name and o.type != "ARMATURE"]
    tris = rb.triangle_count(meshes)
    if tris > FIGHTER_TRIANGLES:
        problems.append("triangles %d over budget %d" % (tris, FIGHTER_TRIANGLES))
    lo, hi = rb.world_bounds(meshes)
    if not FIGHTER_HEIGHT[0] <= hi.z - lo.z <= FIGHTER_HEIGHT[1]:
        problems.append("height %.3f outside %s" % (hi.z - lo.z, FIGHTER_HEIGHT))
    if abs(lo.z) > 0.02:
        problems.append("feet at %.3f, not on the floor" % lo.z)
    problems += validate_motion(rig)
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
    problems += _validate_hilt()
    tris = rb.triangle_count(_meshes())
    if tris > WEAPON_TRIANGLES:
        problems.append("triangles %d over budget %d" % (tris, WEAPON_TRIANGLES))
    return problems


def _validate_hilt():
    """The handle the grip markers were derived from is the handle modelled:
    pommel shoulder and guard underside where the baseline says, and every
    guard part (core, quillons, caps) at the guard rather than elsewhere."""
    problems = []
    pommel = bpy.data.objects.get("Pommel")
    if pommel is None:
        return ["no Pommel mesh"]
    shoulder, _top = rb.world_bounds([pommel])
    if abs(-shoulder.y - POMMEL_SHOULDER) > TOLERANCE:
        problems.append("pommel shoulder at %.4f, expected %.4f" % (-shoulder.y, POMMEL_SHOULDER))
    bars = [o for o in _meshes() if o.name in ("GuardCore", "QuillonL", "QuillonR")]
    if len(bars) != 3:
        return problems + ["guard needs GuardCore, QuillonL and QuillonR"]
    lo, hi = rb.world_bounds(bars)
    if abs(-hi.y - GUARD_UNDERSIDE) > TOLERANCE:
        problems.append("guard underside at %.4f, expected %.4f" % (-hi.y, GUARD_UNDERSIDE))
    centre = -(lo.y + hi.y) * 0.5
    for cap in [o for o in _meshes() if o.name.startswith("QuillonCap")]:
        cap_lo, cap_hi = rb.world_bounds([cap])
        if abs(-(cap_lo.y + cap_hi.y) * 0.5 - centre) > TOLERANCE:
            problems.append("%s at %.4f, not on the guard (%.4f)" % (cap.name, -(cap_lo.y + cap_hi.y) * 0.5, centre))
    if not WEAPON_MARKERS["GripOffhand"] - HAND_HALF_WIDTH >= POMMEL_SHOULDER - TOLERANCE:
        problems.append("off hand overlaps the pommel")
    if not WEAPON_MARKERS["GripDominant"] + HAND_HALF_WIDTH <= GUARD_UNDERSIDE + TOLERANCE:
        problems.append("dominant hand overlaps the guard")
    if not WEAPON_MARKERS["GripDominant"] - WEAPON_MARKERS["GripOffhand"] > 2.0 * HAND_HALF_WIDTH:
        problems.append("the hands overlap each other")
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


def validate_board():
    names = {mat.name for mat in bpy.data.materials}
    problems = []
    for role_name in ("stone_pillar", "stone_edge", "stone_cliff", "stone_terracotta", "gold_trim", "basin_water", "stone_floor"):
        if role_name not in names:
            problems.append("missing %s" % role_name)
    return problems


def _layout():
    import arena_layout
    return arena_layout.load()


def _world_vertices():
    bpy.context.view_layer.update()
    for obj in _meshes():
        matrix = obj.matrix_world
        for vert in obj.data.vertices:
            yield matrix @ vert.co


def _validate_pit(layout):
    """The sand stays clear. The wall and the seats stay outside the disc.
    The gates may rise through the wall. Nothing clears the top tread.
    """
    import math
    problems = []
    disc = layout["expected_disc_radius"]
    top = layout["tiers"][-1]["tread_height"]
    names = _material_names(_meshes())
    if "stone_stand" not in names:
        problems.append("missing stone_stand")
    if "basin_water" in names:
        problems.append("the pit has no water")
    for point in _world_vertices():
        radius = math.hypot(point.x, point.y)
        if radius <= disc + 0.02 and point.z > 0.02:
            problems.append("fighting volume blocked at r %.3f z %.3f" % (radius, point.z))
            break
        if point.z > top + 0.35:
            problems.append("stone above the top tread (z %.3f)" % point.z)
            break
    problems.extend(_pit_doors(layout))
    return problems


def _pit_doors(layout):
    """Inner-course stone beside each door, none in the opening or the wood.

    The flat gate bays face north and south. Their inner face is the plane
    |y| = inner_radius + 0.08. The door width runs along X. A vertex on the
    outer course cannot satisfy the jamb, and a vertex inside the wood fails.
    """
    import math
    gate = layout["gates"]
    inner = layout["wall"]["inner_radius"] + 0.08
    half = gate["width"] * 0.5
    face = inner + 0.05
    side = half + 0.08
    band_hi = inner + 0.45
    bpy.context.view_layer.update()
    stone = []
    gates = []
    for obj in _meshes():
        matrix = obj.matrix_world
        if obj.name in ("GateNorth", "GateSouth"):
            gates.append(obj)
            continue
        for vert in obj.data.vertices:
            point = matrix @ vert.co
            if math.hypot(point.x, point.y) > band_hi:
                continue
            if point.z <= 0.15 or point.z >= gate["height"] - 0.15:
                continue
            stone.append(point)
    problems = []
    if len(gates) != 2:
        problems.append("the pit needs both doors")
    for sign in (1.0, -1.0):
        y = sign * face
        for x_sign in (1.0, -1.0):
            nearest = _nearest(stone, (x_sign * side, y, 0.8))
            if nearest > 0.20:
                problems.append("inner course missing beside the door at (%.2f, %.2f), nearest %.2f" % (x_sign * side, y, nearest))
    buried = 0
    for point in stone:
        if abs(point.x) >= half - 0.05:
            continue
        if inner + 0.03 < abs(point.y) < inner + gate["depth"] - 0.03:
            buried += 1
            break
    if buried:
        problems.append("stone inside the door recess")
    disc = layout["expected_disc_radius"]
    for obj in gates:
        matrix = obj.matrix_world
        coords = [matrix @ vert.co for vert in obj.data.vertices]
        if not coords:
            problems.append("%s has no vertices" % obj.name)
            continue
        if min(math.hypot(point.x, point.y) for point in coords) < disc + 0.02:
            problems.append("%s crosses the combat disc" % obj.name)
        inset = 0.04
        lo_x = min(point.x for point in coords) + inset
        hi_x = max(point.x for point in coords) - inset
        lo_y = min(point.y for point in coords) + inset
        hi_y = max(point.y for point in coords) - inset
        lo_z = min(point.z for point in coords) + inset
        hi_z = max(point.z for point in coords) - inset
        for point in stone:
            if lo_x < point.x < hi_x and lo_y < point.y < hi_y and lo_z < point.z < hi_z:
                problems.append("stone inside %s" % obj.name)
                break
    found = {1.0: False, -1.0: False}
    depth = gate["depth"]
    for obj in _meshes():
        if obj.name in ("GateNorth", "GateSouth"):
            continue
        matrix = obj.matrix_world
        for poly in obj.data.polygons:
            center = matrix @ poly.center
            if abs(abs(center.x) - half) > 0.08:
                continue
            if not (inner - 0.05 < abs(center.y) < inner + depth + 0.08):
                continue
            if not (0.3 < center.z < 1.3):
                continue
            normal = (matrix.to_3x3() @ poly.normal).normalized()
            if abs(normal.x) < 0.85:
                continue
            toward = center.x * normal.x
            if toward < -0.4:
                found[1.0 if center.x > 0.0 else -1.0] = True
            elif toward > 0.4:
                problems.append("jamb face points into the stone at x %.2f" % center.x)
                return problems[:8]
            if len(problems) >= 8:
                return problems
    if not found[1.0] or not found[-1.0]:
        problems.append("no jamb face on both sides of the doors")
    return problems[:8]


def _nearest(points, at):
    import math
    nearest = 1000.0
    for point in points:
        nearest = min(nearest, math.dist(at, (point.x, point.y, point.z)))
    return nearest


def validate_bowl():
    """Fighting volume, not a blanket outside-the-disc test.

    Supports under the floor may sit inside the combat radius when they stay
    below the fighting surface. Arch crowns stay under the soffit. Treads
    stay outside the disc. Water is not a collider here; the mesh just has
    to cover the ground under both arcades, out to the outer tread.
    """
    import math
    problems = []
    if bpy.data.objects.get("PlatformTop") is not None:
        problems.append("the bowl must not carry PlatformTop")
    layout = _layout()
    if layout.get("kind") == "pit":
        return _validate_pit(layout)
    disc = layout["expected_disc_radius"]
    soffit = layout["floor"]["soffit"]
    outer_inner = layout["outer_arcade"]["inner_radius"]
    top = layout["tiers"][-1]["tread_height"]
    first = layout["tiers"][0]["tread_height"]
    second = layout["tiers"][1]["inner_radius"]
    names = _material_names(_meshes())
    if "basin_water" not in names:
        problems.append("missing basin_water")
    for point in _world_vertices():
        radius = math.hypot(point.x, point.y)
        if radius <= disc + 0.05 and point.z > 0.02:
            problems.append("fighting volume blocked at r %.3f z %.3f" % (radius, point.z))
            break
        if radius < outer_inner - 0.05 and point.z > soffit + 0.05:
            problems.append("crown or deck above the soffit at r %.3f z %.3f" % (radius, point.z))
            break
        if point.z > first + 0.05 and radius < second - 0.08:
            problems.append("upper tread reaches into the first row at r %.3f" % radius)
            break
        if point.z > top + 0.05:
            problems.append("stone above the top tread (z %.3f)" % point.z)
            break
    return problems


def validate_floor():
    """Nothing solid on the floor stands above the fighting plane."""
    import math
    problems = []
    if bpy.data.objects.get("PlatformTop") is not None:
        problems.append("the floor asset must not carry PlatformTop")
    layout = _layout()
    floor = layout["floor"]
    disc = layout["expected_disc_radius"]
    names = _material_names(_meshes())
    for role_name in ("stone_floor", "stone_cliff"):
        if role_name not in names:
            problems.append("missing %s" % role_name)
    reached = 0.0
    rim = 0
    lo_x = math.inf
    hi_x = -math.inf
    lo_y = math.inf
    hi_y = -math.inf
    for point in _world_vertices():
        radius = math.hypot(point.x, point.y)
        reached = max(reached, radius)
        lo_x, hi_x = min(lo_x, point.x), max(hi_x, point.x)
        lo_y, hi_y = min(lo_y, point.y), max(hi_y, point.y)
        if radius <= disc + 0.02 and point.z > floor["paving_top"] + 0.004:
            problems.append("floor rises above the paving (z %.3f)" % point.z)
            break
        if radius >= floor["curb_mid_radius"] and point.z <= floor["paving_top"] + 0.004:
            rim += 1
    if reached < disc - 0.05 or reached > disc + 0.08:
        problems.append("floor radius %.3f, disc is %.2f" % (reached, disc))
    if abs(lo_x + hi_x) > 0.05 or abs(lo_y + hi_y) > 0.05:
        problems.append("floor is not centred")
    if rim < 8:
        problems.append("the paving does not reach the rim")
    return problems


def validate_crowd():
    names = {obj.name for obj in _meshes()}
    if names & {"hair", "face"} or ({"skin", "fabric"} <= names):
        return []
    return ["crowd mesh needs skin and fabric, or hair"]


def _emission_strength(mat_name):
    mat = bpy.data.materials.get(mat_name)
    if mat is None or mat.node_tree is None:
        return 0.0
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None or "Emission Strength" not in bsdf.inputs:
        return 0.0
    return bsdf.inputs["Emission Strength"].default_value


def validate_deck():
    problems = []
    names = {o.name for o in bpy.data.objects}
    for required in ("Top", "Edge", "Underside", "Orb"):
        if required not in names:
            problems.append("missing %s" % required)
    if problems:
        return problems
    top = bpy.data.objects.get("Top")
    lo, hi = rb.world_bounds([top])
    radius = max(hi.x, -lo.x, hi.y, -lo.y)
    if abs(radius - ARENA_RADIUS) > TOLERANCE:
        problems.append("deck radius %.4f, rules say %.2f" % (radius, ARENA_RADIUS))
    if abs(hi.z) > 0.01:
        problems.append("deck top at %.4f, not on the floor" % hi.z)
    edge = bpy.data.objects.get("Edge")
    _elo, ehi = rb.world_bounds([edge])
    if max(ehi.x, -_elo.x, ehi.y, -_elo.y) <= ARENA_RADIUS:
        problems.append("the lip does not pass the deck")
    if _emission_strength("edge") <= 0.0 or _emission_strength("orb") <= 0.0:
        problems.append("the edge and the orb carry a little emission")
    if _emission_strength("deck") > 0.0 or _emission_strength("underside") > 0.0:
        problems.append("the deck and the underside stay unlit")
    for mat_name in ("deck", "edge", "underside", "orb"):
        if bpy.data.materials.get(mat_name) is None:
            problems.append("missing material %s" % mat_name)
    if any(o.type == "ARMATURE" for o in bpy.data.objects):
        problems.append("the deck has no rig")
    tris = rb.triangle_count(_meshes())
    if tris > 2000:
        problems.append("triangles %d over budget 2000" % tris)
    return problems


VALIDATORS = {
    "fighter": validate_fighter,
    "weapon": validate_weapon,
    "arena": validate_arena,
    "board": validate_board,
    "bowl": validate_bowl,
    "floor": validate_floor,
    "crowd": validate_crowd,
    "deck": validate_deck,
}


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
