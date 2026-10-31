"""Bootstrap the male base: the authored master every male character derives from (CHARACTER-SOURCE-001).

Run once to create `art-src/blender/characters/male_base.blend`; from then
on that blend is the authority and is edited in Blender (an artist or Blender
MCP), like every other source under art-src. It is never regenerated as part of
a build, and nothing here is a body generator. The muscularity pass
(`tools/blender/authoring/male_base_muscularity_pass.py`) followed it once.

What it starts from, and why:
- WolfRig (the canonical fighter skeleton), its clips, and the frozen v1 candidate's joint-looped topology
  and region weights (`fighters/wolf_production.blend`, read only). Those loops
  and weights are proven in Godot; they carry over as candidates.
- Model A's flat-panel head (`characters/reference/model_a.blend`, read
  only), reduced to the hero budget with planar decimation so its panels, the
  central ridge and the pointed nose stay planes. It rides the Head bone.
- The heroic pass (ART-STYLE-001): mass redistributed around the unchanged
  joints. Waist and limbs narrow, the barrel chest flattens, the pelvis reads
  as a wedge. Bone lengths, joint centres, reach and the 1.80 m crown do not
  move.
- The authoring A-pose, read off Model A's arms, stored on the armature as the
  inspection pose. It is never the rest: the rest is WolfRig's
  (`wolf.rig-contract.json`).

Run: blender --background --factory-startup --python tools/blender/bootstrap/bootstrap_male_base.py
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
BLENDS = os.path.join(ROOT, "art-src", "blender")
V1 = os.path.join(BLENDS, "fighters", "wolf_production.blend")
SOURCE = os.path.join(BLENDS, "characters", "reference", "model_a.blend")
OUT = os.path.join(BLENDS, "characters", "male_base.blend")
BODY = "Body"
SKULL = "BodyASkull"
TORSO_SOURCE = "BodyATorso"
AUTHORING_POSE = "riposte_authoring_pose"

## Model A's crown is 1.785 m; WolfRig's Head tail and the height invariant are 1.80 m.
HEAD_LIFT_M = 0.015
## The skull's planes survive planar decimation below this angle; the collapse
## pass then holds the head to its share of the hero budget.
HEAD_PLANAR_DEGREES = 6.0
HEAD_TRIANGLES = 560
## v1's own head (Head-dominant vertices above the jaw) is removed. The open
## ring left at the top of the neck is carried up and in, so the neck enters
## Model A's skull instead of stopping short of its rear underside.
V1_HEAD_CUT_Z = 1.535
NECK_ENTRY_Z = 1.60
NECK_ENTRY_SCALE = 0.62
NECK_ENTRY_FORWARD_M = 0.025
## Edges sharper than this stay creases on the head: its two panels, the ridge
## and the nose read as planes; the crown stays rounded.
HEAD_SHARP_DEGREES = 28.0

## The torso, Hips/Spine/Chest: (z, width scale, depth scale) about the body's
## centre line, linear between stations. v1 is a column (waist = pelvis
## 0.355 m, depth 0.75 of width); the heroic torso tapers to the waist and
## sheds the barrel's depth, and keeps the chest and shoulder breadth. The
## pelvis keeps its depth: the thigh tops meet it, and narrowing it alone
## shelves them.
TORSO = (
    (0.80, 1.00, 1.00),
    (0.90, 1.00, 0.97),
    (0.98, 0.91, 0.86),
    (1.06, 0.82, 0.77),
    (1.14, 0.87, 0.79),
    (1.22, 0.96, 0.82),
    (1.30, 1.00, 0.84),
    (1.38, 1.00, 0.88),
    (1.46, 1.00, 0.94),
    (1.54, 1.00, 1.00),
)
## Limbs: (t along the bone, radial scale) about the bone axis. v1's limbs are
## 20-30% thick for a 1.80 m athlete; the heroic limb keeps the deltoid and the
## muscle bellies and tapers into elbow, wrist, knee and ankle.
LIMBS = {
    "UpperArm": ((0.0, 0.96), (0.3, 0.86), (0.7, 0.83), (1.0, 0.79)),
    "Forearm": ((0.0, 0.84), (0.4, 0.82), (1.0, 0.74)),
    "Hand": ((0.0, 0.88), (1.0, 0.90)),
    "UpperLeg": ((0.0, 0.97), (0.3, 0.87), (0.7, 0.83), (1.0, 0.80)),
    "LowerLeg": ((0.0, 0.80), (0.3, 0.82), (0.7, 0.76), (1.0, 0.72)),
    "Foot": ((0.0, 0.90), (1.0, 0.92)),
    "Neck": ((0.0, 0.94), (1.0, 0.94)),
}
TORSO_BONES = ("Hips", "Spine", "Chest")
## The hand band in Model A's A-pose: the arm's end, measured off its surface.
A_POSE_HAND_X = (0.80, 0.90)


def _piecewise(stations, at):
    if at <= stations[0][0]:
        return stations[0][1:]
    for (a, *va), (b, *vb) in zip(stations, stations[1:]):
        if at <= b:
            k = (at - a) / (b - a)
            return tuple(x + (y - x) * k for x, y in zip(va, vb))
    return stations[-1][1:]


def _family(bone_name):
    return bone_name.split(".")[0]


def _torso_target(p):
    sx, sy = _piecewise(TORSO, p.z)
    return Vector((p.x * sx, p.y * sy, p.z))


def _limb_target(p, head, tail, stations):
    axis = tail - head
    length = axis.length
    direction = axis / length
    t = max(0.0, min(1.0, (p - head).dot(direction) / length))
    foot = head + direction * (t * length)
    (scale,) = _piecewise(stations, t)
    return foot + (p - foot) * scale


def heroic_pass(body, rig):
    """Every vertex moves by the weighted blend of its bones' targets, so a
    shared vertex at a joint takes a blend of smooth fields, never a step."""
    names = {g.index: g.name for g in body.vertex_groups}
    bones = {b.name: (b.head_local.copy(), b.tail_local.copy()) for b in rig.data.bones}
    for vertex in body.data.vertices:
        p = vertex.co.copy()
        moved = Vector()
        for group in vertex.groups:
            name = names[group.group]
            family = _family(name)
            if family in TORSO_BONES:
                target = _torso_target(p)
            elif family in LIMBS:
                head, tail = bones[name]
                target = _limb_target(p, head, tail, LIMBS[family])
            else:
                target = p
            moved += (target - p) * group.weight
        vertex.co = p + moved


def _append(names):
    with bpy.data.libraries.load(SOURCE, link=False) as (source, target):
        target.objects = [n for n in source.objects if n in names]
    for obj in target.objects:
        bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.update()
    return {obj.name: obj for obj in target.objects}


def _a_pose_arm(torso, shoulder):
    """Model A's upper-arm direction in the A-pose: shoulder joint to the hand band."""
    world = (torso.matrix_world @ v.co for v in torso.data.vertices)
    band = [p for p in world if A_POSE_HAND_X[0] <= p.x <= A_POSE_HAND_X[1]]
    hand = sum(band, Vector()) / len(band)
    return (hand - shoulder).normalized()


