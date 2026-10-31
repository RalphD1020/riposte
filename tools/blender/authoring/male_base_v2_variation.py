"""Build resolved characters on the approved male base v2 (CHARACTER-VARIATION-001), with
the approved hair and face marks fitted to each, and measure the fit.

The Blender half of `character_modeling.variation`: the pure resolver decides every number
(physique parameters, head proportions and morphology, identity placement); this applies
them to the approved objects in `male_base.v2.blend` (`BodyV2`, `HeadV2`, never edited) on
copies, then fits the approved hairstyles (`wolf_hair.build_style`) and Wolf's face marks
(`wolf_face.place_marks`) to the resolved head and body through the same surface queries
they always used. No vertex index of any default head is used.

- Body: the configuration keys of v1's `Body` (16 keys, 8 parameters), evaluated in the
  authoring A-pose and carried onto `BodyV2` by the nearest point of v1's posed surface
  (as `garment_physique` carries them onto a garment), then smoothed over `BodyV2` so v1's
  facets do not print into the sculpt; the neck follows the head's `neck_transition`.
- Head: `variation.head_displacement` on a copy of `HeadV2` and on its stored
  construction surface, then the allometric size about the Head joint.
- Stature: the whole character scales by `height / 1.80` about the floor, as the game's
  fighter does.

Review builds: the outputs are scratch blends (lineups) and a JSON report; no master, no
attire blend, no export is written.

    blender --background --factory-startup --python tools/blender/authoring/male_base_v2_variation.py -- \
        --set configurations|matrix|identity|hair --out <dir>
"""

import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.interpolate import poly_3d_calc

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tools", "character_modeling"))
sys.path.insert(0, os.path.join(ROOT, "tools", "blender", "inspect"))
import face_surface  # noqa: E402
import male_base_v2 as v2  # noqa: E402
import wolf_face  # noqa: E402
import wolf_hair  # noqa: E402
from character_modeling import face_mapping, variation  # noqa: E402

CONFIGURATION = os.path.join(v2.CHARACTERS, "male_base.v2.configuration.json")
MANIFEST = os.path.join(v2.CHARACTERS, "wolf", "wolf.assembly.json")
## Smoothing of the transferred key deltas over BodyV2 (v1's facets are ~40 mm wide).
DELTA_SMOOTH_ITERATIONS = 40
NECK_BAND = (-0.3, 0.0, 0.7, 1.0)
SPACING_M = 1.9
## Fit tolerances (metres): hair may rest on the scalp within this depth; a mark's base may
## sit this far off the surface (it is sunk by its own depth_m by design).
HAIR_INSIDE_TOLERANCE_M = 0.0015
## A head triangle whose normal points down more steeply than this is the underside.
UNDERSIDE_NORMAL_Z = 0.5
SKIN = (0.62, 0.47, 0.38, 1.0)
INK = (0.021, 0.024, 0.027, 1.0)


def _document():
    with open(CONFIGURATION, encoding="utf-8") as handle:
        return json.load(handle)


def _marks():
    with open(MANIFEST, encoding="utf-8") as handle:
        return json.load(handle)["identity"]["face"]["marks"]


def _coords(obj):
    import numpy as np
    co = np.empty(len(obj.data.vertices) * 3)
    obj.data.vertices.foreach_get("co", co)
    return co.reshape(-1, 3)


def _evaluated(body):
    import numpy as np
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh = body.evaluated_get(depsgraph).to_mesh()
    co = np.empty(len(mesh.vertices) * 3)
    mesh.vertices.foreach_get("co", co)
    body.evaluated_get(depsgraph).to_mesh_clear()
    return co.reshape(-1, 3) @ np.array(body.matrix_world.to_3x3()).T + np.array(tuple(body.matrix_world.translation))


def key_deltas():
    """{key name: (n, 3) delta on BodyV2}: v1's keys in the A-pose, carried and smoothed."""
    import numpy as np
    v2.apose()
    body, target = bpy.data.objects["Body"], bpy.data.objects[v2.SCULPT]
    blocks = body.data.shape_keys.key_blocks
    for block in blocks[1:]:
        block.value = 0.0
    basis = _evaluated(body)
    posed = {}
    for block in blocks[1:]:
        block.value = 1.0
        posed[block.name] = _evaluated(body) - basis
        block.value = 0.0
    faces = [list(p.vertices) for p in body.data.polygons]
    tree = BVHTree.FromPolygons([Vector(p) for p in basis], faces)
    points = _coords(target)
    count = len(points)
    index = np.zeros((count, 4), dtype=np.int64)
    weight = np.zeros((count, 4))
    for i, p in enumerate(points):
        location, _n, face, _d = tree.find_nearest(Vector(p))
        corners = faces[face]
        share = poly_3d_calc([Vector(basis[c]) for c in corners], location)
        index[i, :len(corners)] = corners
        weight[i, :len(corners)] = share
    edges = np.array([tuple(e.vertices) for e in target.data.edges])
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


