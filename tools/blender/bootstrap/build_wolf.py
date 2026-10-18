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
chest, head), because the sword path is always the simulation's. The one
exception is the ring fall: the hands have let go, the IK has faded, and the
clip owns the flailing arms.

Wolf stands on a fixed right-foot lead (PRES-STANCE-001). Every clip names
its legs by role — `UpperLeg.Lead`, `LowerLeg.Rear`, … — and `_stance` maps
roles to bones in one place, so no clip can disagree about which foot leads,
and the rest skeleton is built from the same constants. Footwork never
crosses the feet: steps gather (the lead reaches, the rear follows) rather
than pass. Support clips (charge, swing, overswing, recovery) carry the base
stance's legs unchanged and move only the upper body — gait comes from
movement, never from the sword.

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

import character_art  # noqa: E402
import riposte_blocks as rb  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
ART = character_art.load()
_RIG = ART["rig"]
FPS = 60
BLADE_HEIGHT = _RIG["blade_height"]
GRIP_DOMINANT = _RIG["grip_dominant"]
GRIP_OFFHAND = _RIG["grip_offhand"]
## Slightly long for a 1.75 m body on purpose: at full wind-back the far hand
## must still reach the grip, and block proportions forgive the extra reach.
ARM_SEGMENT = _RIG["arm_segment"]
HAND_LENGTH = _RIG["hand_length"]
SHOULDER = tuple(_RIG["shoulder"])

## The display sword's mount for cinematic clips (intro, victory): an unweighted
## bone whose head is the pommel and which points down the blade. Gameplay never
## reads it — the duel's blade is the simulation's — but a showcase actor rides
## it, so a victory can finally pitch the blade out of the gameplay plane.
SWORD_MOUNT = "SwordMount"
## Mid-grip distance from the pommel along the blade (between the markers).
GRIP_MID = (GRIP_DOMINANT + GRIP_OFFHAND) * 0.5

## The fixed lead: which bone side plays each leg role, and where each foot
## stands fore/aft (metres toward the opponent, which is -Y). The rest stagger
## is wide enough that the in-place steps below never close it.
LEAD = "R"
REAR = "L"
LEAD_FOOT_FORWARD = _RIG["lead_foot_forward"]
REAR_FOOT_BACK = _RIG["rear_foot_back"]
## Leg axes, measured on this rig: a thigh's X− swings its foot forward (X+
## back), its Z+ moves the foot toward the fighter's right (−X); a knee's X+
## flexes it; a foot's Y+ rolls its sole back level after the thigh's Z+.
## The base's width: every grounded clip opens both thighs by this much
## (degrees) and rolls the soles back flat, so the ankles stand ~24 cm apart
## across the line instead of ~14 cm — a stable two-handed base, short of
## shoulder width. Authored here, never offset at runtime (STANCE-FOOT-001).
STANCE_ABDUCTION = 4.0
## Footwork amplitudes (degrees): small gathering steps, never passing ones.
STEP_SWING = 9.0
STEP_KNEE = 24.0
SIDE_STEP_SWING = 5.0
## How far the guard lowers the pelvis (m): exactly what the guard's bent
## knees take up (0.41 m segments: lead thigh −19°/shin +13°, rear −10°/+20°
## ≈ 0.032 m), so the boots stay on the floor rather than sinking into it.
GUARD_SINK = 0.032
STEP_BOB = 0.008
LEG_ROLES = ("UpperLeg", "LowerLeg", "Foot")

