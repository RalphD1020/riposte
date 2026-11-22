"""FACE-LAYERS: which surface the camera sees inside each eye's luminous aperture (a QA pass).

The facial counterpart of GARMENT-COVERAGE (`exposure_check.py`), built the same way: a flat
surface-ID render (Workbench, no lighting, no antialiasing) per expression state and view,
eyes magenta, HeadV2 cyan, brows yellow, every other surface grey. The eye rendered alone
gives each eye's intended aperture; the full face rendered over it reports the frontmost
owner of every aperture pixel. Inside the aperture the eye must be first: a HeadV2 pixel there
is skin breaking into the glow (a failure); a brow pixel is the brow hood covering the eye
(reported, the intended overhang); a hole in the eye-alone silhouette is a defect of the eye
mesh itself. The render is paired with geometry, as the attire checks are: the signed
clearance of every evaluated eye sample (vertices, face centres, edge midpoints) from the
HeadV2 surface along its normal (negative = behind the skin; large = floating).

States come from a JSON file, {label: {"L": {channel: w}, "R": {...}, "emission": e}}: the
expression evaluator exports it, so the check knows no expression logic. `--negative` pushes
the left eye's centre behind HeadV2 in memory first; the check must then fail (the negative
test). `--passes` also writes the eye-only / eye+head / eye+brow diagnostic renders.

    blender -b --factory-startup --python face_layers.py -- --blend <b> --prefix wolf_ranger
        --states <states.json> --out <dir> [--views front,three_quarter,three_quarter_other]
        [--only a,b] [--passes] [--negative]
Prints RIPOSTE_FACE_LAYERS <json> per state and view, then the verdict."""

import argparse
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import exposure_check  # noqa: E402

EYE = (1.0, 0.0, 1.0)
HEAD = (0.0, 1.0, 1.0)
BROW = (1.0, 1.0, 0.0)
OTHER = (0.25, 0.25, 0.25)
OWNERS = {"eye": EYE, "head": HEAD, "brow": BROW, "other": OTHER}
VIEWS = {"front": 0.0, "three_quarter": -32.0, "three_quarter_other": 32.0, "side": -80.0}
ORTHO_M, RES = 0.34, 720
## Blobs smaller than this many close-up pixels (~0.47 mm each) are below what any camera
## resolves; at or above it a HeadV2 intrusion or an eye hole fails.
MIN_BLOB_PX = 3
## An eye sample farther than this off the skin reads as detached (floating).
FLOAT_MM = 2.0
## The negative test: how far the left eye's centre is pushed behind the skin.
NEGATIVE_PUSH_M = 0.003


