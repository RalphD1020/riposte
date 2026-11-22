"""Hand-to-handle contact (PRES-GRIP-001): does a gripping hand really hold its handle?

Reads one hand of a skinned body at its current pose, a grip contact (the handle's axis and centre
in Hand-bone space, its radius) and the hand's patch tags (point attribute `riposte_hand_patch`:
1 palm, 2 fingers, 3 thumb). Samples the evaluated surface — vertices, edge midpoints and face
centres, so a face crossing the handle between two clear vertices is still seen — and reports per
patch, through `character_modeling.grip_contact`: deepest penetration, nearest clearance, contact
count and the patch's angle round the handle (0 = the palm direction), plus the problems that keep
the grip from holding. Optionally renders, with a temporary reference handle that is removed
afterwards (nothing is saved): the handle opaque, semi-transparent and hidden from a three-quarter
and an end-on view, and the hand's cross-section at the handle's mid-plane against the handle's
circle (the finger mass's C round the handle, or its absence).

Inside the Blender MCP session:
    exec(open(<this>).read(), {"REPO_ROOT": <repo>, "SIDE": "R", "CONTACT": {...}, "OUT_DIR": <dir or "">, "TAG": "v6"})
Headless:
    blender -b --factory-startup --python hand_grip_contact.py -- <blend> <R|L> <contact.json> [<out dir> <tag>]
(`contact.json` holds {"handle_axis_hand_local", "handle_centre_hand_local_m", "handle_radius_m"} and,
for the real oval grip, "handle_section_m": [a, b] with "handle_section_a_axis_hand_local".)
Prints `GRIP_CONTACT <json>`; sets `result` when run with exec."""
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

## exec() inside the MCP session has no __file__; the caller then passes REPO_ROOT.
_ROOT = globals().get("REPO_ROOT") or os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
sys.path.insert(0, os.path.join(_ROOT, "tools", "character_modeling"))
from character_modeling import grip_contact
import importlib
## A live MCP session keeps modules between runs; always measure with the current code.
grip_contact = importlib.reload(grip_contact)

PATCH_NAMES = {1: "palm", 2: "fingers", 3: "thumb"}
PALM_DIRECTION = {"R": (0.5787, 0.0, 0.8156), "L": (-0.5787, 0.0, 0.8156)}  ## hand_frame.json, Hand-bone space
HALF_LENGTH_M = 0.05
BODY, RIG = "ProductionBody", "WolfRigNeutral"

if "SIDE" not in globals():
    _args = sys.argv[sys.argv.index("--") + 1:]
    bpy.ops.wm.open_mainfile(filepath=_args[0])
    SIDE = _args[1]
    CONTACT = json.load(open(_args[2], encoding="utf-8"))
    OUT_DIR = _args[3] if len(_args) > 3 else ""
    TAG = _args[4] if len(_args) > 4 else "grip"

body = bpy.data.objects[BODY]
rig = bpy.data.objects[RIG]
pose_bone = rig.pose.bones["Hand." + SIDE]
hand_world = rig.matrix_world @ pose_bone.matrix
axis = (hand_world.to_3x3() @ Vector(CONTACT["handle_axis_hand_local"])).normalized()
centre = hand_world @ Vector(CONTACT["handle_centre_hand_local_m"])
palm = (hand_world.to_3x3() @ Vector(PALM_DIRECTION[SIDE])).normalized()
ref = (palm - axis * palm.dot(axis)).normalized()
radius = CONTACT["handle_radius_m"]

deps = bpy.context.evaluated_depsgraph_get()
evaluated = body.evaluated_get(deps)
mesh = evaluated.to_mesh()
world = body.matrix_world
tag_attr = body.data.attributes.get("riposte_hand_patch")
tags = [0] * len(body.data.vertices)
if tag_attr is not None:
    tags = [d.value for d in tag_attr.data]
## Only this side's hand: both hands carry the same patch tags, and the other one can come within
## the handle's window (crossed hands in a pose), so a sample must be skinned mostly to Hand.SIDE.
_hand_group = body.vertex_groups.get("Hand." + SIDE)
if _hand_group is not None:
    for _v in body.data.vertices:
        if tags[_v.index] in PATCH_NAMES and not any(g.group == _hand_group.index and g.weight >= 0.5 for g in _v.groups):
            tags[_v.index] = 0
