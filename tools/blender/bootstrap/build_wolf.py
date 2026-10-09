"""Bootstrap Wolf, the baseline duelist (art-src/blender/fighters/wolf.blend).

Wolf is built in layers, never painted: a cylindrical core torso, a separate
gambeson shell, a physical belt, a fur collar, block boots, bracers, block
hair, and cloth panels. Every piece is its own low-poly solid bound rigidly
to exactly one bone, so joints read as construction joints and nothing
deforms organically.

Dimensions follow the physical baseline: 1.75 m tall inside a 0.27 m
footprint, hands at the sword markers in a HEMA guard with the blade at
1.0 m. The rig faces -Y (Godot +Z). Arms are left to two-hand IK in Godot —
the clips animate only what expresses physical state (feet, hips, spine,
chest, head), because the sword path is always the simulation's.

Side affiliation lives only on the SideAccent* pieces, which Godot recolours
per side; Wolf's own palette never changes.

Run: blender --background --factory-startup --python tools/blender/bootstrap/build_wolf.py -- [--variant training]
"""

import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import riposte_blocks as rb  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
FPS = 60
BLADE_HEIGHT = 1.0
GRIP_DOMINANT = 0.225
GRIP_OFFHAND = 0.15
## Slightly long for a 1.75 m body on purpose: at full wind-back the far hand
## must still reach the grip, and block proportions forgive the extra reach.
ARM_SEGMENT = 0.3
HAND_LENGTH = 0.06
SHOULDER = (0.2, 0.0, 1.37)

BONES = [
    # name, head, tail, parent
    ("Root", (0, 0, 0), (0, 0, 0.15), None),
    ("Hips", (0, 0, 0.88), (0, 0, 1.0), "Root"),
    ("Spine", (0, 0, 1.0), (0, 0, 1.18), "Hips"),
    ("Chest", (0, 0, 1.18), (0, 0, 1.4), "Spine"),
    ("Neck", (0, 0, 1.4), (0, 0, 1.5), "Chest"),
    ("Head", (0, 0, 1.5), (0, 0, 1.76), "Neck"),
]


def _arm_chain(side):
    """Shoulder → elbow → wrist → grip for one arm in the guard rest pose.
    The right (dominant) hand holds near the guard, the left behind it."""
    x = SHOULDER[0] * side
    shoulder = Vector((x, SHOULDER[1], SHOULDER[2]))
    collar = Vector((x * 0.3, 0.0, SHOULDER[2]))
    grip = Vector((0.0, -(GRIP_DOMINANT if side < 0 else GRIP_OFFHAND), BLADE_HEIGHT))
    to_grip = (grip - shoulder).normalized()
    wrist = grip - to_grip * HAND_LENGTH
    reach = (wrist - shoulder).length
    # Elbow out to the side and slightly FORWARD (−Y is where Wolf faces), so
    # the arms open into a triangle toward the hilt in front of the chest
    # rather than clamping the weapon back against the ribs. Lateral dominates
    # so the elbows clear the torso silhouette from the gameplay camera.
    mid = (shoulder + wrist) * 0.5
    bend = math.sqrt(max(ARM_SEGMENT * ARM_SEGMENT - (reach * 0.5) ** 2, 0.0))
    outward = Vector((side, -0.30, -0.12)).normalized()
    axis = (wrist - shoulder).normalized()
    pole = (outward - axis * outward.dot(axis)).normalized()
    elbow = mid + pole * bend
    return collar, shoulder, elbow, wrist, grip


def _leg_chain(side, forward):
    hip = Vector((0.1 * side, forward * 0.5, 0.88))
    knee = Vector((0.1 * side, forward - 0.03, 0.47))
    ankle = Vector((0.1 * side, forward, 0.09))
    toe = Vector((0.1 * side, forward - 0.15, 0.04))
    return hip, knee, ankle, toe