def _neck_scale(points, weights, scale):
    import numpy as np
    if scale == 1.0:
        return points
    _m, head, tail = v2.bone_frame("Neck")
    head, tail = np.array(tuple(head)), np.array(tuple(tail))
    a = (tail - head) / np.linalg.norm(tail - head)
    along = (points - head) @ a
    t = along / np.linalg.norm(tail - head)
    radial = points - (head + along[:, None] * a)
    w = np.minimum(weights.get("Neck", 0.0), 1.0) * v2._window(np, t, NECK_BAND)
    return points + (w * (scale - 1.0))[:, None] * radial


def _material(name, colour):
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    material.diffuse_color = colour
    return material


def build_body(resolved, deltas, weights, name):
    import numpy as np
    source = bpy.data.objects[v2.SCULPT]
    obj = source.copy()
    obj.data = source.data.copy()
    obj.name = obj.data.name = name
    co = _coords(source)
    for parameter, value in resolved["parameters"].items():
        if value:
            co = co + abs(value) * deltas["%s_%s" % (parameter, "plus" if value > 0 else "minus")]
    co = _neck_scale(co, weights, resolved["head"]["neck_radial_scale"])
    obj.data.vertices.foreach_set("co", co.ravel())
    obj.data.update()
    obj.data.materials.clear()
    obj.data.materials.append(_material("skin", SKIN))
    return obj


def build_head(resolved, name):
    """A copy of HeadV2 morphed by the resolved head parameters (surface and construction
    surface alike), then sized about the Head joint (relative to the body's stature)."""
    import numpy as np
    source = bpy.data.objects[v2.STUDY]
    obj = source.copy()
    obj.data = source.data.copy()
    obj.name = obj.data.name = name
    stored = obj.data.attributes[v2.F0_ATTRIBUTE]
    construction = np.array([tuple(a.vector) for a in stored.data])
    frame = {"low": construction[:, 2].min(), "height": np.ptp(construction[:, 2]),
             "half_width": np.abs(construction[:, 0]).max(), "front": construction[:, 1].min(), "back": construction[:, 1].max()}
    params = resolved["head"]["parameters"]
    proportions = resolved["head"]["proportions"]
    _m, pivot, _t = v2.bone_frame("Head")
    pivot = np.array(tuple(pivot))
    size = np.array([proportions["relative_scale"] * proportions["width_scale"],
                     proportions["relative_scale"] * proportions["depth_scale"], proportions["relative_scale"]])

    def morph(points):
        moved = np.array([np.add(p, variation.head_displacement(tuple(p), frame, params)) for p in points])
        return pivot + (moved - pivot) * size

    surface = morph(_coords(obj))
    obj.data.vertices.foreach_set("co", surface.ravel())
    stored.data.foreach_set("vector", morph(construction).ravel())
    obj.data.update()
    obj.data.materials.clear()
    obj.data.materials.append(_material("skin", SKIN))
    chart = (frame["low"], frame["height"], frame["half_width"])
    chart = (pivot[2] + (chart[0] - pivot[2]) * size[2], chart[1] * size[2], chart[2] * size[0])
    return obj, chart


def fit_face(head, chart, resolved, collection, prefix):
    tree = wolf_face.head_of(head)
    marks = _marks()
    report = wolf_face.place_marks(collection, tree, chart[0], chart[1], chart[2], marks,
                                   resolved["face"]["eye_spacing_u"], resolved["face"]["brow_tilt_deg"])
    ink = _material("hair", INK)
    out = {}
    for name, centre, normal in report:
        obj = collection.objects[name]
        obj.name = "%s.%s" % (prefix, name)
        obj.data.materials.append(ink)
        if name.startswith("DeadEye"):
            obj.hide_render = True
        _loc, surface_normal, _i, distance = tree.find_nearest(centre)
        out[name] = {"base_off_surface_mm": round(distance * 1000, 2),
                     "normal_deg": round(math.degrees(normal.angle(surface_normal if surface_normal.y < 0 else -surface_normal)), 1)}
    return out


