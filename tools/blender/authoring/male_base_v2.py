"""The approved male base v2 (2026-10-31): one deterministic build from the frozen v1 master.

Approved by the person on 2026-10-31 (review `r1`). The base is two authored objects on
v1's rig, built in stages from `male_base.blend` (v1, never edited) and saved as
`male_base.v2.blend`, the Blender-owned source of the approved form:

- `BodyV2` (body, no head): v1's body in the stored A-pose without the head island,
  closed and voxel-remeshed (b0), the large anatomical forms (b1), then the heroic
  proportions as broad fields (w1, `HERO`: shoulder girdle, ribcage, arms, thighs, calves,
  neck, trapezius, upper back, lats, glutes). b1's surface is stored on the object
  (`riposte_b1_co`) for comparison.
- `HeadV2`: the approved head (2026-10-31, FACE-IDENTITY-001): v1's head island with its
  face subdivided (f0, no shape change) is the construction surface; the paneled mask face
  (`character_modeling.face_mask`) is built as its own topology on it and zipped to the
  skull (f2, `build_face`). The construction surface stays on the head (`riposte_f0_co`):
  hair and attachments frame on it, never on the face.

`Body` (v1: skinned, 16 physique keys) stays in the file as the rig's reference: weights
and configuration keys transfer from it. Nothing here moves a bone, the rest or the bind.

The record `male_base.v2.record.json` holds each object's fingerprint (vertex and face
counts and a digest of its rounded coordinates and faces); `--verify` rebuilds in memory
and compares with the record and with the saved file, so the source and its build cannot
drift apart silently.

    blender --background --factory-startup --python tools/blender/authoring/male_base_v2.py -- --build
    blender --background --factory-startup --python tools/blender/authoring/male_base_v2.py -- --verify
    blender --background --factory-startup --python tools/blender/authoring/male_base_v2.py -- --foundation
    blender --background --factory-startup --python tools/blender/authoring/male_base_v2.py -- --verify-foundation

`--foundation` builds the default foundation's base (`male_base.foundation.json`: this build
with its mask and body studies) into its own source and record; `--verify-foundation`
rebuilds it in memory and compares.
"""

import hashlib
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector  # noqa: F401  (Matrix is used by the frame helpers)
from mathutils.bvhtree import BVHTree

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
CHARACTERS = os.path.join(ROOT, "art-src", "blender", "characters")
MASTER_V1 = os.path.join(CHARACTERS, "male_base.blend")
CANDIDATE = os.path.join(CHARACTERS, "male_base.v2.blend")
## A review build of the base (an iteration folder's blend) that the fitting tools read in
## place of the approved source; `--build` refuses while it is set.
REVIEW_BASE = os.environ.get("RIPOSTE_BASE_REVIEW", "")
if REVIEW_BASE:
    CANDIDATE = REVIEW_BASE
RECORD = os.path.join(CHARACTERS, "male_base.v2.record.json")
## The default foundation (CHARACTER-FOUNDATION-001): its base is this build with the
## foundation's mask and body studies, saved as the foundation's own source and record. The
## document is the library's current `male_base_foundation` version's
## (`asset_library.current_foundation_document`), or a review copy of it (a candidate's, in
## its iteration folder) that the variation builder reads in its place and that never
## writes the lock.
REVIEW_FOUNDATION = os.environ.get("RIPOSTE_FOUNDATION_REVIEW", "")
SCULPT = "BodyV2"
STUDY = "HeadV2"
HEAD_APPROVAL = ("2026-10-31 (iteration 20261031_2057_head_v1_shape: the mask face on v1's head shape); "
                 "2026-11-01 bridge and brow ridge softened (face_mask.SOFT_EDGES, iteration 20261101_0640_soft_bridge_brow)")
## f0's construction head: built, framed on, and removed inside one build.
CONSTRUCTION_HEAD = "HeadConstruction"
COLLECTION = "V2"
AUTHORING_POSE = "riposte_authoring_pose"
HEAD = "Head"
HEAD_ISLAND_MIN_WEIGHT = 0.99
HEAD_ISLAND_MIN_Z = 1.5
## Sculpt resolution: a 6 mm voxel holds a fingertip-scale form and a muscle groove.
VOXEL_M = 0.006
## The face region f0 subdivides: in front of this depth (metres from the head's front),
## between these height fractions. Two passes: four times the vertices on the panels.
FACE_DEPTH_M = 0.07
FACE_BAND = (0.0, 0.95)
PASSES = 2
## Fingerprints round coordinates to this many metres' decimals (0.01 mm).
FINGERPRINT_DECIMALS = 5


def _sculpt():
    return bpy.data.objects[SCULPT]


def _rig():
    return bpy.data.objects["Armature"]


def _body():
    return bpy.data.objects["Body"]


def apose():
    """Pose the rig in the master's stored A-pose (the sculpt's space)."""
    rig = _rig()
    rig.animation_data_clear()
    for bone, quaternion in json.loads(rig[AUTHORING_POSE]).items():
        pose_bone = rig.pose.bones[bone]
        pose_bone.rotation_mode = "QUATERNION"
        pose_bone.rotation_quaternion = quaternion
    bpy.context.view_layer.update()


def bone_frame(name):
    """The posed bone's world matrix, head and tail (the A-pose landmarks)."""
    rig = _rig()
    pb = rig.pose.bones[name]
    m = rig.matrix_world @ pb.matrix
    return m, rig.matrix_world @ pb.head, rig.matrix_world @ pb.tail


def _head_island(body):
    head = body.vertex_groups[HEAD].index
    return {v.index for v in body.data.vertices
            if (body.matrix_world @ v.co).z > HEAD_ISLAND_MIN_Z
            and any(g.group == head and g.weight >= HEAD_ISLAND_MIN_WEIGHT for g in v.groups)}


def _set_active(obj):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def _apply(obj, modifier):
    _set_active(obj)
    ## The object passed explicitly: an interactive session (the Blender MCP) has no object
    ## context of its own for the operator.
    with bpy.context.temp_override(object=obj, active_object=obj, selected_objects=[obj], selected_editable_objects=[obj]):
        bpy.ops.object.modifier_apply(modifier=modifier.name)


def _smooth(obj, factor, repeat):
    m = obj.modifiers.new("Smooth", "SMOOTH")
    m.factor, m.iterations = factor, repeat
    _apply(obj, m)


def _symmetrize(obj):
    """Mirror +X onto -X (the A-pose is symmetric; the sculpt is authored once)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.symmetrize(bm, input=bm.verts[:] + bm.edges[:] + bm.faces[:], direction="X", dist=1e-4)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def b0():
    """The sculpt surface: v1's body in the A-pose without the protected head, closed,
    voxel-remeshed to a uniform dense surface (the 8-sided tubes and the shoulder shelf
    fuse into one form), smoothed out of its facets, mirrored."""
    if SCULPT in bpy.data.objects:
        raise SystemExit("RIPOSTE_V2: %s exists; b0 runs once" % SCULPT)
    apose()
    body = _body()
    island = _head_island(body)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = body.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    evaluated.to_mesh_clear()
    bm.transform(body.matrix_world)
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if all(v.index in island for v in f.verts)], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=64)
    data = bpy.data.meshes.new(SCULPT)
    bm.to_mesh(data)
    bm.free()
    collection = bpy.data.collections.get(COLLECTION) or bpy.data.collections.new(COLLECTION)
    if collection.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(collection)
    obj = bpy.data.objects.new(SCULPT, data)
    collection.objects.link(obj)
    remesh = obj.modifiers.new("Remesh", "REMESH")
    remesh.mode, remesh.voxel_size, remesh.use_smooth_shade = "VOXEL", VOXEL_M, True
    _apply(obj, remesh)
    _smooth(obj, 0.8, 12)
    _symmetrize(obj)
    for p in obj.data.polygons:
        p.use_smooth = True
    return {"faces": len(obj.data.polygons), "vertices": len(obj.data.vertices)}


def _laplacian(obj, iterations, factor=1.0):
    m = obj.modifiers.new("Relax", "LAPLACIANSMOOTH")
    m.iterations, m.lambda_factor, m.use_volume_preserve, m.use_normalized = iterations, factor, True, True
    _apply(obj, m)


def _frame(axis, front=Vector((0.0, -1.0, 0.0))):
    """An orthonormal frame (along, front, side) for a limb axis."""
    a = axis.normalized()
    f = (front - a * front.dot(a)).normalized()
    return a, f, a.cross(f).normalized()


def _limb(bone, t, front=0.0, side=0.0):
    """A point `t` of the way along a posed (left) bone, offset towards its front (-Y
    projected off the bone) and its side (along x front)."""
    _m, head, tail = bone_frame(bone)
    a, f, s = _frame(tail - head)
    return head + (tail - head) * t + f * front + s * side


def form(centre, radii, amount, axes=None):
    """A smooth mass (amount > 0) or groove (amount < 0) displacing the surface along
    its normal: a 3D Gaussian of `radii` metres along `axes` (default world X, Y, Z)."""
    axes = axes or (Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)))
    return {"c": Vector(centre), "r": radii, "a": amount, "e": [Vector(e).normalized() for e in axes]}


def limb_form(bone, t, radii, amount, front=0.0, side=0.0):
    """A form in a limb's frame: radii along the bone, towards its front, to its side."""
    _m, head, tail = bone_frame(bone)
    return form(_limb(bone, t, front, side), radii, amount, _frame(tail - head))


def _displace(obj, forms):
    """Sum every form at each vertex (mirrored: the sculpt is symmetric in X) and move
    the vertex along its normal by that much. Vectorized: a dense sculpt in seconds
    (run it in background Blender, never inside one MCP request)."""
    import numpy as np
    mesh = obj.data
    mesh.update()
    count = len(mesh.vertices)
    co = np.empty(count * 3)
    normal = np.empty(count * 3)
    mesh.vertices.foreach_get("co", co)
    mesh.vertices.foreach_get("normal", normal)
    co, normal = co.reshape(-1, 3), normal.reshape(-1, 3)
    p = co.copy()
    p[:, 0] = np.abs(p[:, 0])
    d = np.zeros(count)
    for f in forms:
        axes = np.array([tuple(e) for e in f["e"]])
        q = (p - np.array(tuple(f["c"]))) @ axes.T / np.array(f["r"])
        s = (q * q).sum(axis=1)
        d += np.where(s < 16.0, f["a"] * np.exp(-0.5 * s), 0.0)
    co += normal * d[:, None]
    mesh.vertices.foreach_set("co", co.ravel())
    mesh.update()
    return int((np.abs(d) > 1e-6).sum())