def build_armature():
    data = bpy.data.armatures.new("WolfRig")
    rig = bpy.data.objects.new("Armature", data)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    edit = data.edit_bones

    def bone(name, head, tail, parent):
        b = edit.new(name)
        b.head = head
        b.tail = tail
        b.roll = 0.0
        if parent is not None:
            b.parent = edit[parent]
            b.use_connect = False
        return b

    for name, head, tail, parent in BONES:
        bone(name, head, tail, parent)
    for side, tag in ((1, "L"), (-1, "R")):
        collar, shoulder, elbow, wrist, grip = _arm_chain(side)
        bone("Shoulder." + tag, collar, shoulder, "Chest")
        bone("UpperArm." + tag, shoulder, elbow, "Shoulder." + tag)
        bone("Forearm." + tag, elbow, wrist, "UpperArm." + tag)
        bone("Hand." + tag, wrist, grip, "Forearm." + tag)
        # Left foot slightly forward (Mittelhut: staggered, athletic), right foot back.
        hip, knee, ankle, toe = _leg_chain(side, -0.08 if side > 0 else 0.07)
        bone("UpperLeg." + tag, hip, knee, "Hips")
        bone("LowerLeg." + tag, knee, ankle, "UpperLeg." + tag)
        bone("Foot." + tag, ankle, toe, "LowerLeg." + tag)
    bpy.ops.object.mode_set(mode="OBJECT")
    for pose_bone in rig.pose.bones:
        pose_bone.rotation_mode = "XYZ"
    return rig


def bind(obj, rig, bone_name):
    """Rigid skinning: every vertex follows exactly one bone."""
    group = obj.vertex_groups.new(name=bone_name)
    group.add([v.index for v in obj.data.vertices], 1.0, "REPLACE")
    modifier = obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = rig
    obj.parent = rig
    return obj


def segment(name, a, b, width, depth, mat, rig, bone_name, bevel=0.006):
    """A block spanning two points (for limbs), bound to `bone_name`."""
    a, b = Vector(a), Vector(b)
    length = (b - a).length
    obj = rb.box(name, (width, depth, length), (0, 0, 0), mat, bevel=bevel)
    direction = (b - a).normalized()
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(direction)
    obj.location = (a + b) * 0.5
    bpy.context.view_layer.update()
    obj.data.transform(obj.matrix_world)
    obj.matrix_world.identity()
    return bind(obj, rig, bone_name)


