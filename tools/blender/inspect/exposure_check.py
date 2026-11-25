"""GARMENT-COVERAGE: where skin may show on the assembled, posed character (a QA pass).

The appearance plan's `coverage` decides which faces may be removed; this checks what the
final character shows. An outfit declares its exposure policy (`exposure` in the character
manifest's outfit: `must_cover` foundation regions, each optionally bounded along a bone
with `until: [bone, fraction]`, and `must_remain_visible` objects such as the eyes);
everything else may show. The derived body and head carry their foundation regions
(`riposte_region`, stamped before trimming), so the policy reads the final meshes.

For every pose-suite sample (POSE-SUITE-001) and view, a flat surface-ID render (no
antialiasing, no lighting: must-cover skin red, permitted skin green, must-remain-visible
blue, every other object its own grey ID) is written next to its counts. A forbidden blob
fails when it covers at least one pixel of the 1080p gameplay camera at this capture's
scale (smaller blobs are below what a player can see); a must-remain-visible feature fails
when less than VISIBLE_SHARE of it shows compared with the bare head in the same view.

    blender -b --factory-startup --python exposure_check.py -- --blend <b> --prefix wolf_ranger
        --manifest <wolf.json> --outfit ranger --out <dir> [--views front,three_quarter,side,rear]
        [--samples all|acceptance|rest] [--hide a,b]
Prints RIPOSTE_EXPOSURE <json> (per sample and view, and the verdict)."""

import argparse
import json
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "character_modeling"))
sys.path.insert(0, os.path.join(ROOT, "tools", "blender", "authoring"))
sys.path.insert(0, HERE)
import skeleton_capture  # noqa: E402
from character_modeling import pose_suite  # noqa: E402
import pose_fixture  # noqa: E402

MUST_COVER = (1.0, 0.0, 0.0)
MAY_EXPOSE = (0.0, 1.0, 0.0)
MUST_SHOW = (0.0, 0.0, 1.0)
## Covered skin just inside an opening (`opening: [bone, fraction]`, the wrist inside a
## cuff): seen through the opening (continuous with the permitted skin beyond it) it may
## show; seen anywhere else (a gap, a sleeve slid up) it is forbidden.
OPENING = (1.0, 1.0, 0.0)
VIEWS = {"front": 0.0, "three_quarter": 35.0, "side": 90.0, "rear": 180.0, "three_quarter_other": -35.0}
SCALE_M, RES = 2.1, (720, 900)
CAMERA_DISTANCE_M = 6.0
## The gameplay camera the blob size is calibrated against (render_views' gameplay view at 1080p).
GAMEPLAY_FOV_DEG, GAMEPLAY_DISTANCE_M, GAMEPLAY_HEIGHT_PX = 40.0, 14.0, 1080
VISIBLE_SHARE = 0.9
FACE_PARTS = ("Body", "Head", "Ear", "Eye", "Brow")


