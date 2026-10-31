"""The approved male base v2 (2026-10-31): one deterministic build from the frozen v1 master.

Approved by the person on 2026-10-31 (review `r1`). The base is two authored objects on
v1's rig, built in stages from `male_base.blend` (v1, never edited) and saved as
`male_base.v2.blend`, the Blender-owned source of the approved form:

- `BodyV2` (body, no head): v1's body in the stored A-pose without the head island,
  closed and voxel-remeshed (b0), the large anatomical forms (b1), then the heroic
  proportions as broad fields (w1, `HERO`: shoulder girdle, ribcage, arms, thighs, calves,
  neck, trapezius, upper back, lats, glutes). b1's surface is stored on the object
  (`riposte_b1_co`) for comparison.
- `HeadV2`: v1's head island with its face subdivided (f0, no shape change; stored as
  `riposte_f0_co`), then the face construction on the original mask (f1: `FACE_FORMS` and
  `NOSE` strengthened by `FACE_ADJUST`: brow ridge over hooded eyes, cheekbones, an angular
  nose tip, the chin), plane turns over `FACE_ADJUST["edge_deg"]` shaded as edges.

`Body` (v1: skinned, 16 physique keys) stays in the file as the rig's reference: weights
and configuration keys transfer from it. Nothing here moves a bone, the rest or the bind.

The record `male_base.v2.record.json` holds each object's fingerprint (vertex and face
counts and a digest of its rounded coordinates and faces); `--verify` rebuilds in memory
and compares with the record and with the saved file, so the source and its build cannot
drift apart silently.

    blender --background --factory-startup --python tools/blender/authoring/male_base_v2.py -- --build
    blender --background --factory-startup --python tools/blender/authoring/male_base_v2.py -- --verify
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
RECORD = os.path.join(CHARACTERS, "male_base.v2.record.json")
SCULPT = "BodyV2"
STUDY = "HeadV2"
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


def _study():
    return bpy.data.objects[STUDY]


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


def _restore_f0(obj):
    attribute = obj.data.attributes[F0_ATTRIBUTE]
    for v, a in zip(obj.data.vertices, attribute.data):
        v.co = a.vector


def f0():
    """HeadStudy: the head island copied, its face triangles subdivided (no shape change)."""
    if STUDY in bpy.data.objects:
        raise SystemExit("RIPOSTE_HEAD_STUDY: %s exists; f0 runs once" % STUDY)
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
    data = bpy.data.meshes.new(STUDY)
    bm.to_mesh(data)
    bm.free()
    for p in data.polygons:
        p.use_smooth = True
    collection = bpy.data.collections.get(COLLECTION) or bpy.data.collections.new(COLLECTION)
    if collection.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(collection)
    obj = bpy.data.objects.new(STUDY, data)
    collection.objects.link(obj)
    _store_f0(obj)
    kept = sum(1 for v in data.vertices if tuple(round(c, 6) for c in v.co) in before)
    return {"vertices": len(data.vertices), "faces": len(data.polygons), "original_vertices_kept": kept,
            "frame": {k: round(v, 4) for k, v in frame.items()}}


## The face construction, metres in the head's frame (x from the centre line, z world
## height; the head island runs 1.522..1.7985 m, half-width 0.108, the face line at
## y -0.135). `move` is the displacement at the form's centre (x outward, y back),
## `radii` its Gaussian extent across and up. Mirrored: one side authored.
FACE_FORMS = {
    ## Brow: a raised supraorbital ridge, strongest at the inner end, angled down toward
    ## the nose, tapering to the temple (three overlapping masses along it).
    "brow_ridge_inner": {"at": (0.021, 1.696), "radii": (0.015, 0.009), "move": (0.0, -0.0075)},
    "brow_ridge_mid": {"at": (0.046, 1.701), "radii": (0.017, 0.009), "move": (0.0, -0.0058)},
    "brow_ridge_outer": {"at": (0.072, 1.705), "radii": (0.015, 0.008), "move": (0.001, -0.003)},
    "glabella": {"at": (0.0, 1.699), "radii": (0.007, 0.009), "move": (0.0, 0.002)},
    ## Eyes: a recessed orbit under the brow and an upper lid fold just above the eye,
    ## well below the ridge (the eye stays readable; the brow never buries it).
    "orbit": {"at": (0.0363, 1.671), "radii": (0.02, 0.013), "move": (0.0, 0.0042)},
    "upper_lid_fold": {"at": (0.037, 1.6795), "radii": (0.017, 0.0035), "move": (0.0, -0.0018)},
    ## Cheekbones: the widest forward-facing landmarks, lateral and slightly forward,
    ## sloping in toward the nose; a soft hollow below them into the jaw.
    "cheekbone": {"at": (0.063, 1.641), "radii": (0.019, 0.016), "move": (0.004, -0.0065)},
    "cheekbone_inner_plane": {"at": (0.036, 1.638), "radii": (0.014, 0.014), "move": (0.0, -0.0025)},
    "cheek_hollow": {"at": (0.058, 1.597), "radii": (0.017, 0.013), "move": (0.0, 0.0028)},
    ## Chin: defined, slightly rounded forward projection.
    "chin": {"at": (0.0, 1.548), "radii": (0.022, 0.017), "move": (0.0, -0.0045)},
}


## The nose: a raised angular bridge from the glabella to the tip, continuous with the
## forehead (forward projection by height, a tent across x so its two lateral planes
## meet at the centre line), a small rounded tip, a restrained transition below.
NOSE = {"root": (1.696, 0.003, 0.011), "tip": (1.627, 0.016, 0.017), "base": (1.604, 0.0, 0.013),
        "tip_ball": {"at": (0.0, 1.628), "radii": (0.010, 0.008), "move": (0.0, -0.003)}}


## Forms act on the face only: full in front of FRONT_M (y), fading to nothing by FADE_M behind it.
FRONT_M = -0.095


FADE_M = 0.03


def _gauss(x, z, form):
    (cx, cz), (rx, rz) = form["at"], form["radii"]
    return math.exp(-0.5 * (((x - cx) / rx) ** 2 + ((z - cz) / rz) ** 2))


def _nose(x, z, nose):
    """Forward projection of the bridge at height z and offset x (metres, positive)."""
    (z_root, p_root, w_root), (z_tip, p_tip, w_tip), (z_base, p_base, w_base) = nose["root"], nose["tip"], nose["base"]
    if z > z_root or z < z_base:
        return 0.0
    if z >= z_tip:
        t = (z_root - z) / (z_root - z_tip)
        p, w = p_root + (p_tip - p_root) * t ** 1.3, w_root + (w_tip - w_root) * t
    else:
        t = (z_tip - z) / (z_tip - z_base)
        p, w = p_tip + (p_base - p_tip) * t ** 0.7, w_tip + (w_base - w_tip) * t
    return p * max(0.0, 1.0 - x / w)


def f1(forms, nose):
    """The face construction (`forms` as FACE_FORMS, `nose` as NOSE) on the f0 surface."""
    obj = _study()
    if F0_ATTRIBUTE not in obj.data.attributes:
        raise SystemExit("RIPOSTE_V2: %s has no f0 surface stored" % STUDY)
    _restore_f0(obj)
    report = {}
    for v in obj.data.vertices:
        p = v.co
        mask = 1.0 if p.y <= FRONT_M else max(0.0, 1.0 - (p.y - FRONT_M) / FADE_M)
        if mask <= 0.0:
            continue
        x, side = abs(p.x), (1.0 if p.x >= 0.0 else -1.0)
        dx = dy = 0.0
        for form in list(forms.values()) + [nose["tip_ball"]]:
            g = _gauss(x, p.z, form)
            dx += form["move"][0] * g
            dy += form["move"][1] * g
        dy -= _nose(x, p.z, nose)
        if dx or dy:
            p.x += side * dx * mask
            p.y += dy * mask
            moved = math.hypot(dx, dy) * mask
            report["max_move_m"] = max(report.get("max_move_m", 0.0), moved)
    obj.data.update()
    report["max_move_m"] = round(report.get("max_move_m", 0.0), 4)
    report["front_m"] = round(min(v.co.y for v in obj.data.vertices), 4)
    return report


## F1: changes to f1b's own named forms (FACE_FORMS / NOSE), nothing added. `scale` on a
## form multiplies its move; the nose loses its rounded tip ball (the tent's tip stays an
## angular point) and projects a little further.
FACE_ADJUST = {
    "forms": {"brow_ridge_inner": 1.25, "brow_ridge_mid": 1.25, "brow_ridge_outer": 1.15,
              "upper_lid_fold": 1.3, "cheekbone": 1.35, "cheekbone_inner_plane": 1.2, "chin": 1.15},
    "nose_tip_ball": 0.0,
    "nose_projection": 1.12,
    ## Plane changes steeper than this shade as edges; gentler ones stay smooth, so the
    ## mask's panels read flat and its folds read angular.
    "edge_deg": 34.0,
}


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


B1_ATTRIBUTE = "riposte_b1_co"


def _store(obj):
    import numpy as np
    co = np.empty(len(obj.data.vertices) * 3)
    obj.data.vertices.foreach_get("co", co)
    attribute = obj.data.attributes.get(B1_ATTRIBUTE) or obj.data.attributes.new(B1_ATTRIBUTE, "FLOAT_VECTOR", "POINT")
    attribute.data.foreach_set("vector", co)
    return co.reshape(-1, 3)


def _approved_face():
    """FACE_FORMS and NOSE with FACE_ADJUST applied (the approved F1 face)."""
    forms = {k: dict(v) for k, v in FACE_FORMS.items()}
    nose = {k: (dict(v) if isinstance(v, dict) else v) for k, v in NOSE.items()}
    for name, scale in FACE_ADJUST["forms"].items():
        forms[name]["move"] = tuple(c * scale for c in forms[name]["move"])
    nose["tip_ball"]["move"] = tuple(c * FACE_ADJUST["nose_tip_ball"] for c in nose["tip_ball"]["move"])
    for key in ("root", "tip", "base"):
        z, projection, width = nose[key]
        nose[key] = (z, projection * FACE_ADJUST["nose_projection"], width)
    return forms, nose


def w1():
    """The heroic proportions on b1 (HERO): radial scales along segments and broad shifts."""
    import numpy as np
    apose()
    obj = _sculpt()
    co = _store(obj)
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

    for _name, (bones, band, scale) in HERO["radial"].items():
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
    for _name, (centre, radius, direction, amount) in HERO["shift"].items():
        d = np.array(direction) / np.linalg.norm(direction)
        r = np.linalg.norm(p - np.array(centre), axis=1)
        out += (amount * np.exp(-0.5 * (r / radius) ** 2))[:, None] * d
    out[:, 0] *= sign
    obj.data.vertices.foreach_set("co", out.ravel())
    obj.data.update()
    return {"max_move_mm": round(float(np.linalg.norm(out - co, axis=1).max()) * 1000, 1)}


def build():
    """Every stage, from the open v1 master, in order. Returns the stage reports."""
    report = {"b0": b0(), "b1": b1(), "w1": w1(), "f0": f0()}
    forms, nose = _approved_face()
    report["f1"] = f1(forms, nose)
    _study().data.set_sharp_from_angle(angle=math.radians(FACE_ADJUST["edge_deg"]))
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


def _joined():
    """BodyV2 and HeadV2 as one surface (A-pose world): points, faces, and the
    construction surface (the head's f0 skull, the body's own points)."""
    import numpy as np
    body, head = _sculpt(), _study()
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


def bind():
    """The bound body `Body` (v1's `Body` kept as `BodyV1`): returns the round-trip report."""
    import numpy as np
    apose()
    points, faces, construction, smooth, sharp = _joined()
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
    for name in (SCULPT, STUDY, V1_REFERENCE):
        bpy.data.objects[name].hide_render = True
        bpy.data.objects[name].hide_set(True)
    influences = (table > 0.0).sum(axis=1)
    return {"vertices": len(points), "bones": names, "round_trip_max_mm": round(error * 1000, 4),
            "influences": {str(k): int((influences == k).sum()) for k in range(1, MAX_INFLUENCES + 1)},
            "keys": sorted(deltas)}


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
            "objects": {name: fingerprint(bpy.data.objects[name]) for name in (SCULPT, STUDY)}}


def _open_master():
    bpy.ops.wm.open_mainfile(filepath=MASTER_V1)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--bind" in args:
        ## A working blend for the deformation review: never the source (the bound body
        ## becomes the master only at promotion, after its deformation is approved).
        out = os.path.abspath(args[args.index("--bind") + 1])
        bpy.ops.wm.open_mainfile(filepath=CANDIDATE)
        report = bind()
        os.makedirs(os.path.dirname(out), exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=out, copy=True)
        print("RIPOSTE_V2_BIND", json.dumps(dict(report, blend=out)))
        return
    _open_master()
    report = build()
    built = record()
    if "--build" in args:
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
    raise SystemExit("pass --build or --verify")


if __name__ == "__main__":
    main()