def build_body(rig, training):
    m = {
        ## Dark enough to clear 3:1 against the arena floor (the validator
        ## checks it): charcoal for the ranger, a warm dark brown for training.
        "fabric": rb.material("fabric", (0.035, 0.035, 0.042) if not training else (0.05, 0.03, 0.016), roughness=0.95),
        "leather": rb.material("leather", (0.2, 0.12, 0.07) if not training else (0.33, 0.22, 0.12), roughness=0.6),
        "metal": rb.material("metal", (0.16, 0.15, 0.15), roughness=0.55, metallic=0.85, emission=(0.35, 0.22, 0.08), emission_strength=0.08),
        "hair": rb.material("hair", (0.03, 0.03, 0.035), roughness=0.9),
        "skin": rb.material("skin", (0.87, 0.71, 0.6), roughness=0.75),
        "side_accent": rb.material("side_accent", (0.75, 0.62, 0.3), roughness=0.7),
    }
    trousers = m["fabric"]

    def solid(obj, bone_name):
        return bind(obj, rig, bone_name)

    # Core body ------------------------------------------------------------
    solid(rb.prism("TorsoLower", 10, 0.16, 0.95, 1.19, m["fabric"], depth_scale=0.8), "Spine")
    solid(rb.prism("TorsoCore", 10, 0.165, 1.18, 1.45, m["fabric"], depth_scale=0.8, top_scale=1.04), "Chest")
    solid(rb.prism("Neck", 6, 0.055, 1.42, 1.52, m["skin"]), "Neck")
    # Pentagonal prism head: one vertex points where Wolf faces (-Y).
    solid(rb.prism("Head", 5, 0.125, 1.5, 1.75, m["skin"], spin=-math.pi / 2, depth_scale=0.95, bevel=0.008), "Head")
    for side in (-1, 1):
        solid(rb.box("Eye%s" % ("L" if side > 0 else "R"), (0.035, 0.012, 0.02), (side * 0.04, -0.093, 1.635), m["hair"]), "Head")
    solid(rb.box("Brow", (0.12, 0.02, 0.022), (0.0, -0.088, 1.668), m["hair"], rotation=(0.0, 0.0, 0.0)), "Head")
    # Shaggy asymmetric hair: a cap, a heavy back drop, and a fringe swept
    # to Wolf's right so the silhouette also reads facing.
    hair_cap = (0.25, 0.23, 0.05) if not training else (0.23, 0.21, 0.03)
    solid(rb.box("Hair", hair_cap, (0.0, 0.01, 1.755), m["hair"], bevel=0.01), "Head")
    if not training:
        solid(rb.box("HairBack", (0.24, 0.07, 0.2), (0.0, 0.1, 1.64), m["hair"], bevel=0.01), "Head")
        solid(rb.box("HairFringe", (0.09, 0.05, 0.06), (-0.06, -0.085, 1.73), m["hair"], rotation=(0.0, 0.25, 0.0)), "Head")
        solid(rb.box("HairSide", (0.04, 0.12, 0.12), (0.12, 0.02, 1.68), m["hair"]), "Head")
    # Layered clothing ------------------------------------------------------
    solid(rb.prism("GambesonShell", 8, 0.2, 1.1, 1.43, m["fabric"], depth_scale=0.82, spin=math.pi / 8, bevel=0.01), "Chest")
    solid(rb.prism("GambesonLower", 8, 0.205, 0.84, 1.12, m["fabric"], depth_scale=0.84, spin=math.pi / 8, top_scale=0.97), "Spine")
    solid(rb.prism("Belt", 10, 0.215, 0.93, 0.99, m["leather"], depth_scale=0.84), "Hips")
    solid(rb.box("BeltBuckle", (0.06, 0.02, 0.05), (0.0, -0.185, 0.96), m["metal"], bevel=0.004), "Hips")
    solid(rb.box("SideAccentSash", (0.07, 0.03, 0.26), (0.13, -0.155, 0.82), m["side_accent"], rotation=(0.0, 0.18, 0.0)), "Hips")
    solid(rb.box("ClothPanelFront", (0.22, 0.03, 0.26), (0.0, -0.17, 0.74), m["fabric"], bevel=0.004), "Hips")
    solid(rb.box("ClothPanelBack", (0.26, 0.03, 0.3), (0.0, 0.17, 0.72), m["fabric"], bevel=0.004), "Hips")
    if not training:
        solid(rb.prism("FurCollar", 10, 0.24, 1.36, 1.48, m["hair"], depth_scale=0.8, top_scale=0.82, bevel=0.012), "Chest")
        for side in (-1, 1):
            tag = "L" if side > 0 else "R"
            shoulder = Vector((SHOULDER[0] * side, 0.0, SHOULDER[2]))
            solid(rb.box("ShoulderPiece." + tag, (0.13, 0.17, 0.07), shoulder + Vector((side * 0.015, 0.0, 0.04)), m["leather"], bevel=0.01), "Shoulder." + tag)
    solid(rb.box("SideAccentMark", (0.012, 0.07, 0.07), (SHOULDER[0] + 0.065, 0.0, 1.36), m["side_accent"]), "Shoulder.L")
    # Arms -------------------------------------------------------------------
    for side, tag in ((1, "L"), (-1, "R")):
        collar, shoulder, elbow, wrist, grip = _arm_chain(side)
        segment("UpperArm." + tag, shoulder, elbow, 0.085, 0.085, m["fabric"], rig, "UpperArm." + tag)
        segment("Forearm." + tag, elbow, wrist, 0.075, 0.075, m["fabric"], rig, "Forearm." + tag)
        segment("Bracer." + tag, elbow.lerp(wrist, 0.35), wrist, 0.092, 0.092, m["leather"], rig, "Forearm." + tag)
        segment("SideAccentBracer." + tag, wrist.lerp(elbow, 0.08), wrist, 0.098, 0.098, m["side_accent"], rig, "Forearm." + tag, bevel=0.0)
        segment("Hand." + tag, wrist, grip, 0.07, 0.06, m["skin"], rig, "Hand." + tag)
        # Legs ---------------------------------------------------------------
        hip, knee, ankle, toe = _leg_chain(side, -0.08 if side > 0 else 0.07)
        segment("UpperLeg." + tag, hip, knee, 0.12, 0.13, trousers, rig, "UpperLeg." + tag)
        segment("LowerLeg." + tag, knee, ankle + Vector((0, 0, 0.08)), 0.105, 0.115, trousers, rig, "LowerLeg." + tag)
        # Slightly oversized block boots for top-down readability.
        solid(rb.box("Boot." + tag, (0.13, 0.25, 0.14), (ankle.x, ankle.y - 0.05, 0.07), m["leather"], bevel=0.012), "Foot." + tag)
        solid(rb.box("BootCuff." + tag, (0.135, 0.135, 0.06), (ankle.x, ankle.y, 0.17), m["leather"], bevel=0.006), "LowerLeg." + tag)
    return m