def torso_and_limb_forms():
    """The large forms, A-pose metres, left side (mirrored). Named so a review can say
    which to change."""
    J = bone_frame("UpperArm.L")[1]
    arm = (bone_frame("UpperArm.L")[2] - J).normalized()
    forms = {
        ## Chest: full pectoral masses, a lower edge and a sternum valley.
        "pectoral": form((0.098, -0.16, 1.295), (0.085, 0.07, 0.062), 0.018),
        "pectoral_lower_edge": form((0.10, -0.15, 1.222), (0.085, 0.06, 0.011), -0.005),
        "sternum": form((0.0, -0.165, 1.29), (0.013, 0.06, 0.085), -0.006),
        ## Shoulder mantle: a round deltoid cap over the joint, flowing into the pectoral
        ## through a shallow deltopectoral groove; the trapezius slope to the neck.
        "deltoid": form(J + arm * 0.055 + Vector((0.0, -0.005, 0.02)), (0.075, 0.07, 0.062), 0.022,
                        (arm, Vector((0, 1, 0)), arm.cross(Vector((0, 1, 0))))),
        "deltopectoral_groove": form((0.205, -0.115, 1.335), (0.012, 0.05, 0.055), -0.004),
        "trapezius": form((0.12, 0.035, 1.445), (0.085, 0.04, 0.03), 0.013,
                          (Vector((0.88, 0, -0.47)), Vector((0, 1, 0)), Vector((0.47, 0, 0.88)))),
        ## Back: lats widening the flank under the armpit (the V), scapular masses, the
        ## spine valley between the erectors.
        "lat": form((0.165, 0.085, 1.2), (0.05, 0.07, 0.11), 0.015),
        "scapula": form((0.11, 0.155, 1.31), (0.07, 0.05, 0.07), 0.009),
        "spine_valley": form((0.0, 0.15, 1.15), (0.013, 0.06, 0.2), -0.006),
        "erector": form((0.035, 0.13, 1.03), (0.025, 0.05, 0.1), 0.006),
        ## Waist: serratus and external obliques on the ribcage side, a restrained
        ## abdominal panel with its midline, the iliac line.
        "serratus": form((0.165, -0.06, 1.16), (0.04, 0.05, 0.06), 0.007),
        "oblique": form((0.158, -0.035, 1.0), (0.035, 0.06, 0.06), 0.008),
        "abdominal": form((0.045, -0.118, 1.08), (0.05, 0.06, 0.12), 0.006),
        "linea_alba": form((0.0, -0.12, 1.08), (0.009, 0.06, 0.12), -0.004),
        "iliac_line": form((0.1, -0.11, 0.93), (0.045, 0.05, 0.012), -0.003,
                           (Vector((0.7, 0, -0.7)), Vector((0, 1, 0)), Vector((0.7, 0, 0.7)))),
        ## Hips: round glutes, their lower fold.
        "glute": form((0.085, 0.14, 0.86), (0.075, 0.06, 0.08), 0.022),
        "glute_fold": form((0.09, 0.13, 0.775), (0.06, 0.05, 0.012), -0.006),
        ## Upper arm: biceps in front, triceps behind, brachialis low and outside.
        "biceps": limb_form("UpperArm.L", 0.55, (0.07, 0.04, 0.04), 0.012, front=0.03),
        "triceps": limb_form("UpperArm.L", 0.4, (0.09, 0.04, 0.045), 0.012, front=-0.035),
        "brachialis": limb_form("UpperArm.L", 0.78, (0.04, 0.03, 0.03), 0.005, side=0.03),
        "elbow": limb_form("UpperArm.L", 1.0, (0.025, 0.05, 0.05), -0.003),
        ## Forearm: the extensor/brachioradialis mass high and outside, flexors inside,
        ## tapering to the wrist.
        "forearm_extensor": limb_form("Forearm.L", 0.25, (0.08, 0.035, 0.035), 0.011, side=0.022),
        "forearm_flexor": limb_form("Forearm.L", 0.28, (0.08, 0.035, 0.035), 0.008, side=-0.022),
        "wrist": limb_form("Forearm.L", 0.97, (0.03, 0.05, 0.05), -0.005),
        ## Thigh: vastus lateralis outside, rectus femoris in front, the vastus medialis
        ## teardrop above the knee inside, hamstrings behind, adductors inside high.
        "vastus_lateralis": form((0.168, -0.015, 0.62), (0.035, 0.05, 0.14), 0.012),
        "rectus_femoris": form((0.12, -0.085, 0.64), (0.04, 0.04, 0.15), 0.011),
        "vastus_medialis": form((0.083, -0.06, 0.475), (0.03, 0.035, 0.055), 0.012),
        "hamstring": form((0.12, 0.11, 0.65), (0.05, 0.04, 0.14), 0.010),
        "adductor": form((0.065, -0.005, 0.73), (0.03, 0.05, 0.09), 0.006),
        ## Knee: a patella and the narrowing round it.
        "patella": form((0.12, -0.06, 0.42), (0.025, 0.03, 0.028), 0.006),
        "knee": form((0.12, 0.04, 0.4), (0.09, 0.09, 0.025), -0.004),
        ## Calf: two gastrocnemius heads (inner lower and fuller), soleus below, the ankle.
        "gastrocnemius_inner": form((0.1, 0.1, 0.305), (0.03, 0.04, 0.07), 0.015),
        "gastrocnemius_outer": form((0.145, 0.095, 0.325), (0.028, 0.035, 0.06), 0.012),
        "soleus": form((0.12, 0.09, 0.2), (0.045, 0.035, 0.05), 0.005),
        "ankle": form((0.12, 0.04, 0.13), (0.08, 0.08, 0.025), -0.004),
    }
    return forms


def b1():
    """Large forms on the torso, arms and legs (no hands, feet or neck yet)."""
    apose()
    obj = _sculpt()
    _laplacian(obj, 12, 0.8)
    forms = torso_and_limb_forms()
    moved = _displace(obj, list(forms.values()))
    _smooth(obj, 0.5, 3)
    _symmetrize(obj)
    return {"forms": sorted(forms), "moved": moved}


def _transfer_weights(points):
    """Skin weights of v1's posed body at each point (nearest surface, interpolated over
    its polygon): {bone: numpy array}."""
    import numpy as np
    from mathutils.interpolate import poly_3d_calc
    body = _body()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = body.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    verts = [body.matrix_world @ v.co for v in mesh.vertices]
    polys = [list(p.vertices) for p in mesh.polygons]
    evaluated.to_mesh_clear()
    tree = BVHTree.FromPolygons(verts, polys)
    names = [g.name for g in body.vertex_groups]
    table = np.zeros((len(body.data.vertices), len(names)))
    for v in body.data.vertices:
        for g in v.groups:
            table[v.index, g.group] = g.weight
    out = np.zeros((len(points), len(names)))
    for i, p in enumerate(points):
        location, _normal, face, _distance = tree.find_nearest(Vector(p))
        corners = polys[face]
        share = poly_3d_calc([verts[c] for c in corners], location)
        out[i] = sum(s * table[c] for s, c in zip(share, corners))
    return {name: out[:, j] for j, name in enumerate(names)}


def _window(np, t, span):
    """Raised cosine: 0 at span[0], 1 at span[1] (the peak), 0 at span[2]; with four
    values a plateau, 1 from span[1] to span[2] with cosine edges."""
    if len(span) == 4:
        t0, t1, t2, t3 = span
        rise = 0.5 - 0.5 * np.cos(np.pi * np.clip((t - t0) / (t1 - t0), 0.0, 1.0))
        fall = 0.5 + 0.5 * np.cos(np.pi * np.clip((t - t2) / (t3 - t2), 0.0, 1.0))
        return np.minimum(rise, fall) * ((t > t0) & (t < t3))
    t0, tp, t1 = span
    rise = 0.5 - 0.5 * np.cos(np.pi * np.clip((t - t0) / (tp - t0), 0.0, 1.0))
    fall = 0.5 + 0.5 * np.cos(np.pi * np.clip((t - tp) / (t1 - tp), 0.0, 1.0))
    return np.where(t < tp, rise, fall) * ((t > t0) & (t < t1))


def head_frame(points):
    low = min(p.z for p in points)
    high = max(p.z for p in points)
    return {"low": low, "height": high - low, "half_width": max(abs(p.x) for p in points),
            "front": min(p.y for p in points), "back": max(p.y for p in points)}


F0_ATTRIBUTE = "riposte_f0_co"


def _store_f0(obj):
    attribute = obj.data.attributes.get(F0_ATTRIBUTE) or obj.data.attributes.new(F0_ATTRIBUTE, "FLOAT_VECTOR", "POINT")
    for v, a in zip(obj.data.vertices, attribute.data):
        a.vector = v.co


def f0():
    """The construction head: the head island copied, its face triangles subdivided (no
    shape change), its surface stored (`riposte_f0_co`)."""
    if STUDY in bpy.data.objects or CONSTRUCTION_HEAD in bpy.data.objects:
        raise SystemExit("RIPOSTE_HEAD: %s exists; f0 runs once" % STUDY)
    body = _body()
    head = body.vertex_groups[HEAD].index
    world = body.matrix_world
    island = {v.index for v in body.data.vertices
              if (world @ v.co).z > HEAD_ISLAND_MIN_Z and any(g.group == head and g.weight >= HEAD_ISLAND_MIN_WEIGHT for g in v.groups)}
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.transform(world)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if not all(v.index in island for v in f.verts)], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    frame = head_frame([v.co for v in bm.verts])
    before = {tuple(round(c, 6) for c in v.co) for v in bm.verts}
    for _pass in range(PASSES):
        z0 = frame["low"] + FACE_BAND[0] * frame["height"]
        z1 = frame["low"] + FACE_BAND[1] * frame["height"]
        faces = [f for f in bm.faces if all(v.co.y < frame["front"] + FACE_DEPTH_M and z0 <= v.co.z <= z1 for v in f.verts)]
        edges = list({e for f in faces for e in f.edges})
        bmesh.ops.subdivide_edges(bm, edges=edges, cuts=1, use_grid_fill=True)
        bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3])
    data = bpy.data.meshes.new(CONSTRUCTION_HEAD)
    bm.to_mesh(data)
    bm.free()
    for p in data.polygons:
        p.use_smooth = True
    collection = bpy.data.collections.get(COLLECTION) or bpy.data.collections.new(COLLECTION)
    if collection.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(collection)
    obj = bpy.data.objects.new(CONSTRUCTION_HEAD, data)
    collection.objects.link(obj)
    _store_f0(obj)
    kept = sum(1 for v in data.vertices if tuple(round(c, 6) for c in v.co) in before)
    return {"vertices": len(data.vertices), "faces": len(data.polygons), "original_vertices_kept": kept,
            "frame": {k: round(v, 4) for k, v in frame.items()}}