points = [world @ v.co for v in mesh.vertices]


def mm(p):
    return (p.x * 1000.0, p.y * 1000.0, p.z * 1000.0)


samples = []
for i, p in enumerate(points):
    if tags[i] in PATCH_NAMES:
        samples.append((PATCH_NAMES[tags[i]], mm(p)))
for e in mesh.edges:
    a, b = e.vertices
    if tags[a] in PATCH_NAMES and tags[a] == tags[b]:
        samples.append((PATCH_NAMES[tags[a]], mm((points[a] + points[b]) * 0.5)))
for f in mesh.polygons:
    ids = [tags[i] for i in f.vertices]
    if ids[0] in PATCH_NAMES and all(t == ids[0] for t in ids):
        c = sum((points[i] for i in f.vertices), Vector()) / len(f.vertices)
        samples.append((PATCH_NAMES[ids[0]], mm(c)))
evaluated.to_mesh_clear()
## The real oval grip when the contact names it: semi-axes (m) along a hand-local direction (the
## weapon's edge axis) and across it. Otherwise the enclosing circle.
section = None
if CONTACT.get("handle_section_m"):
    a_axis = (hand_world.to_3x3() @ Vector(CONTACT["handle_section_a_axis_hand_local"]))
    a_axis = (a_axis - axis * a_axis.dot(axis)).normalized()
    section = (CONTACT["handle_section_m"][0] * 1000.0, CONTACT["handle_section_m"][1] * 1000.0, tuple(a_axis))
report = grip_contact.measure(samples, mm(centre), tuple(axis), radius * 1000.0, HALF_LENGTH_M * 1000.0, tuple(ref), section=section)
out = {"side": SIDE, "section": "oval" if section else "circle", "patches": report, "problems": grip_contact.problems(report),
       "diagnostics": grip_contact.diagnostics(report),
       "tagged_vertices": sum(1 for t in tags if t in PATCH_NAMES), "units": "mm",
       "tolerance_mm": grip_contact.TOLERANCE, "penetration_limit_mm": grip_contact.PENETRATION_LIMIT}