BONES = [
    # name, head, tail, parent
    ("Root", (0, 0, 0), (0, 0, 0.15), None),
    (SWORD_MOUNT, (0, 0, BLADE_HEIGHT), (0, -0.3, BLADE_HEIGHT), "Root"),
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


def _foot_y(tag):
    """Fore/aft rest position of one foot (armature Y; -Y is forward)."""
    return -LEAD_FOOT_FORWARD if tag == LEAD else REAR_FOOT_BACK


def _stance(poses):
    """Map role-named leg keys (`UpperLeg.Lead`, …) onto bones. Role values are
    authored for the right lead; a left-lead fighter mirrors their lateral
    (Y, Z) components. Bone-named keys pass through (direction-specific
    footwork such as a side step names real sides)."""
    out = {}
    for key, value in poses.items():
        bone_key = key
        for role, tag in (("Lead", LEAD), ("Rear", REAR)):
            if key.endswith("." + role):
                bone_key = key[: -len(role)] + tag
                if LEAD == "L" and not isinstance(value, dict):
                    value = (value[0], -value[1], -value[2])
        if bone_key in out:
            raise ValueError("pose keys %s twice (role and bone names collide)" % bone_key)
        out[bone_key] = value
    return out


def _flat_feet(poses):
    """Stand on the base: open each thigh by `STANCE_ABDUCTION` (the right
    thigh's Z+ carries its foot right, the left's Z− left) and keep each foot
    level with the pelvis — an unkeyed ankle counter-pitches its thigh and knee
    (pitches add down the chain) and rolls back the abduction, so neither a
    flexed knee nor the wider base tips a boot into the floor."""
    out = dict(poses)
    for tag, opening in (("L", -STANCE_ABDUCTION), ("R", STANCE_ABDUCTION)):
        thigh_key = "UpperLeg." + tag
        thigh = out.get(thigh_key)
        if thigh is not None:
            out[thigh_key] = (thigh[0], thigh[1], thigh[2] + opening)
        foot = "Foot." + tag
        if foot in out:
            continue
        knee = out.get("LowerLeg." + tag)
        if thigh is None and knee is None:
            continue
        pitch = (thigh[0] if thigh else 0.0) + (knee[0] if knee else 0.0)
        out[foot] = (-pitch, opening if thigh is not None else 0.0, 0)
    return out


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
        # The fixed lead in the rest skeleton itself: right foot forward.
        hip, knee, ankle, toe = _leg_chain(side, _foot_y(tag))
        bone("UpperLeg." + tag, hip, knee, "Hips")
        bone("LowerLeg." + tag, knee, ankle, "UpperLeg." + tag)
        bone("Foot." + tag, ankle, toe, "LowerLeg." + tag)
    bpy.ops.object.mode_set(mode="OBJECT")
    for pose_bone in rig.pose.bones:
        pose_bone.rotation_mode = "XYZ"
    ## The display-sword mount is keyed as quaternions (free 3D orientation);
    ## the exporter only reads rotation channels of the bone's own mode.
    rig.pose.bones[SWORD_MOUNT].rotation_mode = "QUATERNION"
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
    ## Palette and blocks come from the character art file. Ranger is the
    ## default; training overrides fabric and leather and skips ranger-only parts.
    variant = "training" if training else "ranger"
    colors = character_art.palette_for(ART, variant)
    m = {}
    for slot, body in colors.items():
        color = tuple(body["color"])
        extra = {}
        if slot == "metal":
            extra = {"metallic": body.get("metallic", 0.0), "emission": (0.35, 0.22, 0.08), "emission_strength": 0.08}
        elif "metallic" in body:
            extra = {"metallic": body["metallic"]}
        m[slot] = rb.material(slot, color, roughness=body.get("roughness", 0.8), **extra)
    accent = ART["side_accent"]
    m["side_accent"] = rb.material("side_accent", tuple(accent["preview"]), roughness=accent.get("roughness", 0.7))

    def solid(obj, bone_name):
        return bind(obj, rig, bone_name)

    for part in ART["parts"]:
        if not character_art.visible(part, variant):
            continue
        mat = m[part["slot"]]
        kind = part["kind"]
        if kind == "prism":
            solid(rb.prism(
                part["name"], int(part["sides"]), part["radius"], part["z0"], part["z1"], mat,
                depth_scale=part.get("depth_scale", 1.0), top_scale=part.get("top_scale", 1.0),
                spin=part.get("spin", 0.0), bevel=part.get("bevel", 0.0),
            ), part["bone"])
        elif kind == "box":
            solid(rb.box(
                part["name"], tuple(character_art.part_value(ART, part, variant, "size")), tuple(part["at"]), mat,
                bevel=part.get("bevel", 0.0), rotation=tuple(part.get("rotation", (0.0, 0.0, 0.0))),
            ), part["bone"])
        else:
            segment(
                part["name"], tuple(part["a"]), tuple(part["b"]), part["width"], part["depth"],
                mat, rig, part["bone"], bevel=part.get("bevel", 0.006),
            )
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
        pose_bone.rotation_quaternion = (1, 0, 0, 0)
        pose_bone.location = (0, 0, 0)


def action(rig, name, keys, loop, grounded=True):
    """Key one clip. `grounded` clips keep the feet level (`_flat_feet`); a
    body in the air or on the floor has no stance to keep, and every keyed
    bone costs GLB bytes."""
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = act
    _rest(rig)
    keys = [(frame, _flat_feet(_stance(poses)) if grounded else _stance(poses)) for frame, poses in keys]
    animated = sorted({bone for _f, poses in keys for bone in poses})
    for frame, poses in keys:
        full = {bone: poses.get(bone, (0, 0, 0)) for bone in animated}
        _key(rig, frame, full)
    act["riposte_loop"] = loop
    ## No NLA strips: the exporter reads every action directly, and a strip
    ## stack would quietly pose the rest pose the validators measure.
    rig.animation_data.action = None
    return act


def _key_sword(rig, act, frames):
    """Key the display sword on `SwordMount` for a cinematic clip.

    Each entry is (frame, hands, blade): `hands` is the mid-grip point and
    `blade` the direction the blade points, both in armature space (X lateral
    — Wolf's right is -X — -Y forward, +Z up). The pommel sits GRIP_MID behind
    the hands; the bone's +Y runs down the blade, its +Z keeps the edge plane
    as close to vertical as the direction allows.
    """
    from mathutils import Matrix
    rig.animation_data.action = act
    pose_bone = rig.pose.bones[SWORD_MOUNT]
    rest = pose_bone.bone.matrix_local
    previous = None
    for frame, hands, blade in frames:
        y = Vector(blade).normalized()
        side = Vector((0, 0, 1)).cross(y)
        if side.length < 1e-4:
            side = Vector((1, 0, 0))
        x = side.normalized()
        z = x.cross(y).normalized()
        target = Matrix.Identity(4)
        target.col[0].xyz = x
        target.col[1].xyz = y
        target.col[2].xyz = z
        target.translation = Vector(hands) - y * GRIP_MID
        basis = rest.inverted() @ target
        quat = basis.to_quaternion()
        if previous is not None and previous.dot(quat) < 0.0:
            quat.negate()
        previous = quat
        pose_bone.location = basis.translation
        pose_bone.rotation_quaternion = quat
        pose_bone.keyframe_insert("location", frame=frame)
        pose_bone.keyframe_insert("rotation_quaternion", frame=frame)
    pose_bone.location = (0, 0, 0)
    pose_bone.rotation_quaternion = (1, 0, 0, 0)
    rig.animation_data.action = None


## The duel carriage's landmarks (orbit + CombatPresentationField / CutPresentationCurve),
## as (hands mid-grip, blade direction) in armature space — X lateral (Wolf's
## right is -X), -Y forward, +Z up — so the showcase moves through exactly the
## poses the duel shows. Mirror a pose with _mirror.
MID_GUARD_RIGHT = ((-0.20, -0.29, 1.17), (-0.69, -0.69, 0.21))
CUT_CENTRE = ((0.0, -0.29, 1.16), (0.0, -0.996, 0.087))
CUT_LOW_LEFT = ((0.17, -0.23, 1.03), (0.69, -0.69, -0.24))
GATHER_RIGHT = ((-0.25, -0.17, 1.32), (-0.55, 0.15, 0.82))
HIGH_LOAD_RIGHT = ((-0.28, -0.064, 1.43), (-0.3, 0.3, 0.906))


## A killing thrust's shared timeline, in seconds — the same beats as the
## kit's StabFinisherProfile (duelist_death.tres); PRES-RIG proves the clips
## hold where the profile says they do.
STAB_IMPALE_END = 0.08
STAB_WITHDRAW_START = 0.38
STAB_WITHDRAW_CLEAR = 0.58
STAB_VICTIM_COLLAPSE_START = 0.62
STAB_STRIKER_RECOVER_END = 0.8
STAB_END = 1.05


def _stab_frame(seconds):
    return int(round(seconds * FPS)) + 1


def _mirror(pose):
    (hx, hy, hz), (bx, by, bz) = pose
    return ((-hx, hy, hz), (-bx, by, bz))


def build_victory(rig, guard):
    """Wolf's set victory (~2.2 s at 60 fps): from the duel's mid guard a quick
    cut right → left, the quick return cut left → right, then the gather into
    the duel's own right high shoulder load (Vom Tag at the shoulder / Zornhut
    inspired) — and HOLD while the camera pushes into the profile. No third,
    released attack. Frames match FighterVictoryProfile's beats: cut one 8–18,
    cut two 24–34, charge 42–72, held to 132. One authored timeline — the
    cinematic is presentation, not combat."""
    def body(**poses):
        out = dict(guard)
        out.update(poses)
        return out

    ## Twist is about each vertical bone's own up axis (local Y): +Y turns the
    ## body toward Wolf's left (+X), -Y toward his right.
    cut_left = body(Spine=(8, 12, 0), Chest=(4, 8, 0), Hips={"r": (2, 6, 0), "l": (0, -0.02, -0.045)})
    cut_right = body(Spine=(8, -10, 0), Chest=(4, -8, 0), Hips={"r": (2, -6, 0), "l": (0, -0.02, -0.045)})
    planted = body(**{
        "UpperLeg.Lead": (-12, 0, 0), "UpperLeg.Rear": (10, 0, 0),
        "LowerLeg.Lead": (20, 0, 0), "LowerLeg.Rear": (22, 0, 0),
        "Hips": {"r": (0, -8, 0), "l": (0, 0.03, -0.07)},
    })
    ## A compact stored coil (~18° upper body), head on the camera's side of
    ## the opponent line so the profile reads.
    loaded = dict(planted, Spine=(-4, -6, 0), Chest=(-6, -6, 0), Head=(4, 16, 0))
    keys = [
        (1, guard), (8, guard),
        (13, body(Spine=(8, 0, 0), Chest=(4, 0, 0))), (18, cut_left), (24, cut_left),
        (29, body(Spine=(8, 0, 0), Chest=(4, 0, 0))), (34, cut_right), (42, guard),
        (57, planted), (72, loaded), (132, loaded),
    ]
    act = action(rig, "victory_combo", keys, False)
    _key_sword(rig, act, [
        (1,) + MID_GUARD_RIGHT, (8,) + MID_GUARD_RIGHT,
        (13,) + CUT_CENTRE, (18,) + CUT_LOW_LEFT, (24,) + _mirror(MID_GUARD_RIGHT),
        (29,) + CUT_CENTRE, (34,) + _mirror(CUT_LOW_LEFT), (42,) + MID_GUARD_RIGHT,
        (57,) + GATHER_RIGHT, (72,) + HIGH_LOAD_RIGHT, (132,) + HIGH_LOAD_RIGHT,
    ])
    breathe = dict(loaded, Chest=(-4, -6, 0), Hips={"r": (0, -8, 0), "l": (0, 0.03, -0.075)})
    idle = action(rig, "victory_idle", [(1, loaded), (60, breathe), (120, loaded)], True)
    (hands, blade) = HIGH_LOAD_RIGHT
    breathe_hands = (hands[0], hands[1], hands[2] - 0.01)
    _key_sword(rig, idle, [
        (1,) + HIGH_LOAD_RIGHT,
        (60, breathe_hands, blade),
        (120,) + HIGH_LOAD_RIGHT,
    ])


def _gait(guard, lateral, backward):
    """An in-place gathering-step cycle over the guard stance (36 frames =
    0.6 s at the kit's gait reference speed; playback follows actual speed).
    The feet step alternately — each lifts while it travels the way the body
    moves — but stay on their own side of the stagger: the right foot leads
    through the whole cycle. Fore/aft for advance/retreat; side steps
    (abduction about each thigh's own forward axis) for orbiting, which never
    touch the fore/aft lead. The hips bob; the chest counters a little."""
    sign = -1 if backward else 1
    frames = []
    for i, phase in enumerate((0.0, 0.25, 0.5, 0.75, 1.0)):
        s = math.sin(phase * math.tau)
        c = math.cos(phase * math.tau)
        bob = abs(c) * STEP_BOB
        poses = dict(guard)
        if lateral:
            ## Z+ carries a foot toward −X; a foot lifts while it travels.
            lift_lead = max(-c * lateral, 0.0)
            lift_rear = max(c * lateral, 0.0)
            poses.update({
                "UpperLeg.Lead": (guard["UpperLeg.Lead"][0], 0, s * SIDE_STEP_SWING),
                "UpperLeg.Rear": (guard["UpperLeg.Rear"][0], 0, -s * SIDE_STEP_SWING),
                "LowerLeg.Lead": (guard["LowerLeg.Lead"][0] + lift_lead * STEP_KNEE, 0, 0),
                "LowerLeg.Rear": (guard["LowerLeg.Rear"][0] + lift_rear * STEP_KNEE, 0, 0),
                "Hips": {"r": (0, 0, s * 2), "l": (0, 0, -GUARD_SINK - bob)},
            })
        else:
            ## X− carries a foot forward; a foot lifts while it travels the
            ## way the body moves.
            lift_lead = max(-c * sign, 0.0)
            lift_rear = max(c * sign, 0.0)
            poses.update({
                "UpperLeg.Lead": (guard["UpperLeg.Lead"][0] + s * STEP_SWING, 0, 0),
                "UpperLeg.Rear": (guard["UpperLeg.Rear"][0] - s * STEP_SWING, 0, 0),
                "LowerLeg.Lead": (guard["LowerLeg.Lead"][0] + lift_lead * STEP_KNEE, 0, 0),
                "LowerLeg.Rear": (guard["LowerLeg.Rear"][0] + lift_rear * STEP_KNEE, 0, 0),
                "Hips": {"r": (2 * sign, 0, s * 3), "l": (0, 0, -GUARD_SINK - bob)},
                "Chest": (2, 0, -s * 4),
            })
        frames.append((1 + i * 9, poses))
    return frames


## Upper-body bones a support clip may move; everything below the spine is
## the base stance's.
SUPPORT_BONES = ("Spine", "Chest", "Neck", "Head")


def _support(guard, **upper):
    """A support pose: the guard's lower body unchanged, plus upper-body
    deltas only. Played only while the fighter stands (moving shows the gait),
    so a stationary charge is the idle legs under a charged torso."""
    for bone_name in upper:
        if bone_name not in SUPPORT_BONES:
            raise ValueError("support clips move only %s, not %s" % (SUPPORT_BONES, bone_name))
    out = dict(guard)
    out.update(upper)
    return out


def _one_shot(poses_by_frame):
    return [(frame, poses) for frame, poses in poses_by_frame]


def build_actions(rig):
    ## The base stance every clip derives from: the lead thigh a little
    ## forward, the rear a little back, both knees softly flexed under the
    ## lowered pelvis so both boots stay on the floor.
    guard = {"UpperLeg.Lead": (-19, 0, 0), "UpperLeg.Rear": (-10, 0, 0), "LowerLeg.Lead": (32, 0, 0), "LowerLeg.Rear": (30, 0, 0), "Spine": (4, 0, 0), "Hips": {"r": (0, 0, 0), "l": (0, 0, -GUARD_SINK)}}
    breathe = dict(guard)
    breathe["Chest"] = (2, 0, 0)
    breathe["Hips"] = {"r": (0, 0, 0), "l": (0, 0, -GUARD_SINK - 0.006)}
    action(rig, "idle", [(1, guard), (60, breathe), (120, guard)], True)
    action(rig, "walk_forward", _gait(guard, 0, False), True)
    action(rig, "walk_backward", _gait(guard, 0, True), True)
    action(rig, "orbit_cw", _gait(guard, -1, False), True)
    action(rig, "orbit_ccw", _gait(guard, 1, False), True)
    lunge = {"UpperLeg.Lead": (-30, 0, 0), "UpperLeg.Rear": (24, 0, 0), "LowerLeg.Lead": (28, 0, 0), "LowerLeg.Rear": (6, 0, 0), "Hips": {"r": (10, 0, 0), "l": (0, -0.05, -0.06)}, "Spine": (12, 0, 0), "Chest": (8, 0, 0)}
    action(rig, "dash_forward", _one_shot([(1, guard), (5, lunge), (18, lunge), (30, guard)]), False)
    ## The striker of a killing thrust, on the shared stab timeline
    ## (StabFinisherProfile, frames = seconds × 60 + 1): drive into the lunge,
    ## hold the blade in (firm hands, torso forward) to withdraw_start, draw it
    ## back along the thrust axis — weight back, elbows flex, shoulders retract —
    ## until it is clear, and recover to guard by striker_recover_end.
    driven = dict(lunge, Chest=(12, 0, 0), Head=(4, 0, 0))
    withdrawn = {"UpperLeg.Lead": (-8, 0, 0), "UpperLeg.Rear": (8, 0, 0), "LowerLeg.Lead": (18, 0, 0), "LowerLeg.Rear": (14, 0, 0), "Hips": {"r": (2, 0, 0), "l": (0, 0.03, -0.045)}, "Spine": (0, 0, 0), "Chest": (-4, 0, 0), "Head": (2, 0, 0)}
    action(rig, "run_through", _one_shot([
        (1, guard), (_stab_frame(STAB_IMPALE_END), lunge), (_stab_frame(STAB_WITHDRAW_START), driven),
        (_stab_frame(STAB_WITHDRAW_CLEAR), withdrawn), (_stab_frame(STAB_STRIKER_RECOVER_END), guard),
    ]), False)
    backstep = {"UpperLeg.Lead": (-4, 0, 0), "UpperLeg.Rear": (22, 0, 0), "LowerLeg.Lead": (12, 0, 0), "LowerLeg.Rear": (26, 0, 0), "Hips": {"r": (-8, 0, 0), "l": (0, 0.04, -0.04)}, "Spine": (-6, 0, 0)}
    action(rig, "dash_back", _one_shot([(1, guard), (5, backstep), (16, backstep), (26, guard)]), False)
    ## Side steps name real sides: the leg on the side of travel reaches out
    ## (thigh Z), the other follows a little; fore/aft — the lead — is untouched.
    for name, side in (("dash_left", 1), ("dash_right", -1)):
        driver = "L" if side > 0 else "R"
        burst = dict(guard)
        burst.update({
            "UpperLeg.Lead": (guard["UpperLeg.Lead"][0], 0, -side * (18 if driver == LEAD else 6)),
            "UpperLeg.Rear": (guard["UpperLeg.Rear"][0], 0, -side * (18 if driver == REAR else 6)),
            "LowerLeg.%s" % ("Lead" if driver == LEAD else "Rear"): (24, 0, 0),
            "Hips": {"r": (0, 8 * side, 0), "l": (0.04 * side, 0, -0.05)},
            "Chest": (0, -6 * side, 0),
        })
        action(rig, name, _one_shot([(1, guard), (5, burst), (16, burst), (26, guard)]), False)
    ## Support: the torso coils and commits over the base stance. The legs and
    ## hips stay the guard's (CombatPoseModifier3D adds the load coil).
    ## A held clip still needs motion to have length: a clip whose keys all
    ## repeat collapses to zero length on export and never plays.
    ## The torso's lean — once split between pelvis and spine — is the
    ## spine's alone now, so the stance never moves under it. (One clip
    ## serves both sides of the sword; the side-aware coil is
    ## CombatPoseModifier3D's.)
    coil = _support(guard, Spine=(6, 0, 10))
    action(rig, "charge_support", [(1, coil), (30, dict(coil, Chest=(2, 0, 4))), (60, coil)], True)
    plant = _support(guard, Spine=(12, 0, -24), Chest=(2, 0, -4))
    action(rig, "swing_support", _one_shot([(1, coil), (6, plant), (20, plant), (28, guard)]), False)
    carried = _support(guard, Spine=(18, 0, -36), Chest=(6, 0, -10), Head=(-6, 0, 6))
    action(rig, "overswing", _one_shot([(1, plant), (8, carried), (30, carried), (40, plant)]), False)
    action(rig, "recovery", _one_shot([(1, carried), (10, _support(guard, Spine=(6, 0, -4))), (20, guard)]), False)
    flinch = dict(guard)
    flinch.update({"Spine": (-10, 0, 0), "Chest": (-8, 0, 4), "Head": (-12, 0, 0), "Hips": {"r": (0, 0, 0), "l": (0, 0.03, -0.02)}})
    action(rig, "hurt_light", _one_shot([(1, guard), (4, flinch), (14, guard)]), False)
    heavy = dict(flinch)
    heavy.update({"Spine": (-18, 0, 6), "Chest": (-14, 0, 8), "Head": (-24, 0, -8), "UpperLeg.Rear": (18, 0, 0)})
    action(rig, "hurt_heavy", _one_shot([(1, guard), (4, heavy), (12, heavy), (26, guard)]), False)
    wobble_a = dict(guard, Spine=(-6, 6, 0), Chest=(0, 8, 0), Head=(4, -8, 0))
    wobble_b = dict(guard, Spine=(-4, -6, 0), Chest=(0, -8, 0), Head=(2, 8, 0))
    action(rig, "stagger", [(1, wobble_a), (12, wobble_b), (24, wobble_a)], True)
    fallen = {"Hips": {"r": (-70, 0, 0), "l": (0, 0.35, -0.68)}, "Spine": (-12, 0, 0), "Chest": (-8, 0, 0), "Head": (-20, 0, 10), "UpperLeg.Lead": (40, 0, 0), "UpperLeg.Rear": (70, 0, 0), "LowerLeg.Lead": (-60, 0, 0), "LowerLeg.Rear": (-40, 0, 0)}
    buckle = {"Hips": {"r": (-10, 0, 0), "l": (0, 0.05, -0.2)}, "Spine": (20, 0, 0), "UpperLeg.Lead": (40, 0, 0), "UpperLeg.Rear": (40, 0, 0), "LowerLeg.Lead": (-70, 0, 0), "LowerLeg.Rear": (-70, 0, 0)}
    action(rig, "death", _one_shot([(1, guard), (10, buckle), (28, fallen)]), False, grounded=False)
    ## Run through (a killing thrust): the body folds over the blade and is
    ## driven back a touch, the knees give, and it pitches forward face-down —
    ## the mirror of the cut-down death above, which falls backward. Same axis
    ## language as the lunge: +X pitches forward, -Y moves forward, -Z sinks.
    impaled = {"Hips": {"r": (6, 0, 0), "l": (0, 0.06, -0.06)}, "Spine": (26, 0, 0), "Chest": (20, 0, 0), "Head": (16, 0, 0), "UpperLeg.Lead": (-4, 0, 0), "UpperLeg.Rear": (8, 0, 0), "LowerLeg.Lead": (-16, 0, 0), "LowerLeg.Rear": (-18, 0, 0)}
    kneel = {"Hips": {"r": (14, 0, 0), "l": (0, 0.04, -0.43)}, "Spine": (30, 0, 0), "Chest": (22, 0, 0), "Head": (24, 0, 0), "UpperLeg.Lead": (-10, 0, 0), "UpperLeg.Rear": (-6, 0, 0), "LowerLeg.Lead": (-95, 0, 0), "LowerLeg.Rear": (-92, 0, 0)}
    face_down = {"Hips": {"r": (78, 0, 0), "l": (0, -0.22, -0.70)}, "Spine": (8, 0, 0), "Chest": (6, 0, 0), "Head": (-15, 0, 30), "UpperLeg.Lead": (6, -8, 0), "UpperLeg.Rear": (-4, 6, 0), "LowerLeg.Lead": (-24, 0, 0), "LowerLeg.Rear": (-14, 0, 0)}
    ## On the shared stab timeline: the victim takes the blade, holds impaled
    ## on supporting legs (a beat to look down at it) while the striker
    ## withdraws, and only once the blade is clear do the knees go.
    ## Guard keys one frame inside each end of the hold keep Blender's
    ## auto-clamped handles flat across it, so "held" means held.
    looking = dict(impaled, Head=(30, 0, 0))
    impale, collapse = _stab_frame(STAB_IMPALE_END), _stab_frame(STAB_VICTIM_COLLAPSE_START)
    action(rig, "death_stab", _one_shot([
        (1, guard), (impale, impaled), (impale + 1, impaled), (_stab_frame(STAB_WITHDRAW_START), looking),
        (collapse - 1, looking), (collapse, looking), (_stab_frame(STAB_VICTIM_COLLAPSE_START + 0.2), kneel),
        (_stab_frame(STAB_END), face_down),
    ]), False)
    flourish_a = dict(guard, Spine=(4, 0, 18), Chest=(0, 0, 14), Head=(0, 0, -12))
    flourish_b = dict(guard, Spine=(6, 0, -16), Chest=(0, 0, -12), Head=(0, 0, 10))
    action(rig, "flourish", _one_shot([(1, guard), (12, flourish_a), (26, flourish_b), (40, guard)]), False)
    build_ring_falls(rig, guard)
    build_victory(rig, guard)


## Arm poses for the ring fall, per side (euler degrees on UpperArm / Forearm).
## The hands have let go and the IK has faded, so these clips own the arms.
## Measured on this rig (the two arms' bone rolls differ, so the numbers are
## not mirror images): UP puts each hand ~0.55 m above its shoulder, WIDE
## ~0.55 m out at shoulder height. The left arm's WIDE is written as −225°
## (≡ 135°) so its keys interpolate through 60°, never through the torso.
ARMS_UP = {"UpperArm.L": (-165, 0, 75), "UpperArm.R": (0, 0, 150), "Forearm.L": (-40, 0, 0), "Forearm.R": (-40, 0, 0)}
ARMS_WIDE = {"UpperArm.L": (-225, 0, 165), "UpperArm.R": (60, 0, 90), "Forearm.L": (-40, 0, 0), "Forearm.R": (-40, 0, 0)}
ARMS_FLAP_HIGH = {"UpperArm.L": (-195, 0, 120), "UpperArm.R": (30, 0, 120), "Forearm.L": (-10, 0, 0), "Forearm.R": (-10, 0, 0)}


def _arms(**sides):
    """Merge per-side arm poses: `_arms(L=ARMS_UP, R=ARMS_WIDE)`."""
    out = {}
    for tag, pose in sides.items():
        for key, value in pose.items():
            if key.endswith("." + tag):
                out[key] = value
    return out


def build_ring_falls(rig, guard):
    """Three in-place ring-fall flails (PRES-TERMINAL-001): the fighter has
    lost the platform; the fall itself is the presentation root's trajectory,
    never root motion here. Each raises at least one hand above the shoulder
    within ~0.25 s (frame 16) and keeps the limbs moving: panic, played
    seriously. Short looping cycles (0.6 s) after a startle — a fall leaves
    the screen within a second or two, and each frame costs GLB bytes; the
    variant is chosen deterministically by the terminal presenter."""
    startle = dict(guard, Spine=(-8, 0, 0), Chest=(-10, 0, 0), Head=(-14, 0, 0))
    ## A — arms shoot up, elbows loose, legs splay and kick alternately.
    kick_a = dict(startle, **ARMS_UP, **{"UpperLeg.Lead": (-30, 0, 14), "UpperLeg.Rear": (20, 0, -14), "LowerLeg.Lead": (40, 0, 0), "LowerLeg.Rear": (10, 0, 0)})
    kick_b = dict(startle, **ARMS_FLAP_HIGH, **{"UpperLeg.Lead": (20, 0, 14), "UpperLeg.Rear": (-30, 0, -14), "LowerLeg.Lead": (10, 0, 0), "LowerLeg.Rear": (40, 0, 0)})
    action(rig, "ring_fall_a", [(1, startle), (12, kick_a), (24, kick_b), (36, kick_a)], True, grounded=False)
    ## B — arms windmill (one up while the other is wide), one knee tucks,
    ## the other leg reaches, head tips up.
    mill_a = dict(startle, Head=(-24, 0, 0), **_arms(L=ARMS_UP, R=ARMS_WIDE), **{"UpperLeg.Lead": (-60, 0, 0), "LowerLeg.Lead": (90, 0, 0), "UpperLeg.Rear": (15, 0, -10), "LowerLeg.Rear": (5, 0, 0)})
    mill_b = dict(startle, Head=(-24, 0, 0), **_arms(L=ARMS_WIDE, R=ARMS_UP), **{"UpperLeg.Lead": (-45, 0, 0), "LowerLeg.Lead": (80, 0, 0), "UpperLeg.Rear": (25, 0, -12), "LowerLeg.Rear": (5, 0, 0)})
    action(rig, "ring_fall_b", [(1, startle), (12, mill_a), (24, mill_b), (36, mill_a)], True, grounded=False)
    ## C — a brief starfish, then a frantic double flap with bicycling legs.
    star = dict(startle, **ARMS_WIDE, **{"UpperLeg.Lead": (0, 0, 22), "UpperLeg.Rear": (0, 0, -22), "LowerLeg.Lead": (5, 0, 0), "LowerLeg.Rear": (5, 0, 0)})
    flap_up = dict(star, **ARMS_UP, **{"UpperLeg.Lead": (-40, 0, 10), "LowerLeg.Lead": (70, 0, 0), "UpperLeg.Rear": (10, 0, -10), "LowerLeg.Rear": (20, 0, 0)})
    flap_down = dict(star, **ARMS_FLAP_HIGH, **{"UpperLeg.Lead": (10, 0, 10), "LowerLeg.Lead": (20, 0, 0), "UpperLeg.Rear": (-40, 0, -10), "LowerLeg.Rear": (70, 0, 0)})
    action(rig, "ring_fall_c", [(1, startle), (8, star), (14, flap_up), (24, flap_down), (36, flap_up)], True, grounded=False)


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