## W1: the hero proportions on b1, as broad fields (metres, A-pose world).
## Radial fields scale the distance from a segment's axis inside a band (raised-cosine
## ends, never a step); shift fields move a broad region along a direction with a Gaussian
## falloff whose radius is large against the form (a mass, not a bump).
HERO = {
    "radial": {
        ## (segment bones, t band (t0, t1, t2, t3) along the bone or z for the torso, scale)
        "ribcage_chest": (("Spine", "Chest"), (1.05, 1.18, 1.38, 1.47), 1.07),
        "upper_arm": (("UpperArm.L",), (-0.1, 0.05, 0.75, 1.05), 1.13),
        "forearm": (("Forearm.L",), (-0.05, 0.1, 0.45, 0.9), 1.08),
        ## Starts below the crotch: scaling the thigh's top pushes the inner thighs together.
        "thigh": (("UpperLeg.L",), (0.08, 0.25, 0.8, 1.02), 1.14),
        "calf": (("LowerLeg.L",), (0.0, 0.15, 0.5, 0.8), 1.08),
        "neck": (("Neck",), (-0.3, 0.0, 0.7, 1.0), 1.15),
    },
    "shift": {
        ## (centre, radius, direction, amount): the deltoid mass carried out past the
        ## joint (bideltoid wider than the shoulder joints), the trapezius raised between
        ## neck and shoulder, the upper back and the glutes carried back.
        "deltoid_breadth": ((0.215, -0.005, 1.39), 0.085, (1.0, 0.0, 0.25), 0.022),
        "trapezius": ((0.105, 0.025, 1.47), 0.07, (0.15, 0.25, 1.0), 0.018),
        "upper_back": ((0.10, 0.11, 1.33), 0.10, (0.25, 1.0, 0.0), 0.014),
        "lat_flare": ((0.16, 0.05, 1.22), 0.09, (1.0, 0.25, 0.0), 0.012),
        "gluteal": ((0.085, 0.13, 0.86), 0.09, (0.1, 1.0, 0.05), 0.020),
        "chest_lift": ((0.09, -0.15, 1.31), 0.10, (0.1, -1.0, 0.15), 0.010),
    },
}


## Foundation design studies of the body (CHARACTER-PHYSIQUE-ART-001): candidate revisions
## of the approved reference, never a configuration. 0 is the approved body; a candidate
## names values (`--body-study`), each scaling its extra HERO shifts (left side, mirrored)
## and multiplying its radial scales. Once one is approved it joins HERO (with a new body
## approval and fingerprint) and its entry here is removed. `heroic_profile` (2026-11-01):
## the side profile read slender and, after a glute-only pass, feminine (hips deeper than a
## shallow upper torso, a pointed glute). A heroic male profile carries its depth in the
## upper torso and the legs: a thick upper back, traps and lats with the chest, deltoid
## mass, quadriceps projecting to the front and side, hamstrings, calves; the glutes one
## broad low mass flowing into the hamstrings, never a point.
BODY_STUDY = {
    "heroic_profile": {
        "shift": {
            "upper_back_depth": ((0.09, 0.14, 1.31), 0.12, (0.1, 1.0, 0.15), 0.018),
            "trapezius_mass": ((0.10, 0.07, 1.45), 0.07, (0.2, 0.5, 1.0), 0.014),
            "lat_flare": ((0.17, 0.06, 1.22), 0.09, (1.0, 0.3, 0.0), 0.012),
            "chest_depth": ((0.09, -0.15, 1.29), 0.10, (0.1, -1.0, 0.1), 0.008),
            "deltoid_mass": ((0.22, 0.0, 1.38), 0.07, (1.0, 0.0, 0.2), 0.010),
            "glute_broad": ((0.09, 0.13, 0.83), 0.11, (0.1, 1.0, -0.2), 0.010),
            "hamstring_depth": ((0.115, 0.10, 0.66), 0.10, (0.0, 1.0, 0.0), 0.012),
            "quad_front": ((0.12, -0.075, 0.64), 0.10, (0.0, -1.0, 0.0), 0.016),
            "vastus_lateral": ((0.175, -0.01, 0.60), 0.08, (1.0, 0.0, 0.0), 0.008),
            "calf_back": ((0.12, 0.10, 0.30), 0.07, (0.0, 1.0, 0.0), 0.008),
        },
        "radial": {"upper_arm": 1.05, "forearm": 1.05},
    },
    ## `chest_profile` (2026-11-01, on heroic_profile): in profile the pectoral peaked low
    ## (its apex at the nipple line) and fell away above it, a breast-like curve. The mass
    ## moves up and spreads over a taller band: the upper pectoral fills under the clavicle
    ## and the lower pectoral's downward bulge tucks up into a defined lower boundary. The
    ## pectoral's width and front view are unchanged; local soft masses, never planes.
    "chest_profile": {
        "shift": {
            "pec_upper_fill": ((0.085, -0.165, 1.395), 0.045, (0.1, -1.0, 0.25), 0.016),
            "pec_lower_tuck": ((0.095, -0.17, 1.205), 0.035, (0.0, 1.0, 0.35), 0.009),
        },
    },
    ## `upper_thorax` (on chest_profile): in profile the torso was a lens, its front and
    ## back both deepest at the nipple line and falling away evenly to the neck and the
    ## waist, a bust over a barrel. A heroic thorax is deepest high: the rib cage itself
    ## widens and deepens from the armpits up to the clavicles (`thorax`: z band, x scale,
    ## front and back depth scales about the torso's axis, weighted by the spine and chest),
    ## fading out above the lower pectoral so the waist and the lower chest keep theirs.
    "upper_thorax": {
        "thorax": {"rib_cage": ((1.26, 1.36, 1.46, 1.53), 1.05, 1.06, 1.02)},
    },
    ## `pectoral_sweep` (on upper_thorax): the pectoral as the fan it is, its clavicular
    ## fibres running from the sternum's top out under the clavicle into the anterior
    ## deltoid (`capsule`: a soft mass along a segment, never a point or a plane), so the
    ## upper and outer chest are full and the shoulder leads into it; the sternum's centre
    ## stays shallow.
    "pectoral_sweep": {
        "capsule": {"clavicular_pec": ((0.045, -0.15, 1.425), (0.19, -0.075, 1.405), 0.032, (0.25, -1.0, 0.1), 0.008),
                    "anterior_deltoid": ((0.19, -0.075, 1.405), (0.225, -0.04, 1.36), 0.03, (0.6, -1.0, 0.0), 0.006)},
    },
    ## `upper_chest_depth` (on pectoral_sweep): a little more front depth of the upper
    ## rib cage alone.
    "upper_chest_depth": {
        "thorax": {"rib_cage_front": ((1.28, 1.37, 1.45, 1.52), 1.0, 1.03, 1.0)},
    },
}

def study_fields(study):
    """HERO plus the named body studies (their shifts scaled by the value, their radial
    scales' growth scaled by it)."""
    fields = {"radial": dict(HERO["radial"]), "shift": dict(HERO["shift"]), "thorax": {}, "capsule": {}}
    for key, value in (study or {}).items():
        if key not in BODY_STUDY:
            raise SystemExit("RIPOSTE_V2: unknown body study %s (known: %s)" % (key, sorted(BODY_STUDY)))
        for name, (centre, radius, direction, amount) in BODY_STUDY[key].get("shift", {}).items():
            fields["shift"]["%s.%s" % (key, name)] = (centre, radius, direction, amount * value)
        for name, (band, sx, front, back) in BODY_STUDY[key].get("thorax", {}).items():
            fields["thorax"]["%s.%s" % (key, name)] = (band, 1.0 + (sx - 1.0) * value, 1.0 + (front - 1.0) * value,
                                                      1.0 + (back - 1.0) * value)
        for name, (a, b, radius, direction, amount) in BODY_STUDY[key].get("capsule", {}).items():
            fields["capsule"]["%s.%s" % (key, name)] = (a, b, radius, direction, amount * value)
        for name, extra in BODY_STUDY[key].get("radial", {}).items():
            bones, band, scale = fields["radial"][name]
            fields["radial"][name] = (bones, band, 1.0 + (scale * (1.0 + (extra - 1.0) * value) - 1.0))
    return fields


B1_ATTRIBUTE = "riposte_b1_co"


def _store(obj):
    import numpy as np
    co = np.empty(len(obj.data.vertices) * 3)
    obj.data.vertices.foreach_get("co", co)
    attribute = obj.data.attributes.get(B1_ATTRIBUTE) or obj.data.attributes.new(B1_ATTRIBUTE, "FLOAT_VECTOR", "POINT")
    attribute.data.foreach_set("vector", co)
    return co.reshape(-1, 3)


def w1(body_study=None):
    """The heroic proportions on b1 (HERO, plus a candidate's `body_study`): radial scales
    along segments and broad shifts."""
    apose()
    obj = _sculpt()
    co = _store(obj)
    return _proportion_fields(obj, co, study_fields(body_study))


def _proportion_fields(obj, co, fields):
    """Apply proportion `fields` (HERO's form: radial scales along segments, broad shifts)
    to `obj` whose A-pose points are `co`, weighted by v1's transferred skin weights."""
    import numpy as np
    weights = _transfer_weights([tuple(c) for c in co])
    p = co.copy()
    sign = np.where(p[:, 0] < 0.0, -1.0, 1.0)
    p[:, 0] = np.abs(p[:, 0])
    out = p.copy()

    def weight(names):
        total = np.zeros(len(p))
        for name in names:
            total += weights.get(name, 0.0)
            if name.endswith(".L"):
                total += weights.get(name[:-2] + ".R", 0.0)
        return np.minimum(total, 1.0)

    for _name, (bones, band, scale) in fields.get("radial", {}).items():
        w = weight(bones)
        if bones[0] in ("Spine", "Chest"):
            t = p[:, 2]
            axis = np.stack([np.zeros(len(p)), np.full(len(p), np.median(p[w > 0.5, 1])), t], axis=1)
            radial = p - axis
            radial[:, 2] = 0.0
        else:
            _m, head, tail = bone_frame(bones[0])
            head, tail = np.array(tuple(head)), np.array(tuple(tail))
            a = (tail - head) / np.linalg.norm(tail - head)
            along = (p - head) @ a
            t = along / np.linalg.norm(tail - head)
            radial = p - (head + along[:, None] * a)
        out += (w * _window(np, t, band) * (scale - 1.0))[:, None] * radial
    torso = weight(("Spine", "Chest"))
    axis_y = np.median(p[torso > 0.5, 1])
    for _name, (band, sx, front, back) in fields.get("thorax", {}).items():
        w = torso * _window(np, p[:, 2], band)
        ry = p[:, 1] - axis_y
        out[:, 0] += w * (sx - 1.0) * p[:, 0]
        out[:, 1] += w * np.where(ry < 0.0, front - 1.0, back - 1.0) * ry
    for _name, (a, b, radius, direction, amount) in fields.get("capsule", {}).items():
        a, b = np.array(a), np.array(b)
        d = np.array(direction) / np.linalg.norm(direction)
        s = np.clip((p - a) @ (b - a) / np.dot(b - a, b - a), 0.0, 1.0)
        r = np.linalg.norm(p - (a + s[:, None] * (b - a)), axis=1)
        out += (amount * np.exp(-0.5 * (r / radius) ** 2))[:, None] * d
    for _name, (centre, radius, direction, amount) in fields.get("shift", {}).items():
        d = np.array(direction) / np.linalg.norm(direction)
        r = np.linalg.norm(p - np.array(centre), axis=1)
        out += (amount * np.exp(-0.5 * (r / radius) ** 2))[:, None] * d
    out[:, 0] *= sign
    obj.data.vertices.foreach_set("co", out.ravel())
    obj.data.update()
    return {"max_move_mm": round(float(np.linalg.norm(out - co, axis=1).max()) * 1000, 1)}