def reduce_head(skull):
    skull.location.z += HEAD_LIFT_M
    planar = skull.modifiers.new("Planes", "DECIMATE")
    planar.decimate_type = "DISSOLVE"
    planar.angle_limit = math.radians(HEAD_PLANAR_DEGREES)
    triangulate = skull.modifiers.new("Triangles", "TRIANGULATE")
    collapse = skull.modifiers.new("Budget", "DECIMATE")
    collapse.decimate_type = "COLLAPSE"
    bpy.context.view_layer.objects.active = skull
    bpy.ops.object.modifier_apply(modifier=planar.name)
    bpy.ops.object.modifier_apply(modifier=triangulate.name)
    collapse.ratio = min(1.0, HEAD_TRIANGLES / max(1, len(skull.data.polygons)))
    bpy.ops.object.modifier_apply(modifier=collapse.name)
    skull.data.transform(skull.matrix_world)
    skull.matrix_world = Matrix.Identity(4)
    for polygon in skull.data.polygons:
        polygon.use_smooth = True
    skull.data.set_sharp_from_angle(angle=math.radians(HEAD_SHARP_DEGREES))


def remove_v1_head(body):
    names = {g.index: g.name for g in body.vertex_groups}
    bm = bmesh.new()
    bm.from_mesh(body.data)
    deform = bm.verts.layers.deform.active
    doomed = []
    for v in bm.verts:
        weights = v[deform]
        head = sum(w for g, w in weights.items() if names[g] == "Head")
        if head >= 0.5 and v.co.z > V1_HEAD_CUT_Z:
            doomed.append(v)
    bmesh.ops.delete(bm, geom=doomed, context="VERTS")
    rim = {v for e in bm.edges if e.is_boundary for v in e.verts}
    centre = sum((v.co for v in rim), Vector()) / len(rim)
    for v in rim:
        v.co.x = centre.x + (v.co.x - centre.x) * NECK_ENTRY_SCALE
        v.co.y = centre.y - NECK_ENTRY_FORWARD_M + (v.co.y - centre.y) * NECK_ENTRY_SCALE
        v.co.z = NECK_ENTRY_Z
    bm.to_mesh(body.data)
    bm.free()
    return len(doomed)


