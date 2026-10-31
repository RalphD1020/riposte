"""Author Wolf's face marks into `art-src/blender/characters/wolf/wolf_attire.blend` (collection `Face`).

The attire blend links the male base read-only as the fitting mannequin
(collection `Base (linked, read-only)`); nothing here edits the base. Marks are
placed from the one landmark set in `wolf.assembly.json` (head-relative
fractions), so both skins share an identical face. Each mark is a designed
angular feature, not a box: its authored outline (`outline` in the landmark)
lying on the flat panel under it — a ray from the front finds the panel and the
mark takes that panel's normal — sunk slightly into it, with a bevelled top, so
its depth reads as cut planes. Eyes are narrow almond-pentagons with tapered
corners, brows tapered angular strokes heavier at the inner end, either side of
the raised ridge; the dead-eye X is two tapered bars per eye. All are dark
(`hair` slot).

Run once to create the Face collection; `--replace-face` rebuilds it (the
rest of the attire blend is kept).

    blender --background --factory-startup --python tools/blender/authoring/wolf_face.py [-- --replace-face]
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
BLENDS = os.path.join(ROOT, "art-src", "blender")
ATTIRE = os.path.join(BLENDS, "characters", "wolf", "wolf_attire.blend")
MANIFEST = os.path.join(BLENDS, "characters", "wolf", "wolf.assembly.json")
BASE = os.path.join(BLENDS, "characters", "male_base.blend")
BASE_COLLECTION = "Base (linked, read-only)"
FACE = "Face"
HEAD = "Head"
SIDES = (("L", 1.0), ("R", -1.0))
RAY_FROM_Y = -0.6
## Where the bevel starts, as a share of the mark's height off the panel.
BEVEL_SHOULDER = 0.35


def _open_attire():
    if os.path.exists(ATTIRE):
        bpy.ops.wm.open_mainfile(filepath=ATTIRE)
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)
    os.makedirs(os.path.dirname(ATTIRE), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=ATTIRE)
    collection = bpy.data.collections.new(BASE_COLLECTION)
    bpy.context.scene.collection.children.link(collection)
    with bpy.data.libraries.load(BASE, link=True, relative=True) as (source, target):
        target.objects = [n for n in source.objects if n in ("Body", "Armature")]
    for obj in target.objects:
        collection.objects.link(obj)
        obj.hide_select = True


def _head(body):
    """The head island's vertices (world space) and its faces as a BVH."""
    head = body.vertex_groups[HEAD].index
    world = body.matrix_world
    members = set()
    for v in body.data.vertices:
        if any(g.group == head and g.weight >= 0.99 for g in v.groups) and v.co.z > 1.5:
            members.add(v.index)
    points = [world @ body.data.vertices[i].co for i in members]
    polygons = [list(p.vertices) for p in body.data.polygons if all(i in members for i in p.vertices)]
    index = {i: n for n, i in enumerate(sorted(members))}
    ordered = [world @ body.data.vertices[i].co for i in sorted(members)]
    tree = BVHTree.FromPolygons(ordered, [[index[i] for i in p] for p in polygons])
    low = min(p.z for p in points)
    high = max(p.z for p in points)
    half_width = max(abs(p.x) for p in points)
    return tree, low, high - low, half_width


def _frame(normal, sign, tilt):
    """Box axes on a panel: u across (outward for that side), v up, n out of the panel."""
    n = normal.normalized()
    u = Vector((0.0, 0.0, 1.0)).cross(n).normalized()
    if u.x * sign < 0.0:
        u = -u
    v = n.cross(u).normalized()
    if v.z < 0.0:
        v = -v
    ## A positive tilt raises the outer end on both sides (mirror-symmetric).
    turn = Matrix.Rotation(math.radians(tilt), 3, n)
    if tilt and ((turn @ u).z > 0.0) != (tilt > 0.0):
        turn = Matrix.Rotation(-math.radians(tilt), 3, n)
    return turn @ u, turn @ v, n


def _mark(name, hit, axes, size, mark):
    """A designed feature, not a box: the mark's authored outline (u outward from the
    centre line, v up, both in -0.5..0.5 of its width and height) sunk into the panel,
    standing `proud_m` off it, with a bevelled top inset to `inset` of the outline so
    its depth reads as cut planes."""
    u, v, n = axes
    w, h, d = size
    outline = mark["outline"]
    cx = sum(p[0] for p in outline) / len(outline)
    cy = sum(p[1] for p in outline) / len(outline)
    proud = mark["proud_m"]
    inset = mark.get("inset", 1.0)

    def ring(scale, height):
        return [bm.verts.new(hit + u * ((cx + (x - cx) * scale) * w) + v * ((cy + (y - cy) * scale) * h) + n * height)
                for x, y in outline]

    bm = bmesh.new()
    base = ring(1.0, proud - d)
    shoulder = ring(1.0, proud * BEVEL_SHOULDER)
    top = ring(inset, proud)
    bm.faces.new(list(reversed(base)))
    count = len(outline)
    for low, high in ((base, shoulder), (shoulder, top)):
        for k in range(count):
            bm.faces.new([low[k], low[(k + 1) % count], high[(k + 1) % count], high[k]])
    bm.faces.new(top)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    obj["riposte_slot"] = "hair"
    obj["riposte_bone"] = HEAD
    return obj