## n1 (candidate, not a build stage until approved), the neck seated in the head
## (CHARACTER-VARIATION-001). The neck's upper termination
## overlaps the head on purpose: under the jaw and at the nape, the seam. Where it would
## instead come through the jaw's sides or the face above its lower edge row (a body face
## crossing a DEFECT_CLASSES head face, `head_face_classes`), the neck narrows there toward its own axis (the Neck bone,
## horizontally) just enough to pass NECK_SEAT_M inside that head face. The narrowing is one
## smooth field: each body vertex takes the strongest Gaussian-weighted (NECK_EASE_M)
## requirement of the crossing vertices around it, relaxed over the mesh (NECK_RELAX
## rounds, never below a crossing vertex's own requirement): a local narrowing just under
## the jaw, never a dent or a fold, and the intended overlap stays. Every resolved head and body (every
## configuration) is seated the same way, in the authoring A-pose.
NECK_SEAT_M = 0.002
## A poking vertex is never more than this outside the jaw (beyond it is the shoulder).
NECK_REACH_M = 0.015
## The poking patch: body vertices this near a crossing.
NECK_PATCH_M = 0.012
NECK_EASE_M = 0.012
NECK_RELAX = 12
NECK_PASSES = 8
## A head face whose normal points down more steeply than this is the underside (the seam).
UNDERSIDE_NORMAL_Z = 0.5
## A narrowing toward the axis that meets the crossed face this obliquely is not used.
MIN_APPROACH = 0.2


## Where the body may cross the head (the intended seam) and where it may not.
SEAM_CLASSES = ("underside", "nape", "jaw_edge")
## The neck covers the jaw's lower edge row by at most this (outside the row's faces);
## more is the neck showing over the jaw, a defect.
JAW_EDGE_COVER_M = 0.005
DEFECT_CLASSES = ("side", "front", "up")


def seam_face(normal):
    """A head face where the neck may overlap it: the underside or the nape."""
    return normal.z < -UNDERSIDE_NORMAL_Z or (normal.y > abs(normal.x) and normal.y > 0.3)


def head_face_classes(head):
    """Each head face's class for head-neck integration (CHARACTER-VARIATION-001): by its
    facing, `underside` (under the jaw), `nape` (the lower occiput, facing back), `front`,
    `up` or `side`; a side or front face sharing a vertex with the underside is the jaw's
    lower edge row, `jaw_edge`: the neck covering it is what keeps the junction clean, so
    it is seam with the underside and nape (SEAM_CLASSES); the rest are DEFECT_CLASSES."""
    rotation = head.matrix_world.to_3x3()
    normals = [(rotation @ p.normal).normalized() for p in head.data.polygons]
    classes = []
    for n in normals:
        if n.z < -UNDERSIDE_NORMAL_Z:
            classes.append("underside")
        elif n.y > abs(n.x) and n.y > 0.3:
            classes.append("nape")
        elif n.y < -abs(n.x):
            classes.append("front")
        elif n.z > UNDERSIDE_NORMAL_Z:
            classes.append("up")
        else:
            classes.append("side")
    under = {v for p, kind in zip(head.data.polygons, classes) if kind == "underside" for v in p.vertices}
    for i, p in enumerate(head.data.polygons):
        if classes[i] in ("side", "front") and under.intersection(p.vertices):
            classes[i] = "jaw_edge"
    return classes


def seat_neck(body, head):
    """Seat `body`'s neck inside `head` where it would come through the jaw's sides or the
    face. Returns {"moved_vertices", "eased_vertices", "max_move_mm", "passes", "crossings_left"}."""
    from mathutils.kdtree import KDTree
    head_world, rotation = head.matrix_world, head.matrix_world.to_3x3()
    head_tree = BVHTree.FromPolygons([head_world @ v.co for v in head.data.vertices], [list(p.vertices) for p in head.data.polygons])
    normals = [(rotation @ p.normal).normalized() for p in head.data.polygons]
    seam = [kind in SEAM_CLASSES for kind in head_face_classes(head)]
    centres = [sum((head_world @ head.data.vertices[i].co for i in p.vertices), Vector()) / len(p.vertices) for p in head.data.polygons]
    world, inverse = body.matrix_world, body.matrix_world.inverted()
    _m, neck_head, neck_tail = bone_frame("Neck")
    axis = (neck_tail - neck_head).normalized()
    neighbours = {}
    for edge in body.data.edges:
        a, b = edge.vertices
        neighbours.setdefault(a, []).append(b)
        neighbours.setdefault(b, []).append(a)
    report = {"moved_vertices": 0, "eased_vertices": 0, "max_move_mm": 0.0, "passes": []}

    def crossings(points):
        tree = BVHTree.FromPolygons(points, [list(p.vertices) for p in body.data.polygons])
        return [(h, b) for h, b in head_tree.overlap(tree) if not seam[h]]

    def inward(p):
        """The horizontal direction from `p` to the neck's axis."""
        on_axis = neck_head + axis * (p - neck_head).dot(axis)
        d = on_axis - p
        d.z = 0.0
        return d.normalized() if d.length > 1e-6 else None

    for _pass in range(NECK_PASSES):
        points = [world @ v.co for v in body.data.vertices]
        moves = {}
        for h, b in crossings(points):
            frontier, seen = list(body.data.polygons[b].vertices), set()
            origin = sum((points[i] for i in frontier), Vector()) / len(frontier)
            while frontier:
                i = frontier.pop()
                if i in seen:
                    continue
                seen.add(i)
                depth = (points[i] - centres[h]).dot(normals[h])
                if depth <= -NECK_SEAT_M or (points[i] - origin).length > NECK_PATCH_M:
                    continue
                d = inward(points[i])
                approach = -d.dot(normals[h]) if d is not None else 0.0
                if depth < NECK_REACH_M and approach > MIN_APPROACH:
                    move = d * ((depth + NECK_SEAT_M) / approach)
                    if i not in moves or move.length > moves[i].length:
                        moves[i] = move
                frontier += neighbours.get(i, [])
        if not moves:
            break
        kd = KDTree(len(moves))
        for k, i in enumerate(moves):
            kd.insert(points[i], k)
        kd.balance()
        keys = list(moves)
        need = {i: m.length for i, m in moves.items()}
        amount = {}
        for i, p in enumerate(points):
            best = need.get(i, 0.0)
            for _co, k, distance in kd.find_range(p, 2.5 * NECK_EASE_M):
                best = max(best, need[keys[k]] * math.exp(-(distance / NECK_EASE_M) ** 2))
            if best > 1e-5:
                amount[i] = best
        for _round in range(NECK_RELAX):
            relaxed = {}
            for i, value in amount.items():
                around = [amount.get(j, 0.0) for j in neighbours.get(i, ())]
                mean = 0.5 * value + 0.5 * sum(around) / max(1, len(around))
                relaxed[i] = max(mean, need.get(i, 0.0))
            amount = relaxed
        eased = {i: v for i, v in amount.items() if i not in moves}
        for i, value in amount.items():
            d = inward(points[i])
            if d is not None:
                body.data.vertices[i].co = inverse @ (points[i] + d * value)
        body.data.update()
        report["passes"].append([len(moves), len(crossings([world @ v.co for v in body.data.vertices]))])
        report["moved_vertices"] += len(moves)
        report["eased_vertices"] += len(eased)
        report["max_move_mm"] = max(report["max_move_mm"], round(max(m.length for m in moves.values()) * 1000, 2))
    report["crossings_left"] = len(crossings([world @ v.co for v in body.data.vertices]))
    return report


def build(mask_study=None, body_study=None):
    """Every stage, from the open v1 master, in order. Returns the stage reports.
    `mask_study`: a candidate's foundation design study values (`face_mask.MASK_STUDY`,
    `EDGE_SOFTNESS`); `body_study` the body's (`BODY_STUDY`); None is the approved one."""
    report = {"b0": b0(), "b1": b1(), "w1": w1(body_study), "f0": f0()}
    _head, report["f2"] = build_face(source=CONSTRUCTION_HEAD, name=STUDY, parameters=mask_study)
    construction = bpy.data.objects[CONSTRUCTION_HEAD]
    mesh = construction.data
    bpy.data.objects.remove(construction, do_unlink=True)
    bpy.data.meshes.remove(mesh)
    return report


## The bind (production skinning of the approved form on WolfRig, CHARACTER-SOURCE-001):
## v1's weights carried as the starting point (nearest point of v1's posed surface,
## interpolated), at most MAX_INFLUENCES per vertex, below MIN_INFLUENCE pruned,
## normalized; then each vertex returned from the authoring A-pose to the rig's rest by
## the inverse of its own blended skinning matrix, so the bound body posed in the A-pose
## is the approved form again (the round trip is measured). The rig never moves.
BOUND = "Body"
V1_REFERENCE = "BodyV1"
MAX_INFLUENCES = 4
MIN_INFLUENCE = 0.01
## v1's configuration keys carried onto the dense form are smoothed over its edges so v1's
## facets (~40 mm wide) do not print into the sculpt.
DELTA_SMOOTH_ITERATIONS = 40
## The head's construction surface (the skull before its face forms) in the bound body:
## hair fits measure their frame on it (a longer nose never moves the hair).
CONSTRUCTION_ATTRIBUTE = "riposte_construction_co"


def _points(obj):
    import numpy as np
    co = np.empty(len(obj.data.vertices) * 3)
    obj.data.vertices.foreach_get("co", co)
    m = np.array(obj.matrix_world)
    return co.reshape(-1, 3) @ m[:3, :3].T + m[:3, 3]


def _evaluated_points(obj):
    import numpy as np
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh = obj.evaluated_get(depsgraph).to_mesh()
    co = np.empty(len(mesh.vertices) * 3)
    mesh.vertices.foreach_get("co", co)
    obj.evaluated_get(depsgraph).to_mesh_clear()
    m = np.array(obj.matrix_world)
    return co.reshape(-1, 3) @ m[:3, :3].T + m[:3, 3]


def key_deltas(points, edges):
    """{key name: (n, 3) delta}: v1's configuration keys evaluated in the A-pose and
    carried to `points` (A-pose world) by the nearest point of v1's posed surface, then
    smoothed over `edges`."""
    import numpy as np
    from mathutils.interpolate import poly_3d_calc
    apose()
    body = _body()
    blocks = body.data.shape_keys.key_blocks
    for block in blocks[1:]:
        block.value = 0.0
    basis = _evaluated_points(body)
    posed = {}
    for block in blocks[1:]:
        block.value = 1.0
        posed[block.name] = _evaluated_points(body) - basis
        block.value = 0.0
    faces = [list(p.vertices) for p in body.data.polygons]
    tree = BVHTree.FromPolygons([Vector(p) for p in basis], faces)
    count = len(points)
    index = np.zeros((count, 4), dtype=np.int64)
    weight = np.zeros((count, 4))
    for i, p in enumerate(points):
        location, _n, face, _d = tree.find_nearest(Vector(p))
        corners = faces[face]
        index[i, :len(corners)] = corners
        weight[i, :len(corners)] = poly_3d_calc([Vector(basis[c]) for c in corners], location)
    degree = np.bincount(edges.ravel(), minlength=count).astype(float)
    out = {}
    for name, delta in posed.items():
        d = (weight[:, :, None] * delta[index]).sum(axis=1)
        for _round in range(DELTA_SMOOTH_ITERATIONS):
            total = np.zeros_like(d)
            np.add.at(total, edges[:, 0], d[edges[:, 1]])
            np.add.at(total, edges[:, 1], d[edges[:, 0]])
            d = 0.5 * d + 0.5 * total / np.maximum(degree, 1.0)[:, None]
        out[name] = d
    return out