def fit_hair(head, body, which, collection, prefix):
    frame = wolf_hair.head_frame_of(head, body)
    obj = wolf_hair.build_style(frame, which)
    obj.name = "%s.%s" % (prefix, obj.name)
    collection.objects.link(obj)
    return obj


def _inside(obj, tree, tolerance):
    """Vertices of `obj` behind the surface in `tree` (nearest point, its normal):
    count and the deepest, metres."""
    count, deepest = 0, 0.0
    for v in obj.data.vertices:
        p = obj.matrix_world @ v.co
        location, normal, _i, _d = tree.find_nearest(p)
        if location is None:
            continue
        depth = -(p - location).dot(normal)
        if depth > tolerance:
            count += 1
            deepest = max(deepest, depth)
    return {"vertices": count, "deepest_mm": round(deepest * 1000, 1)}


def _tree(obj):
    points = [obj.matrix_world @ v.co for v in obj.data.vertices]
    return BVHTree.FromPolygons(points, [list(p.vertices) for p in obj.data.polygons])


def measure(head, body, hair, chart):
    head_tree, body_tree = _tree(head), _tree(body)
    sample = face_surface.sample(head, chart)
    surface = face_mapping.FaceSurface(sample)
    marks = _marks()
    landmarks = face_mapping.derive_landmarks(surface, marks)
    attachments = {}
    for kind, (landmark, region) in face_surface.WOLF_ATTACHMENTS.items():
        for side in ("L", "R"):
            attachments["%s.%s" % (kind, side)] = {"landmark": "%s.%s" % (landmark, side), "region": region,
                                                   "normal_offset_m": marks[kind].get("proud_m", 0.0)}
    problems, _frames = face_mapping.attachment_problems(surface, landmarks, attachments)
    problems += face_mapping.landmark_problems(landmarks)
    zs = [(head.matrix_world @ v.co).z for v in head.data.vertices]
    body_zs = [(body.matrix_world @ v.co).z for v in body.data.vertices]
    ## Head/body integration: where the body's surface crosses the head's, by the facing of
    ## the head triangle crossed. The neck's ring is tilted: it enters under the jaw
    ## (underside) and through the lower occiput at the nape (facing back): both are the
    ## seam. A crossing through the jaw's sides or the face (facing out or forward) is the
    ## neck or the trapezius showing through: a defect.
    low = min(zs)
    classes = {"underside": 0, "nape": 0, "side": 0, "front": 0, "up": 0}
    defect_z = []
    head_world = head.matrix_world.to_3x3()
    for head_index, _body_index in head_tree.overlap(body_tree):
        n = (head_world @ head.data.polygons[head_index].normal).normalized()
        if n.z < -UNDERSIDE_NORMAL_Z:
            kind = "underside"
        elif n.y > abs(n.x) and n.y > 0.3:
            kind = "nape"
        elif n.y < -abs(n.x):
            kind = "front"
        elif n.z > UNDERSIDE_NORMAL_Z:
            kind = "up"
        else:
            kind = "side"
        classes[kind] += 1
        if kind in ("side", "front", "up"):
            defect_z.append((head.matrix_world @ head.data.polygons[head_index].center).z - low)
    poking = dict(classes, defect_pairs=len(defect_z),
                  defect_height_above_chin_mm=[round(min(defect_z) * 1000, 1), round(max(defect_z) * 1000, 1)] if defect_z else None)
    report = {"head_height_m": round(max(zs) - low, 4), "figure_height_m": round(max(zs) - min(body_zs), 4),
              "heads_tall": round((max(zs) - min(body_zs)) / (max(zs) - low), 2),
              "landmarks_uv": {k: [round(c, 4) for c in uv] for k, uv in sorted(landmarks.items())},
              "landmark_problems": problems, "neck_through_head_vertices": poking}
    if hair is not None:
        report["hair_inside_head"] = _inside(hair, head_tree, HAIR_INSIDE_TOLERANCE_M)
        report["hair_inside_body"] = _inside(hair, body_tree, HAIR_INSIDE_TOLERANCE_M)
    return report


def build_character(resolved, deltas, weights, name, hair_style, x):
    collection = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(collection)
    body = build_body(resolved, deltas, weights, "%s.Body" % name)
    head, chart = build_head(resolved, "%s.Head" % name)
    collection.objects.link(body)
    collection.objects.link(head)
    face = fit_face(head, chart, resolved, collection, name)
    hair = fit_hair(head, body, hair_style, collection, name) if hair_style else None
    report = measure(head, body, hair, chart)
    report["face_marks"] = face
    root = bpy.data.objects.new("%s.Root" % name, None)
    collection.objects.link(root)
    h = resolved["stature_scale"]
    root.matrix_world = Matrix.Translation((x, 0.0, 0.0)) @ Matrix.Scale(h, 4)
    for obj in collection.objects:
        if obj is not root:
            obj.parent = root
    report["figure_height_scaled_m"] = round(report["figure_height_m"] * h, 4)
    return report