def head_of(obj):
    """Any head object (the approved `HeadV2`, a resolved profile): its faces as a BVH, in
    world space. The chart frame (low, height, half-width) is passed separately, so marks
    keep the character's identity placement while their depth comes from this surface."""
    points = [obj.matrix_world @ v.co for v in obj.data.vertices]
    return BVHTree.FromPolygons(points, [list(p.vertices) for p in obj.data.polygons])


def place_marks(collection, tree, low, height, half_width, marks, eye_spacing_u=0.0, brow_tilt_deg=0.0, offset_x=0.0):
    """Eyes, brows and the dead-eye X on the head surface `tree`, from the identity's marks
    (chart fractions of `low`/`height`/`half_width`). `eye_spacing_u` moves eyes, brows and
    the X apart (chart units); `brow_tilt_deg` adds to the brows' tilt (identity only)."""
    report = []

    def shifted(mark):
        return dict(mark, x=mark["x"] + eye_spacing_u)

    for kind in ("Eye", "Brow"):
        mark = shifted(marks[kind])
        for side, sign in SIDES:
            hit, normal = _place(tree, low, height, half_width, mark, sign, offset_x)
            tilt = mark.get("tilt_by_side", {}).get(side, mark["tilt_deg"]) + (brow_tilt_deg if kind == "Brow" else 0.0)
            axes = _frame(normal, sign, tilt)
            size = (mark["width"] * half_width, mark["height"] * height, mark["depth_m"])
            obj = _mark("%s.%s" % (kind, side), hit, axes, size, mark)
            collection.objects.link(obj)
            report.append((obj.name, hit, axes[2]))
    dead = shifted(marks["DeadEye"])
    for side, sign in SIDES:
        hit, normal = _place(tree, low, height, half_width, dead, sign, offset_x)
        for bar, turn in (("A", 1.0), ("B", -1.0)):
            axes = _frame(normal, sign, dead["tilt_deg"] * turn)
            size = (dead["width"] * half_width, dead["height"] * height, dead["depth_m"])
            obj = _mark("DeadEye.%s.%s" % (side, bar), hit, axes, size, dead)
            collection.objects.link(obj)
            report.append((obj.name, hit, axes[2]))
    return report


def _place(tree, low, height, half_width, mark, sign, offset_x=0.0):
    target = Vector((offset_x + sign * mark["x"] * half_width, RAY_FROM_Y, low + mark["z"] * height))
    hit, normal, _index, _distance = tree.ray_cast(target, Vector((0.0, 1.0, 0.0)))
    if hit is None:
        raise SystemExit("RIPOSTE_FACE: no panel under %s" % (target,))
    if normal.y > 0.0:
        normal = -normal
    return hit, normal


def main():
    replace = "--replace-face" in sys.argv
    _open_attire()
    if FACE in bpy.data.collections:
        if not replace:
            raise SystemExit("RIPOSTE_FACE_EXISTS: %s already has a Face collection; pass --replace-face" % ATTIRE)
        old = bpy.data.collections[FACE]
        for obj in list(old.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.collections.remove(old)
    with open(MANIFEST, encoding="utf-8") as handle:
        marks = json.load(handle)["identity"]["face"]["marks"]
    body = bpy.data.objects["Body"]
    tree, low, height, half_width = _head(body)
    face = bpy.data.collections.new(FACE)
    bpy.context.scene.collection.children.link(face)
    ## A per-side tilt (tilt_by_side) gives the face its slight, deliberate asymmetry.
    report = place_marks(face, tree, low, height, half_width, marks)
    bpy.ops.wm.save_as_mainfile(filepath=ATTIRE, relative_remap=True)
    print("RIPOSTE_FACE head z %.4f..%.4f half-width %.4f" % (low, low + height, half_width))
    for name, centre, normal in report:
        print("RIPOSTE_FACE_MARK %s at %s normal %s" % (name, [round(c, 4) for c in centre], [round(c, 3) for c in normal]))


if __name__ == "__main__":
    main()