def sparse_weights(weights):
    """{bone: (n,) weight} -> (bone names, (n, k) weights): at most MAX_INFLUENCES per
    vertex, below MIN_INFLUENCE pruned, normalized. Deterministic (ties by bone order)."""
    import numpy as np
    names = sorted(weights)
    table = np.stack([weights[n] for n in names], axis=1)
    order = np.argsort(-table, axis=1, kind="stable")[:, :MAX_INFLUENCES]
    keep = np.zeros_like(table, dtype=bool)
    np.put_along_axis(keep, order, True, axis=1)
    table = np.where(keep & (table >= MIN_INFLUENCE), table, 0.0)
    total = table.sum(axis=1, keepdims=True)
    if (total <= 0.0).any():
        raise SystemExit("RIPOSTE_V2: %d vertices have no influence" % int((total <= 0.0).sum()))
    return names, table / total


def _skinning(names):
    """Each bone's A-pose skinning matrix (rest -> posed), world space, as numpy."""
    import numpy as np
    rig = _rig()
    world, inverse = rig.matrix_world, rig.matrix_world.inverted()
    out = []
    for name in names:
        pose_bone = rig.pose.bones[name]
        out.append(np.array(world @ pose_bone.matrix @ rig.data.bones[name].matrix_local.inverted() @ inverse))
    return np.stack(out)


def _joined(body_name=SCULPT, head_name=STUDY):
    """A body and a head (BodyV2 and HeadV2 by default) as one surface (A-pose world):
    points, faces, and the construction surface (the head's skull, the body's own points)."""
    import numpy as np
    body, head = bpy.data.objects[body_name], bpy.data.objects[head_name]
    points = np.concatenate([_points(body), _points(head)])
    stored = np.array([tuple(a.vector) for a in head.data.attributes[F0_ATTRIBUTE].data])
    m = np.array(head.matrix_world)
    construction = np.concatenate([_points(body), stored @ m[:3, :3].T + m[:3, 3]])
    offset = len(body.data.vertices)
    faces = [list(p.vertices) for p in body.data.polygons] + [[offset + i for i in p.vertices] for p in head.data.polygons]
    smooth = [p.use_smooth for p in body.data.polygons] + [p.use_smooth for p in head.data.polygons]
    sharp = [(tuple(e.vertices), e.use_edge_sharp) for e in body.data.edges]
    sharp += [((offset + e.vertices[0], offset + e.vertices[1]), e.use_edge_sharp) for e in head.data.edges]
    return points, faces, construction, smooth, {tuple(sorted(k)) for k, s in sharp if s}


def bind(body_name=SCULPT, head_name=STUDY):
    """The bound body `Body` (v1's `Body` kept as `BodyV1`): returns the round-trip report."""
    import numpy as np
    apose()
    points, faces, construction, smooth, sharp = _joined(body_name, head_name)
    weights = _transfer_weights([tuple(p) for p in points])
    names, table = sparse_weights(weights)
    mesh = bpy.data.meshes.new(BOUND)
    mesh.from_pydata([tuple(p) for p in points], [], faces)
    mesh.update()
    edges = np.array([tuple(e.vertices) for e in mesh.edges])
    deltas = key_deltas(points, edges)
    blend = np.einsum("nb,bij->nij", table, _skinning(names))
    unpose = np.linalg.inv(blend)

    def rest(p):
        return np.einsum("nij,nj->ni", unpose[:, :3, :3], p) + unpose[:, :3, 3]

    rest_points = rest(points)
    mesh.vertices.foreach_set("co", rest_points.ravel())
    mesh.polygons.foreach_set("use_smooth", smooth)
    for edge in mesh.edges:
        edge.use_edge_sharp = tuple(sorted(edge.vertices)) in sharp
    attribute = mesh.attributes.new(CONSTRUCTION_ATTRIBUTE, "FLOAT_VECTOR", "POINT")
    attribute.data.foreach_set("vector", rest(construction).ravel())
    _body().name = V1_REFERENCE
    obj = bpy.data.objects.new(BOUND, mesh)
    collection = bpy.data.collections.get(COLLECTION) or bpy.data.collections.new(COLLECTION)
    collection.objects.link(obj)
    for j, name in enumerate(names):
        group = obj.vertex_groups.new(name=name)
        for weight in np.unique(table[:, j][table[:, j] > 0.0]):
            group.add(np.nonzero(table[:, j] == weight)[0].tolist(), float(weight), "REPLACE")
    obj.shape_key_add(name="Basis", from_mix=False)
    for name, delta in deltas.items():
        key = obj.shape_key_add(name=name, from_mix=False)
        moved = rest_points + np.einsum("nij,nj->ni", unpose[:, :3, :3], delta)
        key.data.foreach_set("co", moved.ravel())
        key.value = 0.0
    obj.parent = _rig()
    obj.modifiers.new("Armature", "ARMATURE").object = _rig()
    bpy.context.view_layer.update()
    ## Round trip: the bound body posed in the authoring A-pose is the approved form.
    error = float(np.linalg.norm(_evaluated_points(obj) - points, axis=1).max())
    for pose_bone in _rig().pose.bones:
        pose_bone.matrix_basis.identity()
    for name in {SCULPT, STUDY, V1_REFERENCE, body_name, head_name}:
        bpy.data.objects[name].hide_render = True
        bpy.data.objects[name].hide_set(True)
    influences = (table > 0.0).sum(axis=1)
    return {"vertices": len(points), "bones": names, "round_trip_max_mm": round(error * 1000, 4),
            "influences": {str(k): int((influences == k).sum()) for k in range(1, MAX_INFLUENCES + 1)},
            "keys": sorted(deltas)}


## The heroic paneled mask (FACE-IDENTITY-001, `character_modeling.face_mask`): the face's
## own topology on the head's construction surface.
## The face's panel turns shade as edges only above this angle: softened, never razor-sharp
## (the geometry carries the turn).
FACE_EDGE_DEG = 40.0
## A skull vertex is on the front sheet (the face's chart covers it) within this of the
## front-most surface at its (x, z).
FRONT_SHEET_M = 0.002
## The seam between the face and the skull is refined until no edge is longer than this,
## every new vertex put back on the construction surface (a chord across the skull's
## curvature would cut inside it and print a crease).
SEAM_EDGE_M = 0.008
SEAM_PASSES = 6
## The face eases into the skull: vertices within BLEND_M of the boundary (both sides) are
## relaxed, fully at the boundary and not at all at BLEND_M, so no perimeter reads; the
## panel turns inside stay as built.
BLEND_M = 0.015
BLEND_PASSES = 12
## With `face_mask.LOWER_CONTOUR`: under the jaw (the boundary below the jaw's corner plus
## LOWER_BLEND_ABOVE_M) the face meets the skull at an angle (the corner under the chin at
## chin_low, the border's dip at jaw_low, its step at jaw_angle: HEAD-CONTOUR-001), so the
## band there is widened by LOWER_BLEND_M per unit of the study (at most one unit).
LOWER_BLEND_M = 0.015
LOWER_BLEND_ABOVE_M = 0.004
## With it the lower face is split LOWER_CUTS times per edge, smoothly (`subdivide_edges`
## smooth: the new vertices follow the vertex normals, a curve through the old ones).
LOWER_CUTS = 2
LOWER_SMOOTH = 1.0
## The skull's underside (`_underside`): below UNDERSIDE_V of the head's height (mid-ear: a
## rim at the ear lobe crossed the jaw's rear rise in view, a crease against the coarse
## facets above), edges over UNDERSIDE_EDGE_M split flat, then UNDERSIDE_PASSES Taubin
## passes (LAMBDA smooths, MU inflates back; 12 left ripples at the coarse triangles' ~3 cm
## spacing on the jaw's side), the weight rising over UNDERSIDE_FADE_M.
UNDERSIDE_V = 0.50
## And in front of UNDERSIDE_DEPTH of the head's depth: the jaw and the junction, never the
## nape the hair hangs from (smoothing it moved the hanging hair into the body).
UNDERSIDE_DEPTH = 0.75
UNDERSIDE_EDGE_M = 0.008
UNDERSIDE_PASSES = 30
UNDERSIDE_LAMBDA = 0.5
UNDERSIDE_MU = -0.53
UNDERSIDE_FADE_M = 0.025
UNDERSIDE_IN_M = 0.001
## The skull's hole keeps at least this distance from the face boundary (a hole vertex on
## the boundary would zip into needle triangles).
SEAM_GAP_M = 0.003
## The skull and seam triangles this near the boundary are re-triangulated for even angles
## (edge rotation only: no vertex moves or is added; the face's panels are never touched).
BEAUTIFY_M = 0.07


def _mask_module():
    sys.path.insert(0, os.path.join(ROOT, "tools", "character_modeling"))
    from character_modeling import face_mask
    return face_mask


class _Construction:
    """A head's construction surface in its chart: the front-most point at (u, v) and the
    smoothed normal there (vertex normals interpolated across the hit triangle)."""

    def __init__(self, points, faces):
        import numpy as np
        self.co = np.asarray(points, dtype=float)
        self.faces = faces
        self.low, self.top = float(self.co[:, 2].min()), float(self.co[:, 2].max())
        self.height = self.top - self.low
        self.half_width = float(np.abs(self.co[:, 0]).max())
        self.front, self.back = float(self.co[:, 1].min()), float(self.co[:, 1].max())
        self.centre = Vector((0.0, (self.front + self.back) / 2.0, self.low + self.height / 2.0))
        normals = np.zeros_like(self.co)
        for f in faces:
            a, b, c = (self.co[i] for i in f[:3])
            normals[list(f)] += np.cross(b - a, c - a)
        self.normals = normals / np.linalg.norm(normals, axis=1)[:, None]
        self.tree = BVHTree.FromPolygons([Vector(p) for p in self.co], faces)

    def chart(self, p):
        return p[0] / self.half_width, (p[2] - self.low) / self.height

    def hit(self, x, z):
        location, _normal, index, _d = self.tree.ray_cast(Vector((x, self.front - 1.0, z)), Vector((0.0, 1.0, 0.0)))
        return location, index

    def onto(self, p):
        """`p` moved onto the surface along the smoothed normal at its nearest point (a
        nearest-point snap would collapse neighbours onto one facet's edge)."""
        nearest, _normal, index, _d = self.tree.find_nearest(p)
        corners = self.faces[index][:3]
        weights = _barycentric_3d(nearest, *(Vector(self.co[i]) for i in corners))
        normal = sum((Vector(self.normals[i]) * w for i, w in zip(corners, weights)), Vector()).normalized()
        location, _n, _i, _d = self.tree.ray_cast(p + normal * 0.03, -normal, 0.06)
        return location if location is not None else nearest

    def at(self, u, v, name=""):
        location, index = self.hit(u * self.half_width, self.low + v * self.height)
        if location is None:
            raise SystemExit("RIPOSTE_FACE: %s (u %.3f, v %.3f) is off the head's front" % (name, u, v))
        corners = self.faces[index][:3]
        a, b, c = (Vector(self.co[i]) for i in corners)
        weights = _barycentric_3d(location, a, b, c)
        normal = sum((Vector(self.normals[i]) * w for i, w in zip(corners, weights)), Vector())
        return location, normal.normalized()