def _definitions(which, document):
    configurations = document["configurations"]
    order = ("extreme_lean", "lean", "lean_half", "default", "heavy_half", "heavy", "extreme_heavy")
    if which == "configurations":
        return [(n, variation.configuration_definition(configurations, n), "ranger") for n in order]
    if which == "matrix":
        return [(n, {"body": {"height_m": h, "frame_build": f, "muscularity": m}}, "ranger")
                for n, h, f, m in variation.BOUNDARY_MATRIX]
    if which == "identity":
        ## Same-face check: five head identities on the default body, then one identity on
        ## three physiques (the identity must hold, the proportions must follow).
        rows = [("id_%s" % a, {"body": dict(variation.configuration_definition(configurations, "default")["body"]),
                               "head": {"archetype": a}}, None) for a in ("reference", "angular", "broad", "elongated", "compact")]
        for n in ("extreme_lean", "default", "extreme_heavy"):
            rows.append(("angular_%s" % n, dict(variation.configuration_definition(configurations, n), head={"archetype": "angular"}), None))
        return rows
    if which == "hair":
        rows = []
        for n in ("extreme_lean", "default", "extreme_heavy"):
            for style in ("ranger", "training"):
                rows.append(("%s_%s" % (style, n), variation.configuration_definition(configurations, n), style))
        for n, h, f, m in variation.BOUNDARY_MATRIX:
            if n in ("short_powerful", "tall_lean"):
                for style in ("ranger", "training"):
                    rows.append(("%s_%s" % (style, n), {"body": {"height_m": h, "frame_build": f, "muscularity": m}}, style))
        return rows
    raise SystemExit("unknown set %s" % which)


BOARD_VIEWS = {"front": 0.0, "three_quarter": 35.0, "side": 90.0, "rear": 180.0}
## (spacing m, look-at z, height m, pixels per metre): whole figures or heads and necks.
BOARD_FRAMES = {"body": (SPACING_M, 1.0, 2.35, 260), "head": (0.78, 1.66, 0.56, 700)}