def join_head(body, skull):
    skull.data.materials.clear()
    for material in body.data.materials:
        skull.data.materials.append(material)
    group = skull.vertex_groups.new(name="Head")
    group.add(list(range(len(skull.data.vertices))), 1.0, "REPLACE")
    bpy.ops.object.select_all(action="DESELECT")
    skull.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()


def authoring_pose(rig, arm_direction):
    """Pose quaternions that put the rest skeleton into Model A's A-pose: arms
    down and out along Model A's, legs plumb. Stored, never applied as rest."""
    down = Vector((0.0, 0.0, -1.0))
    targets = {}
    for side, sign in ((".L", 1.0), (".R", -1.0)):
        arm = Vector((arm_direction.x * sign, arm_direction.y, arm_direction.z))
        for bone in ("UpperArm", "Forearm", "Hand"):
            targets[bone + side] = arm
        for bone in ("UpperLeg", "LowerLeg"):
            targets[bone + side] = down
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    modes = {pb.name: pb.rotation_mode for pb in rig.pose.bones}
    action = rig.animation_data.action if rig.animation_data else None
    if rig.animation_data:
        rig.animation_data.action = None
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
    recorded = {}
    for pb in rig.pose.bones:
        if pb.name not in targets:
            continue
        bpy.context.view_layer.update()
        current = pb.matrix.copy()
        turn = current.col[1].xyz.normalized().rotation_difference(targets[pb.name])
        head = current.translation.copy()
        pb.matrix = Matrix.Translation(head) @ turn.to_matrix().to_4x4() @ Matrix.Translation(-head) @ current
        bpy.context.view_layer.update()
        recorded[pb.name] = [round(c, 6) for c in pb.rotation_quaternion]
    for pb in rig.pose.bones:
        pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pb.location = (0.0, 0.0, 0.0)
        pb.rotation_mode = modes[pb.name]
    if action is not None:
        rig.animation_data.action = action
    bpy.ops.object.mode_set(mode="OBJECT")
    rig[AUTHORING_POSE] = json.dumps(recorded, sort_keys=True)
    return recorded


def main():
    if os.path.exists(OUT) and "--replace-master" not in sys.argv:
        raise SystemExit("RIPOSTE_MASTER_EXISTS %s: the master is edited in Blender; pass --replace-master to discard those edits" % OUT)
    bpy.ops.wm.open_mainfile(filepath=V1)
    body = bpy.data.objects[BODY]
    rig = body.parent
    assert body.matrix_world == Matrix.Identity(4) and rig.matrix_world == Matrix.Identity(4)
    before = len(body.data.polygons)
    heroic_pass(body, rig)
    removed = remove_v1_head(body)
    source = _append({SKULL, TORSO_SOURCE})
    shoulder = rig.data.bones["UpperArm.L"].head_local
    arm = _a_pose_arm(source[TORSO_SOURCE], shoulder)
    bpy.data.objects.remove(source[TORSO_SOURCE], do_unlink=True)
    skull = source[SKULL]
    reduce_head(skull)
    join_head(body, skull)
    body.name = BODY
    pose = authoring_pose(rig, arm)
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    print("RIPOSTE_BASE_FACES", before, "->", len(body.data.polygons), "tris", tris, "v1 head verts removed", removed)
    print("RIPOSTE_BASE_A_POSE_ARM", [round(c, 3) for c in arm], "bones", len(pose))
    bpy.ops.outliner.orphans_purge(do_recursive=True)
    bpy.ops.wm.save_as_mainfile(filepath=OUT, compress=True)
    print("RIPOSTE_BUILT", OUT)


if __name__ == "__main__":
    main()