def _arguments():
    p = argparse.ArgumentParser()
    p.add_argument("--blend", required=True)
    p.add_argument("--prefix", required=True)
    p.add_argument("--states", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--views", default="front,three_quarter,three_quarter_other")
    p.add_argument("--only", default="")
    p.add_argument("--passes", action="store_true")
    p.add_argument("--negative", action="store_true")
    return p.parse_args(sys.argv[sys.argv.index("--") + 1:])


def component(obj, prefix):
    part = obj.name[len(prefix) + 1:] if obj.name.startswith(prefix + ".") else ""
    if part.startswith("Eye."):
        return "eye"
    if part == "Head":
        return "head"
    if part.startswith("Brow."):
        return "brow"
    return "other"


def _owner(px):
    """The surface ID of each pixel: the nearest palette colour (alpha 0 = background)."""
    import numpy as np
    rgb = px[..., :3]
    names = list(OWNERS)
    dist = np.stack([np.abs(rgb - np.array(OWNERS[n])).sum(axis=2) for n in names])
    out = np.array(names, dtype=object)[dist.argmin(axis=0)]
    out[px[..., 3] < 0.5] = "none"
    return out


def _holes(mask):
    """Background pixels fully enclosed by `mask` (not reachable from the image border)."""
    import numpy as np
    free = ~mask
    reach = np.zeros_like(mask)
    h, w = mask.shape
    stack = [(y, x) for y in range(h) for x in (0, w - 1) if free[y, x]]
    stack += [(y, x) for x in range(w) for y in (0, h - 1) if free[y, x]]
    for y, x in stack:
        reach[y, x] = True
    while stack:
        cy, cx = stack.pop()
        for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
            if 0 <= ny < h and 0 <= nx < w and free[ny, nx] and not reach[ny, nx]:
                reach[ny, nx] = True
                stack.append((ny, nx))
    return free & ~reach


def _world_tree(obj):
    deps = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(deps)
    bm = bmesh.new()
    bm.from_mesh(ev.to_mesh())
    bm.transform(obj.matrix_world)
    ev.to_mesh_clear()
    return BVHTree.FromBMesh(bm), bm


def clearance(eye, head_tree):
    """Signed distances (m) of the evaluated eye's samples from the skin along its normal."""
    deps = bpy.context.evaluated_depsgraph_get()
    ev = eye.evaluated_get(deps)
    me = ev.to_mesh()
    mw = eye.matrix_world
    points = [mw @ v.co for v in me.vertices]
    points += [mw @ p.center for p in me.polygons]
    points += [mw @ ((me.vertices[e.vertices[0]].co + me.vertices[e.vertices[1]].co) * 0.5) for e in me.edges]
    ev.to_mesh_clear()
    out = []
    for p in points:
        loc, normal, _i, _d = head_tree.find_nearest(p)
        if loc is not None:
            out.append((p - loc).dot(normal))
    return out


def cant_deg(eye):
    """The evaluated eye's corner cant in the front plane: the angle of the line from its inner
    corner (nearest the centre line) to its outer corner, positive when the outer is higher."""
    deps = bpy.context.evaluated_depsgraph_get()
    ev = eye.evaluated_get(deps)
    me = ev.to_mesh()
    pts = [eye.matrix_world @ v.co for v in me.vertices]
    ev.to_mesh_clear()
    inner = min(pts, key=lambda p: abs(p.x))
    outer = max(pts, key=lambda p: abs(p.x))
    return math.degrees(math.atan2(outer.z - inner.z, abs(outer.x) - abs(inner.x)))


## Brow contour gate: a designed edge may make this many deliberate broad turns; more is a
## squiggle. A thickness profile rises to one peak and falls (at most one turn).
BROW_EDGE_REVERSALS = 2
BROW_WIDTH_TURNS = 1
## A bend only counts toward a reversal when it moves the edge visibly: a turn of theta between
## segments of length L displaces it by about L * theta / 4, and below this deviation (a tenth
## of a close-up pixel) a sign flip is numerical noise on a straight blade, not a wave.
BROW_VISIBLE_MM = 0.02
BROW_KINK_DEG = 12.0
BROW_MIN_EDGE_MM = 0.05
BROW_MIRROR_MM = 0.1


def _turns(values, floor):
    d = [b - a for a, b in zip(values, values[1:])]
    signs = [1 if x > floor else -1 if x < -floor else 0 for x in d]
    signs = [s for s in signs if s]
    return sum(1 for a, b in zip(signs, signs[1:]) if a != b)


def brow_contour(brow):
    """The evaluated brow's front-plane edges (its column rows: row 1 the lower edge, row
    rows-2 the upper), their direction reversals and kinks, the thickness profile's turns, and
    the shortest edge. Rows come from the builder (`riposte_brow_rows`)."""
    rows = int(brow.get("riposte_brow_rows", 7))
    deps = bpy.context.evaluated_depsgraph_get()
    ev = brow.evaluated_get(deps)
    me = ev.to_mesh()
    pts = [brow.matrix_world @ v.co for v in me.vertices]
    short = min(((pts[e.vertices[0]] - pts[e.vertices[1]]).length for e in me.edges), default=0.0)
    ev.to_mesh_clear()
    cols = len(pts) // rows
    lower = [pts[c * rows + 1] for c in range(cols)]
    upper = [pts[c * rows + rows - 2] for c in range(cols)]
    out = {"min_edge_mm": round(short * 1000, 3)}
    for name, edge in (("lower", lower), ("upper", upper)):
        slopes = [math.degrees(math.atan2(b.z - a.z, abs(b.x - a.x) or 1e-9)) for a, b in zip(edge, edge[1:])]
        bends = [b - a for a, b in zip(slopes, slopes[1:])]
        worst = max(range(len(bends)), key=lambda i: abs(bends[i])) if bends else 0
        segment_mm = 1000 * sum((b - a).length for a, b in zip(edge, edge[1:])) / max(1, len(edge) - 1)
        floor = math.degrees(4.0 * BROW_VISIBLE_MM / max(segment_mm, 1e-6))
        out[name] = {"reversals": _turns(slopes, floor), "worst_kink_deg": round(abs(bends[worst]) if bends else 0.0, 2),
                     "bend_floor_deg": round(floor, 2),
                     "worst_kink_at": round((worst + 1) / max(1, cols - 1), 3),
                     "bends_deg": [round(b, 1) for b in bends]}
    widths = [(u.z - l.z) * 1000 for l, u in zip(lower, upper)]
    out["width_mm"] = [round(w, 2) for w in widths]
    out["width_turns"] = _turns(widths, 0.05)
    out["_edges"] = (lower, upper)
    return out


def brow_problems(label, side, c):
    out = []
    for name in ("lower", "upper"):
        if c[name]["reversals"] > BROW_EDGE_REVERSALS:
            out.append("brow %s %s edge reverses %d times (squiggle)" % (side, name, c[name]["reversals"]))
        if c[name]["worst_kink_deg"] > BROW_KINK_DEG:
            out.append("brow %s %s edge kinks %.1f deg" % (side, name, c[name]["worst_kink_deg"]))
    if c["width_turns"] > BROW_WIDTH_TURNS:
        out.append("brow %s thickness turns %d times (lumps/pinches)" % (side, c["width_turns"]))
    if c["min_edge_mm"] < BROW_MIN_EDGE_MM:
        out.append("brow %s has a %.3f mm edge (degenerate)" % (side, c["min_edge_mm"]))
    return out


def mirror_mm(left, right):
    """The largest distance between the left brow's edges and the right brow's mirrored."""
    worst = 0.0
    for el, er in zip(left, right):
        for a, b in zip(el, er):
            worst = max(worst, (a - Vector((-b.x, b.y, b.z))).length)
    return worst * 1000


def pose(features, state):
    for obj, side in features:
        weights = state[side]
        for block in obj.data.shape_keys.key_blocks[1:]:
            block.slider_max = 2.0
            block.value = weights.get(block.name, 0.0)


def push_behind(eye, head_tree):
    """The negative test: the left eye's central vertices pushed NEGATIVE_PUSH_M behind the
    skin in every key (in memory only)."""
    me = eye.data
    keys = me.shape_keys.key_blocks if me.shape_keys else [None]
    centre = sum((v.co for v in me.vertices), Vector()) / len(me.vertices)
    near = sorted(range(len(me.vertices)), key=lambda i: (me.vertices[i].co - centre).length)[:max(4, len(me.vertices) // 12)]
    inv = eye.matrix_world.inverted().to_3x3()
    for i in near:
        world = eye.matrix_world @ me.vertices[i].co
        _loc, normal, _j, _d = head_tree.find_nearest(world)
        step = inv @ (-normal * NEGATIVE_PUSH_M)
        me.vertices[i].co += step
        for kb in keys:
            if kb is not None:
                kb.data[i].co += step
    return len(near)


def main():
    import numpy as np
    args = _arguments()
    os.makedirs(args.out, exist_ok=True)
    with open(args.states, encoding="utf-8") as h:
        states = json.load(h)
    if args.only:
        states = {k: v for k, v in states.items() if k in args.only.split(",")}
    bpy.ops.wm.open_mainfile(filepath=os.path.abspath(args.blend))
    scene = bpy.context.scene
    camera = exposure_check._setup(scene)
    camera.data.ortho_scale = ORTHO_M
    scene.render.resolution_x = scene.render.resolution_y = RES
    root = bpy.data.objects["%s.Root" % args.prefix]
    for other in bpy.data.objects:
        if other.name.endswith(".Root") and other is not root:
            other.hide_render = True
            for child in other.children_recursive:
                child.hide_render = True
    parts = [o for o in root.children_recursive if o.type == "MESH"]
    kinds = {o.name: component(o, args.prefix) for o in parts}
    for o in parts:
        if o.name.split(".", 1)[-1].startswith("DeadEye"):
            o.hide_render = True
            continue
        exposure_check._paint(o, OWNERS[kinds[o.name]])
    features = [(o, o.name.rsplit(".", 1)[-1]) for o in parts
                if kinds[o.name] in ("eye", "brow") and o.data.shape_keys]
    eyes = [o for o in parts if kinds[o.name] == "eye"]
    head = bpy.data.objects["%s.Head" % args.prefix]
    root.location = root.rotation_euler = (0, 0, 0)
    bpy.context.view_layer.update()
    zs = [(head.matrix_world @ v.co).z for v in head.data.vertices]
    look_z = 0.5 * (min(zs) + max(zs))
    camera.location, camera.rotation_euler = (0.0, -2.0, look_z), (math.radians(90), 0, 0)
    pushed = 0
    if args.negative:
        tree, bm = _world_tree(head)
        pushed = push_behind(next(o for o in eyes if o.name.endswith(".L")), tree)
        bm.free()
    shown = {o.name: o.hide_render for o in parts}

    def only(kinds_on):
        for o in parts:
            o.hide_render = shown[o.name] or kinds[o.name] not in kinds_on

    results, failures = [], []
    for label, state in states.items():
        pose(features, state)
        root.rotation_euler = (0, 0, 0)
        bpy.context.view_layer.update()
        tree, bm = _world_tree(head)
        gaps = {o.name.rsplit(".", 1)[-1]: clearance(o, tree) for o in eyes}
        bm.free()
        geometry = {side: {"min_mm": round(min(g) * 1000, 3), "max_mm": round(max(g) * 1000, 3),
                           "behind": sum(1 for d in g if d < 0.0)} for side, g in gaps.items()}
        for o in eyes:
            geometry[o.name.rsplit(".", 1)[-1]]["cant_deg"] = round(cant_deg(o), 2)
        brows = {o.name.rsplit(".", 1)[-1]: brow_contour(o) for o in parts if kinds[o.name] == "brow"}
        brow_report = {side: {k: v for k, v in c.items() if k != "_edges"} for side, c in brows.items()}
        brow_issues = [p for side, c in brows.items() for p in brow_problems(label, side, c)]
        if state.get("L") == state.get("R") and set(brows) == {"L", "R"}:
            brow_report["mirror_mm"] = round(mirror_mm(brows["L"]["_edges"], brows["R"]["_edges"]), 3)
            if brow_report["mirror_mm"] > BROW_MIRROR_MM:
                brow_issues.append("neutral brows are not mirror images (%.3f mm)" % brow_report["mirror_mm"])
        for view in args.views.split(","):
            root.rotation_euler = (0, 0, math.radians(VIEWS[view]))
            stem = os.path.join(args.out, "%s_%s_%s" % (args.prefix, label.replace("+", "_"), view))
            only({"eye"})
            aperture = _owner(exposure_check._render(scene, stem + "_eye.png")) == "eye"
            if args.passes:
                for tag, on in (("eye_head", {"eye", "head"}), ("eye_brow", {"eye", "brow"})):
                    only(on)
                    exposure_check._render(scene, "%s_%s.png" % (stem, tag))
            only({"eye", "head", "brow", "other"})
            seen = _owner(exposure_check._render(scene, stem + "_full.png"))
            row = {"state": label, "view": view, "aperture_px": int(aperture.sum()),
                   "eye_holes_px": int(_holes(aperture).sum()), "geometry": geometry, "occluded_by": {}}
            for owner in ("head", "brow", "other"):
                blobs = exposure_check._blobs(aperture & (seen == owner))
                if blobs:
                    row["occluded_by"][owner] = {"px": int(sum(blobs)), "blobs": len(blobs), "largest": blobs[0]}
            problems = []
            ## A HeadV2 blob touching the aperture's edge at an angled view is the socket rim
            ## (the recess hiding the eye's edge, physical); an island inside the aperture, or
            ## any HeadV2 pixel in the front view, is skin breaking into the glow.
            h, w = aperture.shape
            island, rim = [], []
            for members in exposure_check._blobs(aperture & (seen == "head"), pixels=True):
                edge = any(not (0 <= y + dy < h and 0 <= x + dx < w and aperture[y + dy, x + dx])
                           for y, x in members for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                (rim if edge else island).append(len(members))
            row["head_rim_px"], row["head_island_px"] = sum(rim), sum(island)
            fail = [b for b in island + (rim if view == "front" else []) if b >= MIN_BLOB_PX]
            if fail:
                problems.append("HeadV2 breaks into the aperture: %d blob(s), largest %d px" % (len(fail), max(fail)))
            if view == "front":
                row["brows"] = brow_report
                problems += brow_issues
            if row["eye_holes_px"] >= MIN_BLOB_PX:
                problems.append("the eye-alone silhouette has %d hole px" % row["eye_holes_px"])
            if view == "front":
                for side, g in geometry.items():
                    if g["behind"]:
                        problems.append("eye %s: %d samples behind the skin (min %.3f mm)" % (side, g["behind"], g["min_mm"]))
                    if g["max_mm"] > FLOAT_MM:
                        problems.append("eye %s floats %.2f mm off the skin" % (side, g["max_mm"]))
            row["problems"] = problems
            results.append(row)
            failures += ["%s/%s: %s" % (label, view, p) for p in problems]
            print("RIPOSTE_FACE_LAYERS", json.dumps(row))
    verdict = {"prefix": args.prefix, "checked": len(results), "failures": len(failures),
               "negative_test": bool(args.negative), "pushed_vertices": pushed, "pass": not failures}
    with open(os.path.join(args.out, "%s_face_layers.json" % args.prefix), "w", encoding="utf-8") as h:
        json.dump({"verdict": verdict, "results": results, "failures": failures}, h, indent=1)
    for f in failures:
        print("RIPOSTE_FACE_LAYERS_FAIL", f)
    print("RIPOSTE_FACE_LAYERS_VERDICT", json.dumps(verdict))


if __name__ == "__main__":
    main()