def render_board(blend, out, views, frame="body", gameplay=(), only=""):
    """Render a lineup blend as boards: every character turned on its own root to the view
    (so side and rear read in one row), labelled; `gameplay` names characters rendered
    alone through the shipped match camera (render_views' constants). Head boards lift
    every character so the heads share one line whatever the stature; `only` keeps the
    characters whose name starts with it."""
    import render_views
    bpy.ops.wm.open_mainfile(filepath=blend)
    scene = bpy.context.scene
    roots = sorted((o for o in bpy.data.objects if o.name.endswith(".Root")), key=lambda o: o.matrix_world.translation.x)
    for root in [r for r in roots if not r.name.startswith(only)]:
        for child in root.children_recursive:
            child.hide_render = True
    roots = [r for r in roots if r.name.startswith(only)]
    spacing, look_z, height_m, ppm = BOARD_FRAMES[frame]
    for i, root in enumerate(roots):
        root.location.x = i * spacing
        if frame == "head":
            head = bpy.data.objects["%s.Head" % root.name[:-5]]
            bpy.context.view_layer.update()
            zs = [(head.matrix_world @ v.co).z for v in head.data.vertices]
            root.location.z += look_z + 0.03 - 0.5 * (min(zs) + max(zs))
        label = bpy.data.curves.new("%s.Label" % root.name[:-5], "FONT")
        label.body = root.name[:-5]
        label.size = 0.06 if frame == "head" else 0.11
        label.align_x = "CENTER"
        text = bpy.data.objects.new(label.name, label)
        text.location = (i * spacing, -0.6, look_z - height_m * 0.46)
        text.rotation_euler = (math.radians(90.0), 0.0, 0.0)
        text.color = (0.1, 0.1, 0.1, 1.0)
        text.data.materials.append(_material("label", (0.1, 0.1, 0.12, 1.0)))
        scene.collection.objects.link(text)
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    width_m = spacing * len(roots)
    camera_data = bpy.data.cameras.new("BoardCamera")
    camera = bpy.data.objects.new("BoardCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    written = []
    for view in views:
        for root in roots:
            root.rotation_euler = (0.0, 0.0, math.radians(BOARD_VIEWS[view]))
        camera_data.type = "ORTHO"
        camera_data.ortho_scale = max(width_m, height_m)
        scene.render.resolution_x = int(width_m * ppm)
        scene.render.resolution_y = int(height_m * ppm)
        camera.location = ((len(roots) - 1) * spacing * 0.5, -render_views.CAMERA_DISTANCE_M, look_z)
        camera.rotation_euler = (math.radians(90.0), 0.0, 0.0)
        scene.render.filepath = "%s_%s.png" % (out, view)
        bpy.ops.render.render(write_still=True)
        written.append(scene.render.filepath)
    for root in roots:
        root.rotation_euler = (0.0, 0.0, 0.0)
    for name in gameplay:
        root = bpy.data.objects["%s.Root" % name]
        keep = root.location.x
        for other in roots:
            other.hide_render = True
            for child in other.children_recursive:
                child.hide_render = child.name.split(".", 1)[-1].startswith("DeadEye") or other is not root
        root.location.x = 0.0
        pitch = math.radians(render_views.GAMEPLAY_PITCH_DEG)
        camera_data.type = "PERSP"
        camera_data.angle = math.radians(render_views.GAMEPLAY_FOV_DEG)
        camera.location = render_views.GAMEPLAY_LOOK_AT + Vector((0.0, -math.cos(pitch), math.sin(pitch))) * render_views.GAMEPLAY_DISTANCE_M
        camera.rotation_euler = (math.radians(90.0) - pitch, 0.0, 0.0)
        scene.render.resolution_x, scene.render.resolution_y = 1280, 720
        scene.render.filepath = "%s_gameplay_%s.png" % (out, name)
        bpy.ops.render.render(write_still=True)
        written.append(scene.render.filepath)
        root.location.x = keep
    return written


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    if "--render" in args:
        sys.path.insert(0, os.path.join(ROOT, "tools", "blender", "inspect"))
        frame = args[args.index("--frame") + 1] if "--frame" in args else "body"
        views = args[args.index("--views") + 1].split(",") if "--views" in args else list(BOARD_VIEWS)
        gameplay = args[args.index("--gameplay") + 1].split(",") if "--gameplay" in args else ()
        only = args[args.index("--only") + 1] if "--only" in args else ""
        print("RIPOSTE_BOARD", json.dumps(render_board(os.path.abspath(args[args.index("--render") + 1]),
                                                       os.path.abspath(args[args.index("--out") + 1]), views, frame, gameplay, only)))
        return
    which = args[args.index("--set") + 1]
    out_dir = os.path.abspath(args[args.index("--out") + 1])
    document = _document()
    bpy.ops.wm.open_mainfile(filepath=v2.CANDIDATE)
    v2.apose()
    deltas = key_deltas()
    weights = v2._transfer_weights([tuple(c) for c in _coords(bpy.data.objects[v2.SCULPT])])
    reports = {}
    for i, (name, definition, hair_style) in enumerate(_definitions(which, document)):
        resolved = variation.resolve(definition, document)
        report = build_character(resolved, deltas, weights, name, hair_style, i * SPACING_M)
        report["x_m"] = i * SPACING_M
        report["body_inputs"] = resolved["body"]
        report["mass_kg"] = round(resolved["physique"]["mass_kg"], 2)
        report["parameters"] = {k: round(v, 3) for k, v in resolved["parameters"].items() if v}
        report["head_parameters"] = {k: v for k, v in resolved["head"]["parameters"].items() if v}
        report["head_proportions"] = resolved["head"]["proportions"]
        reports[name] = report
        print("RIPOSTE_VARIANT", name, json.dumps({k: report[k] for k in ("mass_kg", "heads_tall", "neck_through_head_vertices")}
                                                  | {k: report.get(k) for k in ("hair_inside_head", "hair_inside_body")}
                                                  | {"landmark_problems": len(report["landmark_problems"])}))
    for name in ("Body", v2.SCULPT, v2.STUDY):
        bpy.data.objects.remove(bpy.data.objects[name], do_unlink=True)
    os.makedirs(out_dir, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out_dir, "%s.blend" % which), copy=True)
    with open(os.path.join(out_dir, "%s.json" % which), "w", encoding="utf-8") as handle:
        json.dump(reports, handle, indent=1)
    print("RIPOSTE_VARIATION_SET", which, len(reports))


if __name__ == "__main__":
    main()