# Animation ------------------------------------------------------------------

def _key(rig, frame, poses):
    for bone_name, value in poses.items():
        pose_bone = rig.pose.bones[bone_name]
        rot = value.get("r") if isinstance(value, dict) else value
        loc = value.get("l") if isinstance(value, dict) else None
        if rot is not None:
            pose_bone.rotation_euler = tuple(math.radians(v) for v in rot)
            pose_bone.keyframe_insert("rotation_euler", frame=frame)
        if loc is not None:
            ## Offsets are authored in armature space (X lateral, -Y forward,
            ## +Z up) — the language every clip below is written in — but a
            ## pose bone's location lives in its own rest frame. For the
            ## vertical Hips that frame is Y-up/Z-forward, so writing the
            ## offset raw swapped "sink" with "step back" and dropped a dead
            ## body 0.35 m *up* instead of 0.68 m down.
            pose_bone.location = pose_bone.bone.matrix_local.to_3x3().inverted() @ Vector(loc)
            pose_bone.keyframe_insert("location", frame=frame)


def _rest(rig):
    for pose_bone in rig.pose.bones:
        pose_bone.rotation_euler = (0, 0, 0)
        pose_bone.location = (0, 0, 0)


def action(rig, name, keys, loop):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = act
    _rest(rig)
    animated = sorted({bone for _f, poses in keys for bone in poses})
    for frame, poses in keys:
        full = {bone: poses.get(bone, (0, 0, 0)) for bone in animated}
        _key(rig, frame, full)
    act["riposte_loop"] = loop
    ## No NLA strips: the exporter reads every action directly, and a strip
    ## stack would quietly pose the rest pose the validators measure.
    rig.animation_data.action = None
    return act


def _gait(lateral, backward):
    """A passing-step cycle: legs scissor fore/aft (or abduct for orbiting),
    hips bob, chest counters. 36 frames = 0.6 s."""
    sign = -1 if backward else 1
    frames = []
    for i, phase in enumerate((0.0, 0.25, 0.5, 0.75, 1.0)):
        s = math.sin(phase * math.tau)
        bob = abs(math.cos(phase * math.tau)) * 0.02
        if lateral:
            poses = {
                "UpperLeg.L": (0, s * 14 * lateral, 0),
                "UpperLeg.R": (0, -s * 14 * lateral, 0),
                "LowerLeg.L": (max(s, 0) * 18, 0, 0),
                "LowerLeg.R": (max(-s, 0) * 18, 0, 0),
                "Hips": {"r": (0, s * 4, 0), "l": (0, 0, -bob)},
                "Chest": (0, -s * 3, 0),
            }
        else:
            poses = {
                "UpperLeg.L": (s * 26 * sign, 0, 0),
                "UpperLeg.R": (-s * 26 * sign, 0, 0),
                "LowerLeg.L": (-max(-s, 0) * 34, 0, 0),
                "LowerLeg.R": (-max(s, 0) * 34, 0, 0),
                "Hips": {"r": (2 * sign, 0, s * 5), "l": (0, 0, -bob)},
                "Chest": (0, 0, -s * 6),
            }
        frames.append((1 + i * 9, poses))
    return frames


def _one_shot(poses_by_frame):
    return [(frame, poses) for frame, poses in poses_by_frame]