def _render(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


if OUT_DIR:
    sc = bpy.context.scene
    saved = {"camera": sc.camera, "engine": sc.render.engine, "rx": sc.render.resolution_x, "ry": sc.render.resolution_y,
             "xray": sc.display.shading.show_xray, "xray_alpha": sc.display.shading.xray_alpha,
             "color_type": sc.display.shading.color_type, "light": sc.display.shading.light,
             "hidden": {o.name: o.hide_render for o in bpy.data.objects}, "smooth": [p.use_smooth for p in body.data.polygons]}
    made = []
    handle_mesh = bpy.data.meshes.new("GripRefHandle")
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=32, radius1=radius, radius2=radius, depth=2 * HALF_LENGTH_M + 0.1)
    bm.to_mesh(handle_mesh)
    bm.free()
    handle = bpy.data.objects.new("GripRefHandle", handle_mesh)
    sc.collection.objects.link(handle)
    handle.matrix_world = Matrix.Translation(centre) @ Vector((0, 0, 1)).rotation_difference(axis).to_matrix().to_4x4()
    made.append(handle)
    for o in bpy.data.objects:
        if o.type == "MESH":
            o.hide_render = o not in (body, handle)
    for p in body.data.polygons:
        p.use_smooth = True
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "OBJECT"
    sc.render.resolution_x = sc.render.resolution_y = 400
    sc.render.image_settings.file_format = "PNG"
    body.color = (0.85, 0.75, 0.68, 1.0)
    handle.color = (0.35, 0.25, 0.18, 1.0)
    cam_data = bpy.data.cameras.new("GripRefCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 0.16
    cam = bpy.data.objects.new("GripRefCam", cam_data)
    sc.collection.objects.link(cam)
    made.append(cam)
    sc.camera = cam
    knuckles = (hand_world.to_3x3() @ Vector((0, 1, 0))).normalized()
    views = {"end": -axis if SIDE == "R" else axis,
             "threequarter": (ref * 0.55 - axis * 0.45 + knuckles * 0.5).normalized()}
    paths = []
    for vname, d in views.items():
        up = knuckles if vname == "end" else (knuckles - d * knuckles.dot(d)).normalized()
        x = up.cross(d).normalized()
        cam.matrix_world = Matrix((x, d.cross(x), d)).transposed().to_4x4()
        cam.location = centre + d * 0.5
        for mode in ("opaque", "xray", "hidden"):
            sc.display.shading.show_xray = mode == "xray"
            sc.display.shading.xray_alpha = 0.45
            handle.hide_render = mode == "hidden"
            paths.append(_render(os.path.join(OUT_DIR, "%s_%s_%s_%s.png" % (TAG, SIDE, vname, mode))))
    sc.display.shading.show_xray = False
    ## The cross-section at the handle's mid-plane: hand outline and handle circle as thin tubes.
    bm = bmesh.new()
    bm.from_object(body, deps)
    bm.transform(world)
    cut = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=centre, plane_no=axis)
    keep = {e for e in cut["geom_cut"] if isinstance(e, bmesh.types.BMEdge)}
    near = [e for e in keep if (sum((v.co for v in e.verts), Vector()) / 2 - centre).length < 0.08]
    sec = bmesh.new()
    vmap = {}
    for e in near:
        ends = []
        for v in e.verts:
            if v not in vmap:
                vmap[v] = sec.verts.new(v.co)
            ends.append(vmap[v])
        sec.edges.new(ends)
    bm.free()
    sec_mesh = bpy.data.meshes.new("GripRefSection")
    sec.to_mesh(sec_mesh)
    sec.free()
    section = bpy.data.objects.new("GripRefSection", sec_mesh)
    sc.collection.objects.link(section)
    made.append(section)
    section.modifiers.new("wire", "SKIN")
    for v in section.data.skin_vertices[0].data:
        v.radius = (0.0006, 0.0006)
    circle_mesh = bpy.data.meshes.new("GripRefCircle")
    cb = bmesh.new()
    bmesh.ops.create_circle(cb, segments=48, radius=radius)
    cb.to_mesh(circle_mesh)
    cb.free()
    circle = bpy.data.objects.new("GripRefCircle", circle_mesh)
    sc.collection.objects.link(circle)
    circle.matrix_world = handle.matrix_world.copy()
    circle.modifiers.new("wire", "SKIN")
    for v in circle.data.skin_vertices[0].data:
        v.radius = (0.0006, 0.0006)
    made.append(circle)
    section.color = (0.9, 0.9, 0.9, 1.0)
    circle.color = (0.85, 0.45, 0.2, 1.0)
    for o in bpy.data.objects:
        if o.type == "MESH":
            o.hide_render = o not in (section, circle)
    d = views["end"]
    up = knuckles
    x = up.cross(d).normalized()
    cam.matrix_world = Matrix((x, d.cross(x), d)).transposed().to_4x4()
    cam.location = centre + d * 0.5
    paths.append(_render(os.path.join(OUT_DIR, "%s_%s_section.png" % (TAG, SIDE))))
    ## Restore the scene exactly: nothing from the inspection is left behind.
    for o in made:
        data = o.data
        bpy.data.objects.remove(o)
        if isinstance(data, bpy.types.Mesh):
            bpy.data.meshes.remove(data)
        elif isinstance(data, bpy.types.Camera):
            bpy.data.cameras.remove(data)
    for p, s in zip(body.data.polygons, saved["smooth"]):
        p.use_smooth = s
    for o in bpy.data.objects:
        o.hide_render = saved["hidden"].get(o.name, o.hide_render)
    sc.camera = saved["camera"]
    sc.render.engine = saved["engine"]
    sc.render.resolution_x, sc.render.resolution_y = saved["rx"], saved["ry"]
    sc.display.shading.show_xray = saved["xray"]
    sc.display.shading.xray_alpha = saved["xray_alpha"]
    sc.display.shading.color_type = saved["color_type"]
    sc.display.shading.light = saved["light"]
    out["renders"] = paths

print("GRIP_CONTACT " + json.dumps(out))
result = out