## A placed control's construction point lies this near its chart position (face vertices
## along a panel edge are a third of the edge apart, ~10 mm).
CONTROL_MATCH_M = 0.004


## A resolved head (a morphed copy of the built head, one topology) carries its control
## vertices' indices, found on the head it was copied from (`face_control_indices`): a
## morph moves the chart frame (a taller cranium, a shorter face), so a chart lookup on
## the morphed head would miss them.
CONTROL_INDICES = "riposte_control_vertices"
## On a built head, each control vertex's (1 + index in sorted control names); 0 elsewhere.
CONTROL_ATTRIBUTE = "riposte_control"


def face_controls(head, names, parameters=None):
    """World positions of `face_mask` control vertices `names` (".R": the -x twin) on a head
    built by `build_face`: the control as placed (its construction point plus its lift), so a
    feature attaches to the crease the head has. A resolved head uses its stored indices."""
    if CONTROL_INDICES in head:
        known = json.loads(head[CONTROL_INDICES])
        if all(n in known for n in names):
            return {n: head.matrix_world @ head.data.vertices[known[n]].co for n in names}
    return {n: head.matrix_world @ head.data.vertices[i].co for n, i in face_control_indices(head, names, parameters).items()}


def face_control_indices(head, names, parameters=None):
    """The vertex index of each control vertex `names` on a head built by `build_face`: the
    head's own vertex whose stored construction point lies at the control's chart position
    on the front of the head."""
    from mathutils.kdtree import KDTree
    face_mask = _mask_module()
    tag = head.data.attributes.get(CONTROL_ATTRIBUTE)
    if tag is not None:
        names_all = sorted(face_mask.control_points(None))
        found = {names_all[a.value - 1]: i for i, a in enumerate(tag.data) if a.value > 0}
        missing = [n for n in names if n not in found]
        if missing:
            raise SystemExit("RIPOSTE_FACE: controls %s are not tagged on %s" % (missing, head.name))
        return {n: found[n] for n in names}
    stored = [head.matrix_world @ Vector(a.vector) for a in head.data.attributes[F0_ATTRIBUTE].data]
    low = min(p.z for p in stored)
    height = max(p.z for p in stored) - low
    half_width = max(abs(p.x) for p in stored)
    centre_y = 0.5 * (min(p.y for p in stored) + max(p.y for p in stored))
    front = [i for i, p in enumerate(stored) if p.y < centre_y]
    kd = KDTree(len(front))
    for k, i in enumerate(front):
        kd.insert(Vector((stored[i].x, 0.0, stored[i].z)), k)
    kd.balance()
    controls = face_mask.control_points(parameters)
    out = {}
    for name in names:
        u, v = controls[name][:2]
        _co, k, distance = kd.find(Vector((u * half_width, 0.0, low + v * height)))
        if distance > CONTROL_MATCH_M:
            raise SystemExit("RIPOSTE_FACE: control %s has no vertex on %s (%.1f mm off)" % (name, head.name, distance * 1000))
        out[name] = front[k]
    return out


def _barycentric_3d(p, a, b, c):
    v0, v1, v2 = b - a, c - a, p - a
    d00, d01, d11, d20, d21 = v0.dot(v0), v0.dot(v1), v1.dot(v1), v2.dot(v0), v2.dot(v1)
    den = d00 * d11 - d01 * d01
    wb = (d11 * d20 - d01 * d21) / den
    wc = (d00 * d21 - d01 * d20) / den
    return 1.0 - wb - wc, wb, wc


def _inside(point, polygon):
    x, y = point
    inside = False
    for (x1, y1), (x2, y2) in zip(polygon, polygon[1:] + polygon[:1]):
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
            inside = not inside
    return inside


def _border_loop(bm, verts):
    """The one closed loop of boundary edges among `verts`, in walking order."""
    edges = [e for e in bm.edges if e.is_boundary and e.verts[0] in verts and e.verts[1] in verts]
    neighbours = {}
    for e in edges:
        a, b = e.verts
        neighbours.setdefault(a, []).append(b)
        neighbours.setdefault(b, []).append(a)
    if not neighbours or any(len(n) != 2 for n in neighbours.values()):
        raise SystemExit("RIPOSTE_FACE: the border is not one simple loop (%d edges)" % len(edges))
    start = next(iter(neighbours))
    loop, previous = [start], None
    while True:
        here = loop[-1]
        nxt = neighbours[here][0] if neighbours[here][0] is not previous else neighbours[here][1]
        if nxt is start:
            break
        previous = here
        loop.append(nxt)
    if len(loop) != len(neighbours):
        raise SystemExit("RIPOSTE_FACE: %d border vertices in more than one loop" % len(neighbours))
    return loop


def _boundary_keys(triangles):
    """The refined face's border (edges of one triangle only) as one ordered loop of keys."""
    uses = {}
    for _region, (a, b, c) in triangles:
        for edge in ((a, b), (b, c), (c, a)):
            edge = tuple(sorted(edge))
            uses[edge] = uses.get(edge, 0) + 1
    neighbours = {}
    for (a, b), count in uses.items():
        if count == 1:
            neighbours.setdefault(a, []).append(b)
            neighbours.setdefault(b, []).append(a)
    start = next(iter(neighbours))
    loop, previous = [start], None
    while True:
        here = loop[-1]
        nxt = neighbours[here][0] if neighbours[here][0] != previous else neighbours[here][1]
        if nxt == start:
            return loop
        previous = here
        loop.append(nxt)


def _zip(bm, inner, outer):
    """Triangles between two closed loops on the skull: each walked from its point nearest
    the other's start, in the same direction, advancing whichever is behind — `inner` by
    its arc length, each `outer` point by where it projects onto `inner` (kept monotone),
    so a jagged hole never folds the strip."""
    def signed(loop):
        return sum(a.co.x * b.co.z - b.co.x * a.co.z for a, b in zip(loop, loop[1:] + loop[:1]))

    if (signed(inner) > 0) != (signed(outer) > 0):
        outer = outer[::-1]
    first = min(range(len(outer)), key=lambda i: (outer[i].co - inner[0].co).length)
    outer = outer[first:] + outer[:first]

    def params(loop):
        lengths = [(b.co - a.co).length for a, b in zip(loop, loop[1:] + loop[:1])]
        total, run, out = sum(lengths), 0.0, []
        for length in lengths:
            out.append(run / total)
            run += length
        return out + [1.0]

    ti = params(inner)
    span = ti[1:] + [1.0 + ti[1]]

    def projected(point):
        best = None
        for k, a in enumerate(inner):
            b = inner[(k + 1) % len(inner)]
            ab = b.co - a.co
            t = max(0.0, min(1.0, (point - a.co).dot(ab) / ab.length_squared))
            d = (a.co + ab * t - point).length
            if best is None or d < best[0]:
                best = (d, ti[k] + t * (span[k] - ti[k]))
        return best[1]

    to, running = [], 0.0
    for o in outer:
        x = projected(o.co)
        x = min((x - 1.0, x, x + 1.0), key=lambda c: abs(c - running))
        running = max(running, min(1.0, x))
        to.append(running)
    to[0] = 0.0
    to.append(1.0)
    i = j = 0
    made = []
    while i < len(inner) or j < len(outer):
        if j >= len(outer) or (i < len(inner) and ti[i + 1] <= to[j + 1]):
            made.append(bm.faces.new((inner[i], inner[(i + 1) % len(inner)], outer[j % len(outer)])))
            i += 1
        else:
            made.append(bm.faces.new((inner[i % len(inner)], outer[(j + 1) % len(outer)], outer[j])))
            j += 1
    return made


def _split_triangle(a, b, c, mab, mbc, mca):
    """Red-green refinement of triangle (a, b, c) at the given edge midpoints (None: kept),
    winding preserved; never a straight-angle polygon, so never a zero-area triangle."""
    m = (mab, mbc, mca)
    k = sum(x is not None for x in m)
    if k == 3:
        return [(a, mab, mca), (mab, b, mbc), (mca, mbc, c), (mab, mbc, mca)]
    ## Rotate so the split edges come first.
    corners = [a, b, c]
    while m[0] is None or (k == 2 and m[1] is None):
        corners, m = corners[1:] + corners[:1], m[1:] + m[:1]
    a, b, c = corners
    if k == 1:
        return [(a, m[0], c), (m[0], b, c)]
    mab, mbc = m[0], m[1]
    quad = [(a, mab, mbc), (a, mbc, c)] if (a.co - mbc.co).length <= (mab.co - c.co).length else [(a, mab, c), (mab, mbc, c)]
    return [(mab, b, mbc)] + quad


def _refine_seam(bm, layer, surface):
    """Split the long edges of the faces marked in `layer` (the face's boundary edges too:
    they lie on the skull), each new vertex on the construction surface, neighbours closed
    red-green; returns the longest seam edge left (m)."""
    for _pass in range(SEAM_PASSES):
        edges = list(dict.fromkeys(e for f in bm.faces if f[layer] for e in f.edges if e.calc_length() > SEAM_EDGE_M))
        if not edges:
            break
        mid = {e: bm.verts.new(surface.onto((e.verts[0].co + e.verts[1].co) / 2.0)) for e in edges}
        affected = list(dict.fromkeys(f for e in edges for f in e.link_faces))
        rebuilt = []
        for f in affected:
            loops = list(f.loops)
            corners = [l.vert for l in loops]
            splits = [mid.get(l.edge) for l in loops]
            rebuilt += [(t, f[layer]) for t in _split_triangle(*corners, *splits)]
        bmesh.ops.delete(bm, geom=affected, context="FACES_ONLY")
        for tri, flag in rebuilt:
            bm.faces.new(tri)[layer] = flag
        bmesh.ops.delete(bm, geom=[e for e in edges if e.is_valid and not e.link_faces], context="EDGES")
    return max((e.calc_length() for f in bm.faces if f[layer] for e in f.edges), default=0.0)


def _distance_to_loop(p, loop):
    best = None
    for i, a in enumerate(loop):
        ab = loop[(i + 1) % len(loop)] - a
        t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
        d = (a + ab * t - p).length
        best = d if best is None else min(best, d)
    return best