def build_actions(rig):
    ## The guard sinks the hips rather than lifting the feet: bent knees under a
    ## lowered pelvis keep both boots on the floor.
    guard = {"UpperLeg.L": (-8, 0, 0), "UpperLeg.R": (6, 0, 0), "LowerLeg.L": (-10, 0, 0), "LowerLeg.R": (-12, 0, 0), "Spine": (4, 0, 0), "Hips": {"r": (0, 0, 0), "l": (0, 0, -0.035)}}
    breathe = dict(guard)
    breathe["Chest"] = (2, 0, 0)
    breathe["Hips"] = {"r": (0, 0, 0), "l": (0, 0, -0.045)}
    action(rig, "idle", [(1, guard), (60, breathe), (120, guard)], True)
    action(rig, "walk_forward", _gait(0, False), True)
    action(rig, "walk_backward", _gait(0, True), True)
    action(rig, "orbit_cw", _gait(-1, False), True)
    action(rig, "orbit_ccw", _gait(1, False), True)
    lunge = {"UpperLeg.L": (38, 0, 0), "UpperLeg.R": (-30, 0, 0), "LowerLeg.L": (-28, 0, 0), "LowerLeg.R": (-6, 0, 0), "Hips": {"r": (10, 0, 0), "l": (0, -0.05, -0.06)}, "Spine": (12, 0, 0), "Chest": (8, 0, 0)}
    action(rig, "dash_forward", _one_shot([(1, guard), (5, lunge), (18, lunge), (30, guard)]), False)
    ## The striker of a killing thrust holds the run-through: drive into the
    ## lunge and stay committed through the kill beat (54 frames = 0.9 s),
    ## instead of the dash's step back to guard.
    driven = dict(lunge, Chest=(12, 0, 0), Head=(4, 0, 0))
    action(rig, "run_through", _one_shot([(1, guard), (5, lunge), (54, driven)]), False)
    backstep = {"UpperLeg.L": (-14, 0, 0), "UpperLeg.R": (24, 0, 0), "LowerLeg.R": (-30, 0, 0), "Hips": {"r": (-8, 0, 0), "l": (0, 0.04, -0.04)}, "Spine": (-6, 0, 0)}
    action(rig, "dash_back", _one_shot([(1, guard), (5, backstep), (16, backstep), (26, guard)]), False)
    for name, side in (("dash_left", 1), ("dash_right", -1)):
        burst = {"UpperLeg.L": (0, 22 * side, 0), "UpperLeg.R": (0, 10 * side, 0), "LowerLeg.L": (-20, 0, 0), "Hips": {"r": (0, 8 * side, 0), "l": (0.04 * side, 0, -0.05)}, "Chest": (0, -6 * side, 0)}
        action(rig, name, _one_shot([(1, guard), (5, burst), (16, burst), (26, guard)]), False)
    coil = dict(guard)
    coil.update({"UpperLeg.R": (14, 0, 0), "LowerLeg.R": (-24, 0, 0), "Hips": {"r": (0, 0, 8), "l": (0, 0.03, -0.04)}, "Spine": (6, 0, 10)})
    action(rig, "charge_support", [(1, coil), (30, dict(coil, Chest=(2, 0, 4))), (60, coil)], True)
    plant = {"UpperLeg.L": (24, 0, 0), "UpperLeg.R": (-12, 0, 0), "LowerLeg.L": (-22, 0, 0), "Hips": {"r": (4, 0, -10), "l": (0, -0.03, -0.03)}, "Spine": (8, 0, -12)}
    action(rig, "swing_support", _one_shot([(1, coil), (6, plant), (20, plant), (28, guard)]), False)
    carried = {"UpperLeg.L": (30, 0, 0), "UpperLeg.R": (-18, 0, 0), "LowerLeg.L": (-30, 0, 0), "Hips": {"r": (8, 0, -18), "l": (0, -0.06, -0.06)}, "Spine": (14, 0, -18), "Chest": (6, 0, -10), "Head": (-6, 0, 6)}
    action(rig, "overswing", _one_shot([(1, plant), (8, carried), (30, carried), (40, plant)]), False)
    action(rig, "recovery", _one_shot([(1, carried), (10, dict(guard, Spine=(6, 0, -4))), (20, guard)]), False)
    flinch = dict(guard)
    flinch.update({"Spine": (-10, 0, 0), "Chest": (-8, 0, 4), "Head": (-12, 0, 0), "Hips": {"r": (0, 0, 0), "l": (0, 0.03, -0.02)}})
    action(rig, "hurt_light", _one_shot([(1, guard), (4, flinch), (14, guard)]), False)
    heavy = dict(flinch)
    heavy.update({"Spine": (-18, 0, 6), "Chest": (-14, 0, 8), "Head": (-24, 0, -8), "UpperLeg.R": (18, 0, 0)})
    action(rig, "hurt_heavy", _one_shot([(1, guard), (4, heavy), (12, heavy), (26, guard)]), False)
    wobble_a = dict(guard, Spine=(-6, 6, 0), Chest=(0, 8, 0), Head=(4, -8, 0))
    wobble_b = dict(guard, Spine=(-4, -6, 0), Chest=(0, -8, 0), Head=(2, 8, 0))
    action(rig, "stagger", [(1, wobble_a), (12, wobble_b), (24, wobble_a)], True)
    fallen = {"Hips": {"r": (-70, 0, 0), "l": (0, 0.35, -0.68)}, "Spine": (-12, 0, 0), "Chest": (-8, 0, 0), "Head": (-20, 0, 10), "UpperLeg.L": (40, 0, 0), "UpperLeg.R": (70, 0, 0), "LowerLeg.L": (-60, 0, 0), "LowerLeg.R": (-40, 0, 0)}
    buckle = {"Hips": {"r": (-10, 0, 0), "l": (0, 0.05, -0.2)}, "Spine": (20, 0, 0), "UpperLeg.L": (40, 0, 0), "UpperLeg.R": (40, 0, 0), "LowerLeg.L": (-70, 0, 0), "LowerLeg.R": (-70, 0, 0)}
    action(rig, "death", _one_shot([(1, guard), (10, buckle), (28, fallen)]), False)
    ## Run through (a killing thrust): the body folds over the blade and is
    ## driven back a touch, the knees give, and it pitches forward face-down —
    ## the mirror of the cut-down death above, which falls backward. Same axis
    ## language as the lunge: +X pitches forward, -Y moves forward, -Z sinks.
    impaled = {"Hips": {"r": (6, 0, 0), "l": (0, 0.06, -0.06)}, "Spine": (26, 0, 0), "Chest": (20, 0, 0), "Head": (16, 0, 0), "UpperLeg.L": (-4, 0, 0), "UpperLeg.R": (8, 0, 0), "LowerLeg.L": (-16, 0, 0), "LowerLeg.R": (-18, 0, 0)}
    kneel = {"Hips": {"r": (14, 0, 0), "l": (0, 0.04, -0.43)}, "Spine": (30, 0, 0), "Chest": (22, 0, 0), "Head": (24, 0, 0), "UpperLeg.L": (-10, 0, 0), "UpperLeg.R": (-6, 0, 0), "LowerLeg.L": (-95, 0, 0), "LowerLeg.R": (-92, 0, 0)}
    face_down = {"Hips": {"r": (78, 0, 0), "l": (0, -0.22, -0.70)}, "Spine": (8, 0, 0), "Chest": (6, 0, 0), "Head": (-15, 0, 30), "UpperLeg.L": (6, 8, 0), "UpperLeg.R": (-4, -6, 0), "LowerLeg.L": (-24, 0, 0), "LowerLeg.R": (-14, 0, 0)}
    action(rig, "death_stab", _one_shot([(1, guard), (6, impaled), (16, kneel), (32, face_down)]), False)
    flourish_a = dict(guard, Spine=(4, 0, 18), Chest=(0, 0, 14), Head=(0, 0, -12))
    flourish_b = dict(guard, Spine=(6, 0, -16), Chest=(0, 0, -12), Head=(0, 0, 10))
    action(rig, "flourish", _one_shot([(1, guard), (12, flourish_a), (26, flourish_b), (40, guard)]), False)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    variant = argv[argv.index("--variant") + 1] if "--variant" in argv else "base"
    scene = rb.reset_scene()
    scene.render.fps = FPS
    rig = build_armature()
    build_body(rig, variant == "training")
    build_actions(rig)
    _rest(rig)
    name = "wolf_training.blend" if variant == "training" else "wolf.blend"
    out = os.path.join(ROOT, "art-src", "blender", "fighters", name)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=out, compress=True)
    print("RIPOSTE_BUILT", out)


if __name__ == "__main__":
    main()