def _arguments():
    p = argparse.ArgumentParser()
    p.add_argument("--blend", required=True)
    p.add_argument("--prefix", required=True)
    p.add_argument("--manifest", required=True)
    p.add_argument("--outfit", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--views", default="front,three_quarter,side,rear")
    p.add_argument("--samples", default="acceptance")
    p.add_argument("--hide", default="")
    p.add_argument("--only", default="", help="comma list of pose-suite fixture ids (and rest) to check")
    p.add_argument("--clips", type=int, default=0,
                   help="check the production clips in the blend instead, every N frames (intermediate frames included)")
    return p.parse_args(sys.argv[sys.argv.index("--") + 1:])


def min_blob_px():
    """One 1080p gameplay pixel's area in this capture's pixels."""
    game = GAMEPLAY_HEIGHT_PX / (2.0 * GAMEPLAY_DISTANCE_M * math.tan(math.radians(GAMEPLAY_FOV_DEG) / 2.0))
    qa = max(RES) / SCALE_M
    return max(1, int(round((qa / game) ** 2)))


def _bone_fraction(rig, bone, point):
    b = rig.data.bones[bone]
    head, tail = rig.matrix_world @ b.head_local, rig.matrix_world @ b.tail_local
    axis = tail - head
    return (point - head).dot(axis) / max(1e-9, axis.length_squared)


def classify(obj, rig, policy, rest):
    """Per vertex of `obj` (rest positions `rest`): MUST_COVER, MAY_EXPOSE."""
    names = list(obj.get("riposte_regions", ()))
    tags = obj.data.attributes.get("riposte_region")
    rules = {}
    for rule in policy.get("must_cover", ()):
        rules[rule["region"] if isinstance(rule, dict) else rule] = rule
    out = []
    for i in range(len(obj.data.vertices)):
        region = names[tags.data[i].value] if tags is not None and 0 <= tags.data[i].value < len(names) else None
        rule = rules.get(region)
        if rule is None:
            out.append(MAY_EXPOSE)
            continue
        until = rule.get("until") if isinstance(rule, dict) else None
        opening = rule.get("opening") if isinstance(rule, dict) else None
        if until and _bone_fraction(rig, until[0], rest[i]) > until[1]:
            out.append(MAY_EXPOSE)
        elif opening and _bone_fraction(rig, opening[0], rest[i]) > opening[1]:
            out.append(OPENING)
        else:
            out.append(MUST_COVER)
    return out


def _paint(obj, colours):
    """A flat colour attribute (per vertex list, or one colour) made active for Workbench."""
    me = obj.data
    attr = me.color_attributes.get("riposte_qa") or me.color_attributes.new("riposte_qa", "BYTE_COLOR", "POINT")
    if isinstance(colours, tuple):
        colours = [colours] * len(me.vertices)
    for d, c in zip(attr.data, colours):
        d.color = (*c, 1.0)
    me.color_attributes.active_color = attr
    me.attributes.active_color = attr


def _bind_head_parts(objects, rig):
    """The study build leaves the head's rigid parts (head, eyes, brows, hair) unbound;
    the shipping assembly binds each on Head at weight 1 (`character_assembly.bind_rigid`).
    The check poses what ships: an unbound part is bound the same way (on this in-memory
    copy only; the parent is kept so nothing moves at rest)."""
    for obj in objects:
        if any(m.type == "ARMATURE" for m in obj.modifiers) or obj.name.endswith(".Body"):
            continue
        obj.vertex_groups.clear()
        obj.vertex_groups.new(name="Head").add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
        obj.modifiers.new("QAArmature", "ARMATURE").object = rig


def _play(rig, action, frame):
    """`rig` at `frame` of the production clip `action` (bones the clip turns by Euler curves
    take Euler rotation, or the curves are ignored)."""
    euler = set()
    for layer in getattr(action, "layers", ()):
        for strip in layer.strips:
            for slot in action.slots:
                bag = strip.channelbag(slot)
                for fc in bag.fcurves if bag else ():
                    if fc.data_path.startswith('pose.bones["') and fc.data_path.endswith(".rotation_euler"):
                        euler.add(fc.data_path.split('"')[1])
    pose_fixture.reset(rig)
    for pb in rig.pose.bones:
        pb.rotation_mode = "XYZ" if pb.name in euler else "QUATERNION"
    rig.animation_data_create()
    rig.animation_data.action = action
    if getattr(action, "slots", None):
        rig.animation_data.action_slot = action.slots[0]
    bpy.context.scene.frame_set(frame)


def _setup(scene):
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "FLAT"
    scene.display.shading.color_type = "VERTEX"
    scene.display.shading.show_specular_highlight = False
    scene.display.shading.show_backface_culling = True
    scene.display.render_aa = "OFF"
    scene.view_settings.view_transform = "Standard"
    scene.render.film_transparent = True
    scene.render.resolution_x, scene.render.resolution_y = RES
    scene.render.image_settings.file_format = "PNG"
    cam = bpy.data.cameras.new("QACamera")
    cam.type, cam.ortho_scale = "ORTHO", SCALE_M
    camera = bpy.data.objects.new("QACamera", cam)
    scene.collection.objects.link(camera)
    scene.camera = camera
    return camera


def _blobs(mask, pixels=False):
    """Connected components (4-neighbour) of a boolean HxW numpy mask: their sizes, largest
    first (or, `pixels`, each component's pixel list)."""
    import numpy as np
    seen = np.zeros_like(mask, dtype=bool)
    found = []
    h, w = mask.shape
    for y, x in zip(*np.nonzero(mask)):
        if seen[y, x]:
            continue
        stack, members = [(y, x)], []
        seen[y, x] = True
        while stack:
            cy, cx = stack.pop()
            members.append((cy, cx))
            for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((ny, nx))
        found.append(members)
    if pixels:
        return found
    return sorted((len(m) for m in found), reverse=True)


def _render(scene, path):
    import numpy as np
    skeleton_capture.render_still(scene, path, "exposure_check")
    img = bpy.data.images.load(path, check_existing=False)
    px = np.array(img.pixels[:]).reshape(img.size[1], img.size[0], 4)
    bpy.data.images.remove(img)
    return px


def _grow(mask):
    near = mask.copy()
    near[1:, :] |= mask[:-1, :]
    near[:-1, :] |= mask[1:, :]
    near[:, 1:] |= mask[:, :-1]
    near[:, :-1] |= mask[:, 1:]
    return near


def _counts(px, cuff_interior=False):
    """(forbidden, must-show, cuff-interior) masks: must-cover skin, and opening skin not
    continuous with permitted skin. With `cuff_interior` (the outfit's approved exception),
    must-cover skin seen down a cuff is its own mask, not forbidden: a blob that touches the
    cuff's opening band and is otherwise enclosed by the garment (never the background; a
    sleeve gap shows the forearm against the background or away from the hand)."""
    import numpy as np
    r, g, b, a = px[..., 0], px[..., 1], px[..., 2], px[..., 3]
    on = a > 0.5
    red = on & (r > 0.9) & (g < 0.1) & (b < 0.1)
    blue = on & (b > 0.9) & (r < 0.1) & (g < 0.1)
    green = on & (g > 0.9) & (r < 0.1) & (b < 0.1)
    yellow = on & (r > 0.9) & (g > 0.9) & (b < 0.1)
    near_green = _grow(green)
    for blob in _blobs(yellow, pixels=True):
        if not any(near_green[y, x] for y, x in blob):
            ys, xs = zip(*blob)
            red[np.array(ys), np.array(xs)] = True
    cuff = np.zeros_like(red)
    if cuff_interior:
        near_yellow, near_void = _grow(yellow), _grow(~on)
        for blob in _blobs(red, pixels=True):
            ys, xs = (np.array(c) for c in zip(*blob))
            if near_yellow[ys, xs].any() and not near_void[ys, xs].any():
                cuff[ys, xs] = True
                red[ys, xs] = False
    return red, blue, cuff


def main():
    args = _arguments()
    bpy.ops.wm.open_mainfile(filepath=os.path.abspath(args.blend))
    with open(args.manifest, encoding="utf-8") as handle:
        policy = json.load(handle)["outfits"][args.outfit].get("exposure") or {}
    scene = bpy.context.scene
    prefix = args.prefix
    hidden = {h for h in args.hide.split(",") if h}
    ## The dead-eye X is FacePresentation's swap for a downed fighter, never shown with the eyes.
    mine = [o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith(prefix + ".") and o.name not in hidden
            and not o.name.split(".", 1)[1].startswith("DeadEye")]
    for o in bpy.data.objects:
        if o.type == "MESH":
            o.hide_render = o not in mine
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE" and o.name.startswith(prefix))
    _bind_head_parts(mine, rig)
    pose_fixture.reset(rig)
    bpy.context.view_layer.update()
    show = set(policy.get("must_remain_visible", ()))
    skin = {"Body", "Head"} | {n for n in ("Ear.L", "Ear.R")}
    centre = sum((o.matrix_world.translation for o in mine if o.name.endswith(".Body")), Vector()) + Vector((0.0, 0.0, 0.95))
    for n, o in enumerate(sorted(mine, key=lambda o: o.name)):
        part = o.name.split(".", 1)[1]
        if part in ("Body", "Head"):
            dg = bpy.context.evaluated_depsgraph_get()
            e = o.evaluated_get(dg)
            m = e.to_mesh()
            rest = [o.matrix_world @ v.co for v in m.vertices]
            e.to_mesh_clear()
            _paint(o, classify(o, rig, policy, rest))
        elif any(part.startswith(s) for s in show):
            _paint(o, MUST_SHOW)
        elif part in skin:
            _paint(o, MAY_EXPOSE)
        else:
            grey = 0.25 + 0.5 * ((n * 37) % 11) / 10.0
            _paint(o, (grey, grey * 0.96, grey * 0.92))
    camera = _setup(scene)
    os.makedirs(args.out, exist_ok=True)
    samples = [{"id": "rest", "t": 0.0, "arms": {}}]
    if args.clips:
        samples = [{"id": a.name, "t": float(f), "clip": a} for a in sorted(bpy.data.actions, key=lambda a: a.name)
                   for f in range(int(round(a.frame_range[0])), int(round(a.frame_range[1])) + 1, args.clips)]
    elif args.samples != "rest":
        samples += pose_suite.samples(include_diagnostic=args.samples == "all")
    if args.only:
        samples = [s for s in samples if s["id"] in args.only.split(",")]
    blob_min = min_blob_px()
    ## Wrist skin seen down a cuff, contiguous with the hand (the outfit's approved exception).
    cuff_interior = policy.get("cuff_interior") == "contiguous_with_hand"
    ## What may hide a must-remain-visible feature: the outfit (garments, accessories, hair),
    ## never the face's own parts (lids, lines, brows).
    garments = [o for o in mine if not o.name.split(".", 1)[1].startswith(FACE_PARTS)]
    results, failures = [], []
    for s in samples:
        if "clip" in s:
            _play(rig, s["clip"], int(s["t"]))
        else:
            pose_fixture.apply(rig, s)
        bpy.context.view_layer.update()
        for view in args.views.split(","):
            angle = math.radians(VIEWS[view])
            camera.location = centre + Vector((math.sin(angle), -math.cos(angle), 0.0)) * CAMERA_DISTANCE_M
            camera.rotation_euler = (math.radians(90.0), 0.0, angle)
            tag = "%s_%.2f_%s" % (s["id"], s["t"], view)
            red, blue, cuff = _counts(_render(scene, os.path.join(args.out, "%s.png" % tag)), cuff_interior)
            blobs = _blobs(red)
            row = {"sample": s["id"], "t": s["t"], "view": view, "forbidden_px": int(red.sum()),
                   "largest_blob_px": blobs[0] if blobs else 0, "failing_blobs": sum(1 for b in blobs if b >= blob_min),
                   "cuff_interior_px": int(cuff.sum())}
            if show:
                for o in garments:
                    o.hide_render = True
                _r, bare, _c = _counts(_render(scene, os.path.join(args.out, "_bare.png")))
                for o in garments:
                    o.hide_render = False
                row["visible_share"] = round(float(blue.sum()) / max(1, int(bare.sum())), 3) if bare.sum() else None
            fail = row["failing_blobs"] > 0 or (row.get("visible_share") is not None and row["visible_share"] < VISIBLE_SHARE)
            row["pass"] = not fail
            if fail:
                failures.append(tag)
            results.append(row)
            print("RIPOSTE_EXPOSURE_ROW", json.dumps(row))
    pose_fixture.reset(rig)
    if os.path.exists(os.path.join(args.out, "_bare.png")):
        os.remove(os.path.join(args.out, "_bare.png"))
    report = {"outfit": args.outfit, "min_blob_px": blob_min, "rows": results, "failures": failures, "pass": not failures}
    with open(os.path.join(args.out, "exposure.json"), "w", encoding="utf-8", newline="\n") as handle:
        json.dump(report, handle, indent=1)
    print("RIPOSTE_EXPOSURE", json.dumps({"outfit": args.outfit, "min_blob_px": blob_min, "failures": len(failures),
                                          "checked": len(results), "pass": not failures}))


if __name__ == "__main__":
    main()