def _distance_to_run(p, run):
    """Distance from `p` to the open polyline `run`."""
    best = None
    for a, b in zip(run, run[1:]):
        ab = b - a
        t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared)) if ab.length_squared else 0.0
        d = (a + ab * t - p).length
        best = d if best is None else min(best, d)
    return best


def _blend(bm, boundary, face_verts, surface, lower=None):
    """Relax the band around the closed polyline `boundary` (smoothstep weight on the
    distance to it), the skull's side kept on the construction surface (relaxing alone
    shrinks the band into a groove): the face's outer ring eases into the skull. `lower`
    ((run, width)): along that open run of the boundary the band is `width` wide."""
    weight = {}
    for v in bm.verts:
        d = _distance_to_loop(v.co, boundary)
        w = 0.0
        if d < BLEND_M:
            x = 1.0 - d / BLEND_M
            w = x * x * (3.0 - 2.0 * x)
        if lower is not None:
            run, width = lower
            d = _distance_to_run(v.co, run)
            if d < width:
                x = 1.0 - d / width
                w = max(w, x * x * (3.0 - 2.0 * x))
        if w > 0.0:
            weight[v] = w
    for k in range(BLEND_PASSES):
        verts = [v for v, w in weight.items() if w > k / BLEND_PASSES]
        bmesh.ops.smooth_vert(bm, verts=verts, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
        for v in verts:
            if v not in face_verts:
                v.co = surface.onto(v.co)
    return len(weight)


def _underside(bm, face_index, count, surface):
    """The skull's own lower half (UNDERSIDE_V: under the jaw, the jaw's run back to the
    ear, where the neck enters) is the construction head's 2-4 cm triangles,
    so the jawline and the head-neck junction were polygons across them. Its long edges are
    split flat (resolution, no shape), then Taubin-smoothed (a smoothing step and an
    inflating step per pass: facet corners go, volume stays), fading to nothing at the
    region's rim and never put back on the coarse construction surface. The seam's zip
    along the jaw's lower edge is in the region (split flat, smoothed); the face's own faces
    are not."""
    floor = surface.low + UNDERSIDE_V * surface.height
    rear = surface.front + UNDERSIDE_DEPTH * (surface.back - surface.front)
    bm.verts.index_update()

    def low_front(f):
        centre = f.calc_center_median()
        return centre.z < floor and centre.y < rear

    def skull_or_seam(f, split_from):
        ## The skull's own faces and the seam's (a face vertex and a skull vertex: the zip
        ## along the jaw's lower edge, the last coarse strip); never the face's own.
        face = [v.index in face_index or count <= v.index < split_from for v in f.verts]
        return not all(face)
    faces = {f for f in bm.faces if low_front(f) and skull_or_seam(f, len(bm.verts))}
    edges = [e for e in dict.fromkeys(e for f in faces for e in f.edges)
             if all(g in faces for g in e.link_faces) and e.calc_length() > UNDERSIDE_EDGE_M]
    before = len(bm.verts)
    bmesh.ops.subdivide_edges(bm, edges=edges, cuts=LOWER_CUTS, smooth=0.0, use_grid_fill=False)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3])
    bm.verts.index_update()
    ## The region again (its new vertices are skull vertices, index >= before).
    faces = {f for f in bm.faces if low_front(f) and skull_or_seam(f, before)}
    verts = {v for f in faces for v in f.verts}
    ## The rim is where the region meets the rest of the skull; the face's own faces beside
    ## the seam are no rim (the seam itself is what is smoothed).
    rim = {v for v in verts if any(g not in faces and skull_or_seam(g, before) for g in v.link_faces)}
    ## Weight: distance from the rim, smoothstep over UNDERSIDE_FADE_M (a fade counted in
    ## rings is ~1 cm on the split mesh: a ridge where the smoothing stops).
    from mathutils.kdtree import KDTree
    tree = KDTree(len(rim))
    for i, v in enumerate(rim):
        tree.insert(v.co, i)
    tree.balance()
    weight = {}
    for v in verts - rim:
        x = min(1.0, tree.find(v.co)[2] / UNDERSIDE_FADE_M)
        weight[v] = x * x * (3.0 - 2.0 * x)
    bm.normal_update()
    start = {v: (v.co.copy(), v.normal.copy()) for v in weight}
    for _pass in range(UNDERSIDE_PASSES):
        for factor in (UNDERSIDE_LAMBDA, UNDERSIDE_MU):
            moved = {}
            for v, w in weight.items():
                around = [e.other_vert(v).co for e in v.link_edges]
                mean = sum(around, Vector()) / len(around)
                moved[v] = v.co + (mean - v.co) * (factor * w)
            for v, co in moved.items():
                v.co = co
    ## Never more than UNDERSIDE_IN_M inward of where it was (a facet corner cut deeper let
    ## the tall lean neck show through the head's side).
    for v, (co, normal) in start.items():
        inward = (v.co - co).dot(normal)
        if inward < -UNDERSIDE_IN_M:
            v.co = v.co + normal * (-UNDERSIDE_IN_M - inward)
    return len(weight)


def build_face(source=CONSTRUCTION_HEAD, name=STUDY, parameters=None):
    """The face as its own topology (FACE-IDENTITY-001): `face_mask`'s control vertices on
    `source`'s construction surface become mesh vertices and its panels faces (refined
    `face_mask.REFINE` times, each panel the plane of its corners bent by `follow` onto the
    skull, with a convex swell); the skull's front sheet inside the designed boundary is
    removed and the face is zipped to what remains, the seam refined onto the skull: one
    closed surface."""
    face_mask = _mask_module()
    head = bpy.data.objects[source]
    stored = head.data.attributes[F0_ATTRIBUTE]
    faces = [tuple(p.vertices) for p in head.data.polygons]
    skull = [head.matrix_world @ Vector(a.vector) for a in stored.data]
    surface = _Construction([tuple(p) for p in skull], faces)
    controls = face_mask.control_points(parameters)
    placed = {}
    for cname, (u, v, lift, _follow) in controls.items():
        location, normal = surface.at(u, v, cname)
        placed[cname] = location + normal * lift
    points, triangles = face_mask.refined()
    lower = (parameters or {}).get(face_mask.LOWER_CONTOUR, 0.0)
    positions = {}
    for key, (weights, swell, _region) in points.items():
        u = sum(w * controls[n][0] for n, w in weights.items())
        v = sum(w * controls[n][1] for n, w in weights.items())
        lift = sum(w * controls[n][2] for n, w in weights.items())
        follow = sum(w * controls[n][3] for n, w in weights.items())
        planar = sum((placed[n] * w for n, w in weights.items()), Vector())
        if follow > 0.0:
            location, normal = surface.at(u, v, str(key))
            planar = planar.lerp(location + normal * lift, follow)
        if lower and v < controls["mouth"][1]:
            ## Below the mouth the rounding and the smooth split carry the curvature; a
            ## swell per panel stacked panel-sized bulges on it (a lumpy lower jaw).
            swell = 0.0
        if swell > 0.0:
            a, b, c = (placed[n] for n in weights)
            normal = (b - a).cross(c - a).normalized()
            if normal.dot(planar - surface.centre) < 0.0:
                normal = -normal
            size = max((b - a).length, (c - b).length, (a - c).length)
            planar = planar + normal * face_mask.SWELL * size * swell
        positions[key] = planar
    ## The bridge and the brow ridge rounded (face_mask.SOFT_EDGES), the boundary held.
    soft = face_mask.soft_keys(points)
    order = _boundary_keys(triangles)
    rounded = face_mask.soften({k: tuple(p) for k, p in positions.items()}, triangles, soft, frozenset(order), parameters)
    if lower:
        lower_soft = face_mask.soft_keys(points, face_mask.LOWER_SOFT_EDGES)
        ## The under-jaw boundary corners round with it (jaw_low pointed down 3-5 mm below
        ## the border either side of it); the skull is cut and zipped to the boundary as
        ## rounded, so the seam follows.
        free = {((n, face_mask.REFINE),) for n in face_mask.LOWER_FREE_BOUNDARY}
        free |= {((face_mask.mirrored(n), face_mask.REFINE),) for n in face_mask.LOWER_FREE_BOUNDARY}
        rounded = face_mask.soften(rounded, triangles, lower_soft, frozenset(order) - free,
                                   amount=face_mask.SOFTEN * lower, passes=face_mask.LOWER_SOFTEN_PASSES)
        ## Rounded edges shade smooth, as the bridge's do.
        soft = soft | lower_soft
    positions = {k: Vector(p) for k, p in rounded.items()}
    ## The skull: the construction surface minus its front sheet inside the boundary.
    bm = bmesh.new()
    skull = [bm.verts.new(Vector(p)) for p in surface.co]
    for f in faces:
        bm.faces.new([skull[i] for i in f])
    outline = [controls[n][:2] for n in face_mask.boundary_loop()]
    start = order.index((("hairline", face_mask.REFINE),))
    order = order[start:] + order[:start]
    boundary = [positions[k] for k in order]

    def covered(p):
        location, _index = surface.hit(p.x, p.z)
        return location is not None and p.y <= location.y + FRONT_SHEET_M and _inside(surface.chart(p), outline)

    removed = [f for f in bm.faces if any(covered(v.co) or _distance_to_loop(v.co, boundary) < SEAM_GAP_M for v in f.verts)
               or covered(f.calc_center_median())]
    bmesh.ops.delete(bm, geom=removed, context="FACES_ONLY")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    skull_loop = _border_loop(bm, set(bm.verts))
    ## The face, zipped to the hole; the seam refined onto the skull.
    verts = {key: bm.verts.new(p) for key, p in positions.items()}
    for _region, keys in triangles:
        bm.faces.new([verts[k] for k in keys])
    face_verts = set(verts.values())
    layer = bm.faces.layers.int.new("riposte_seam")
    for f in _zip(bm, [verts[k] for k in order], skull_loop):
        f[layer] = 1
    seam_mm = _refine_seam(bm, layer, surface) * 1000.0
    bm.faces.layers.int.remove(layer)
    near = [f for f in bm.faces if not all(v in face_verts for v in f.verts)
            and _distance_to_loop(f.calc_center_median(), boundary) < BEAUTIFY_M]
    inside = set(near)
    bmesh.ops.beautify_fill(bm, faces=near, edges=list(dict.fromkeys(e for f in near for e in f.edges if not e.is_boundary
                                                                    and all(g in inside for g in e.link_faces))))
    wide = None
    if lower:
        ## The under-jaw run of the boundary (chin_low and back to each jaw corner).
        floor = placed["jaw_angle"].z + LOWER_BLEND_ABOVE_M
        under = [i for i, p in enumerate(boundary) if p.z <= floor]
        if under:
            wide = ([boundary[i] for i in range(under[0], under[-1] + 1)], BLEND_M + LOWER_BLEND_M * min(1.0, lower))
    blended = _blend(bm, boundary, face_verts, surface, wide)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    open_edges = sum(1 for e in bm.edges if not e.is_manifold)
    bm.verts.index_update()
    rounded_verts = {verts[k].index for k in soft}
    rounded_verts |= {n.index for k in soft for e in verts[k].link_edges for n in e.verts}
    names = sorted(controls)
    control_index = {i + 1: verts[((n, face_mask.REFINE),)].index for i, n in enumerate(names) if ((n, face_mask.REFINE),) in verts}
    face_index = {v.index for v in face_verts}
    data = bpy.data.meshes.new(name)
    bm.to_mesh(data)
    bm.free()
    split = 0
    if lower:
        ## The lower face's panel edges (below the mouth, the seam under the jaw included)
        ## split smoothly: the new vertices on a curve through the existing ones, none of
        ## which moves, every existing index kept (HEAD-CONTOUR-001: an 11 mm edge cannot
        ## carry the chin's turn).
        count = len(data.vertices)
        sub = bmesh.new()
        sub.from_mesh(data)
        sub.verts.ensure_lookup_table()
        ceiling = placed["mouth"].z
        ## Inside the mask only: on the seam the face's and the skull's normals disagree and
        ## a smooth split ripples the jaw's lower edge (seen from the front).
        region = {f for f in sub.faces if f.calc_center_median().z < ceiling and all(v.index in face_index for v in f.verts)}
        edges = list(dict.fromkeys(e for f in region for e in f.edges if all(g in region for g in e.link_faces)))
        bmesh.ops.subdivide_edges(sub, edges=edges, cuts=LOWER_CUTS, smooth=LOWER_SMOOTH, use_grid_fill=False)
        bmesh.ops.triangulate(sub, faces=[f for f in sub.faces if len(f.verts) > 3])
        _underside(sub, face_index, count, surface)
        bmesh.ops.recalc_face_normals(sub, faces=sub.faces[:])
        open_edges = sum(1 for e in sub.edges if not e.is_manifold)
        ## The split region shades smooth: its form is rounded, never creased.
        sub.verts.index_update()
        rounded_verts |= {v.index for f in sub.faces if f.calc_center_median().z < ceiling
                          and any(v.index in face_index or v.index >= count for v in f.verts) for v in f.verts}
        sub.to_mesh(data)
        sub.free()
        split = len(data.vertices) - count
    for polygon in data.polygons:
        polygon.use_smooth = True
    data.set_sharp_from_angle(angle=math.radians(FACE_EDGE_DEG))
    ## The softened edges shade smooth (never a hard line), as the nose tip does.
    sharp = data.attributes["sharp_edge"]
    for edge in data.edges:
        if rounded_verts.issuperset(edge.vertices):
            sharp.data[edge.index].value = False
    obj = bpy.data.objects.new(name, data)
    (head.users_collection[0] if head.users_collection else bpy.context.scene.collection).objects.link(obj)
    ## Its construction surface (hair and attachments frame on it, never on the face).
    construction = data.attributes.new(F0_ATTRIBUTE, "FLOAT_VECTOR", "POINT")
    for v, a in zip(data.vertices, construction.data):
        a.vector = surface.tree.find_nearest(v.co)[0]
    ## Its control vertices tagged (CONTROL_ATTRIBUTE): a rounded control moves off its chart
    ## position, so the chart lookup would miss it.
    tag = data.attributes.new(CONTROL_ATTRIBUTE, "INT", "POINT")
    for value, index in control_index.items():
        tag.data[index].value = value
    forward = min(placed, key=lambda n: placed[n].y)
    depth = {n: round(-placed[n].y * 1000.0, 1) for n in ("nose_peak", "bridge_root", "brow_inner", "brow_mid", "shelf_mid",
                                                           "eye_low", "cheekbone", "chin")}
    return obj, {"vertices": len(data.vertices), "faces": len(data.polygons), "panels": len(face_mask.panels()),
                 "face_vertices": len(face_verts), "skull_faces_removed": len(removed),
                 "seam_longest_edge_mm": round(seam_mm, 1), "blended_vertices": blended, "non_manifold_edges": open_edges,
                 "lower_split_vertices": split,
                 "forward_control": forward, "control_depth_mm": depth,
                 "frame": [round(surface.low, 4), round(surface.height, 4), round(surface.half_width, 4)]}


def fingerprint(obj):
    import numpy as np
    co = np.empty(len(obj.data.vertices) * 3)
    obj.data.vertices.foreach_get("co", co)
    digest = hashlib.sha256(np.round(co, FINGERPRINT_DECIMALS).astype("<f8").tobytes())
    for p in obj.data.polygons:
        digest.update(json.dumps(list(p.vertices)).encode())
    return {"vertices": len(obj.data.vertices), "faces": len(obj.data.polygons), "sha256": digest.hexdigest()}


def record():
    return {"schema": "riposte.male_base_v2_record", "version": 1, "approved": "2026-10-31 (review r1)",
            "source": "male_base.blend (v1)", "builder": "tools/blender/authoring/male_base_v2.py",
            "head_approved": HEAD_APPROVAL,
            "objects": {name: fingerprint(bpy.data.objects[name]) for name in (SCULPT, STUDY)}}


def _open_master():
    bpy.ops.wm.open_mainfile(filepath=MASTER_V1)


def foundation_document():
    """(the foundation module, the checked foundation document)."""
    sys.path.insert(0, os.path.join(ROOT, "tools", "character_modeling"))
    from character_modeling import asset_library, foundation
    document = foundation.load(REVIEW_FOUNDATION or asset_library.current_foundation_document())
    problems = foundation.problems(document)
    if problems:
        raise SystemExit("RIPOSTE_FOUNDATION: " + "; ".join(problems))
    return foundation, document


def foundation_source():
    foundation, document = foundation_document()
    return foundation.path_of(document, "source", os.path.dirname(CHARACTERS))


def _foundation(verify):
    """Build the foundation's base from the v1 master with its studies; save the source and
    its record, or (`verify`) compare the rebuild with the record and the saved source."""
    foundation, document = foundation_document()
    blender = os.path.dirname(CHARACTERS)
    source = foundation.path_of(document, "source", blender)
    record_path = foundation.path_of(document, "record", blender)
    if os.path.abspath(foundation.path_of(document["base"], "master", blender)) != os.path.abspath(MASTER_V1):
        raise SystemExit("RIPOSTE_FOUNDATION: the foundation's master is not %s" % MASTER_V1)
    _open_master()
    report = build(document["base"]["mask_study"], document["base"]["body_study"])
    built = {"schema": "riposte.character_foundation_record", "version": 1, "foundation": document["id"],
             "approved": document.get("approved"), "builder": "tools/blender/authoring/male_base_v2.py --foundation",
             "objects": {name: fingerprint(bpy.data.objects[name]) for name in (SCULPT, STUDY)}}
    if not verify:
        from character_modeling import asset_library
        for path in (source, record_path):
            asset_library.refuse_overwrite(path)
        bpy.ops.wm.save_as_mainfile(filepath=source)
        with open(record_path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(json.dumps(built, indent=2) + "\n")
        print("RIPOSTE_FOUNDATION_BUILD", json.dumps({"stages": report, "record": built}))
        return
    with open(record_path, encoding="utf-8") as handle:
        recorded = json.load(handle)["objects"]
    bpy.ops.wm.open_mainfile(filepath=source)
    saved = {name: fingerprint(bpy.data.objects[name]) for name in (SCULPT, STUDY)}
    problems = ["%s: rebuild %s != record %s" % (n, built["objects"][n], recorded[n])
                for n in recorded if built["objects"][n] != recorded[n]]
    problems += ["%s: saved %s != record %s" % (n, saved[n], recorded[n]) for n in recorded if saved[n] != recorded[n]]
    print("RIPOSTE_FOUNDATION_VERIFY", json.dumps({"ok": not problems, "problems": problems}))
    if problems:
        raise SystemExit(1)


def _iteration_out(path):
    """An output path inside one iteration folder (ART-ITERATION-001), or refused."""
    sys.path.insert(0, os.path.join(ROOT, "tools", "character_modeling"))
    from character_modeling import iterations
    problems = iterations.path_problems(path, ROOT)
    if problems:
        raise SystemExit("RIPOSTE_ITERATION: " + "; ".join(problems))
    return os.path.abspath(path)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--bind" in args:
        ## A working blend for the deformation review: never the source (the bound body
        ## becomes the master only at promotion, after its deformation is approved).
        out = _iteration_out(args[args.index("--bind") + 1])
        bpy.ops.wm.open_mainfile(filepath=CANDIDATE)
        report = bind()
        os.makedirs(os.path.dirname(out), exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=out, copy=True)
        print("RIPOSTE_V2_BIND", json.dumps(dict(report, blend=out)))
        return
    if "--foundation" in args or "--verify-foundation" in args:
        if REVIEW_BASE:
            raise SystemExit("RIPOSTE_V2: the foundation builds from the master; unset RIPOSTE_BASE_REVIEW")
        _foundation("--verify-foundation" in args)
        return
    study = None
    if "--mask-study" in args:
        ## key=value pairs, comma-separated (survives every shell's quoting).
        study = {k: float(v) for k, v in (pair.split("=") for pair in args[args.index("--mask-study") + 1].split(","))}
    if study and "--candidate" not in args:
        raise SystemExit("RIPOSTE_V2: --mask-study builds candidates only (the approved mask is CONTROL)")
    _open_master()
    report = build(study)
    built = record()
    if "--candidate" in args:
        out = _iteration_out(args[args.index("--candidate") + 1])
        os.makedirs(os.path.dirname(out), exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=out, copy=True)
        print("RIPOSTE_V2_CANDIDATE", json.dumps({"stages": report, "record": built, "mask_study": study, "blend": out}))
        return
    if "--build" in args:
        if REVIEW_BASE:
            raise SystemExit("RIPOSTE_V2: --build writes the approved source; unset RIPOSTE_BASE_REVIEW")
        bpy.ops.wm.save_as_mainfile(filepath=CANDIDATE)
        with open(RECORD, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(json.dumps(built, indent=2) + "\n")
        print("RIPOSTE_V2_BUILD", json.dumps({"stages": report, "record": built}))
        return
    if "--verify" in args:
        with open(RECORD, encoding="utf-8") as handle:
            recorded = json.load(handle)["objects"]
        bpy.ops.wm.open_mainfile(filepath=CANDIDATE)
        saved = {name: fingerprint(bpy.data.objects[name]) for name in (SCULPT, STUDY)}
        problems = ["%s: rebuild %s != record %s" % (n, built["objects"][n], recorded[n])
                    for n in recorded if built["objects"][n] != recorded[n]]
        problems += ["%s: saved %s != record %s" % (n, saved[n], recorded[n]) for n in recorded if saved[n] != recorded[n]]
        print("RIPOSTE_V2_VERIFY", json.dumps({"ok": not problems, "problems": problems}))
        if problems:
            raise SystemExit(1)
        return
    raise SystemExit("pass --build, --verify or --candidate <iteration>/<name>.blend")


if __name__ == "__main__":
    main()
