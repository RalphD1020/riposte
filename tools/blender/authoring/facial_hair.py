"""Facial hair fitted to a resolved head (CHARACTER-GROOMING-001): the Blender half of a
`riposte.garment` definition of type `facial_hair`.

A style is designed masses (`design.masses`), each an outline in the head's chart (u: |x|
over the head's half-width, mirrored; v: height fraction from the chart's low point) with a
lower edge, an upper edge (the cheek line), a thickness, a drop below the lower edge (the
silhouette under the jaw and chin) and clumps along that edge. Each mass is a grid of points
in that outline, every point projected onto the resolved head's surface (a ray toward the
face, as the face marks are placed), stood off along the surface's smoothed normal by its
thickness (tapering to the skin at the upper edge, so the mass grows out of the face with no
seam), the lower edge dropped and broken into clumps, then given a closed shell. One mapping
for every head: the outline is anatomy, the head under it is whichever head was resolved.

Measured, never judged: points of a mass inside a preserved window (the mouth), and points
that missed the head.
"""

import math

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

## The shell's thickness behind the outer surface (metres): a closed, solid mass.
SHELL_M = 0.002
## The share of a mass's rows (from the upper edge) over which its thickness rises from the
## skin to full: the cheek line grows out of the face.
TOP_TAPER = 0.35
## The upper edge sits this far inside the skin so it never floats.
TUCK_M = 0.0004
## The share of a mass's width (from its far end) over which it thins to the skin.
END_TAPER = 0.2
## Faces meeting at more than this read as a clump's edge; below it they shade smooth.
CLUMP_EDGE_DEG = 38.0
## The mouth window (chart u, v) facial hair never covers.
MOUTH = ((0.0, 0.20), (0.17, 0.245))


def _polyline(points, x):
    if x <= points[0][0]:
        return points[0][1]
    if x >= points[-1][0]:
        return points[-1][1]
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        if x <= x1:
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
    return points[-1][1]


def _head_tree(head):
    world = head.matrix_world
    return BVHTree.FromPolygons([world @ v.co for v in head.data.vertices], [list(p.vertices) for p in head.data.polygons])


def _surface(tree, x, z, y_front, y_side):
    """The head's surface at chart (x, z): a ray from in front of the face; where the head
    is narrower than x at that height (the jaw under the cranium's width), a ray from beside
    the head toward it at depth `y_side` (the row's last front hit, so the row stays one
    continuous band round the jaw)."""
    hit = tree.ray_cast(Vector((x, y_front, z)), Vector((0.0, 1.0, 0.0)))
    if hit[0] is not None:
        return hit[0], False
    side = 1.0 if x >= 0.0 else -1.0
    hit = tree.ray_cast(Vector((side * (abs(x) + 0.3), y_side, z)), Vector((-side, 0.0, 0.0)))
    return (None, True) if hit[0] is None else (hit[0], True)


def local_half_widths(points, step=0.004):
    """{z bin: the head's half-width there} from its vertices: a mass whose `u_frame` is
    `local` measures u against the head's own width at each height (the jaw, not the
    cranium), so its outline follows each head's jaw."""
    table = {}
    for p in points:
        key = round(p.z / step)
        table[key] = max(table.get(key, 0.0), abs(p.x))
    return step, table


def _half_width_at(widths, z):
    step, table = widths
    key = round(z / step)
    near = [table[k] for k in (key - 1, key, key + 1) if k in table]
    return max(near) if near else None


def build_mass(tree, chart, mass, side, y_front, y_mid, widths=None):
    """One mass on one side: (rows of outer points, rows of skin points, report)."""
    low, height, half_width = chart
    local = mass.get("u_frame") == "local" and widths is not None
    us = [mass["u"][0] + (mass["u"][1] - mass["u"][0]) * i / (mass["columns"] - 1) for i in range(mass["columns"])]
    rows = mass["rows"]
    skin, missed, nearest, in_mouth = [], 0, 0, 0
    for i in range(rows):
        row = []
        y_side = y_mid
        for u in us:
            v_low, v_top = _polyline(mass["lower"], u), _polyline(mass["upper"], u)
            v = v_top + (v_low - v_top) * i / (rows - 1)
            if MOUTH[0][0] <= u < MOUTH[0][1] and MOUTH[1][0] < v < MOUTH[1][1]:
                in_mouth += 1
            z = low + v * height
            width = (_half_width_at(widths, z) or half_width) if local else half_width
            p, beside = _surface(tree, side * u * width, z, y_front, y_side)
            nearest += beside
            if p is not None and not beside:
                y_side = p.y
            ## A point that finds no head is a gap, never an invented point (no spikes).
            missed += p is None
            row.append(p)
        skin.append(row)
    outer = []
    for i in range(rows):
        row = []
        for j, u in enumerate(us):
            if skin[i][j] is None:
                row.append(None)
                continue
            ## The smoothed normal: the grid's own tangents (the head's facets do not print),
            ## a missing neighbour replaced by the point itself.
            here = skin[i][j]
            a, b = skin[max(i - 1, 0)][j] or here, skin[min(i + 1, rows - 1)][j] or here
            c, d = skin[i][max(j - 1, 0)] or here, skin[i][min(j + 1, len(us) - 1)] or here
            normal = (d - c).cross(b - a) * side
            normal = normal.normalized() if normal.length > 1e-9 else Vector((0.0, -1.0, 0.0))
            if normal.y > 0.0:
                normal = -normal
            share = i / (rows - 1)
            rise = min(share / TOP_TAPER, 1.0)
            ## The mass thins to the skin at its far end (u's last END_TAPER), so its edge by
            ## the ear grows out of the face like its upper edge does.
            end = min((mass["u"][1] - u) / max(END_TAPER * (mass["u"][1] - mass["u"][0]), 1e-6), 1.0) if mass["u"][1] < 1.0 else 1.0
            fade = (0.5 - 0.5 * math.cos(math.pi * rise)) * (0.5 - 0.5 * math.cos(math.pi * end))
            thick = _polyline(mass["thickness"], u) * fade - TUCK_M * (1.0 - min(rise, end))
            p = skin[i][j] + normal * thick
            if i == rows - 1:
                clumps = mass.get("clumps", 0)
                depth = mass.get("clump_depth", 0.0)
                wave = 1.0 + depth * math.cos(2.0 * math.pi * clumps * u) if clumps else 1.0
                p = p + Vector((0.0, -0.25, -1.0)).normalized() * _polyline(mass.get("drop", [(0.0, 0.0)]), u) * wave * end
            if u == 0.0:
                p = Vector((0.0, p.y, p.z))
            row.append(p)
        outer.append(row)
    return outer, skin, {"missed": missed, "beside": nearest, "in_mouth": in_mouth}


def build_under(tree, chart, mass, side, head_box):
    """An under-jaw mass on one side: an outline across (u) and back (`d`: a fraction of the
    head's depth from its front) on the underside of the chin and jaw, each point found by a
    ray from below, stood off downward by its thickness (tapering to the skin at its back
    edge, where the beard meets the throat). Returns (rows of outer points, report)."""
    low, height, half_width = chart
    front, depth, bottom = head_box
    us = [mass["u"][0] + (mass["u"][1] - mass["u"][0]) * i / (mass["columns"] - 1) for i in range(mass["columns"])]
    rows, missed = mass["rows"], 0
    ## A ray from below stops at the mass's ceiling (chart v): past the chin it would find
    ## the lower lip or the nose's underside.
    ## The ceiling rises from the front rows to the back (the underside climbs to the throat).
    ceilings = mass.get("v_max", [[0.0, 0.17], [1.0, 0.17]])
    outer = []
    for i in range(rows):
        share = i / (rows - 1)
        ceiling = low + _polyline(ceilings, share) * height
        row = []
        for u in us:
            d = _polyline(mass["front"], u) + (_polyline(mass["back"], u) - _polyline(mass["front"], u)) * share
            origin = Vector((side * u * half_width, front + d * depth, bottom - 0.2))
            hit = tree.ray_cast(origin, Vector((0.0, 0.0, 1.0)), ceiling - origin.z)
            if hit[0] is None:
                missed += 1
                row.append(None)
                continue
            p, normal = hit[0], hit[1]
            if normal.z > 0.0:
                normal = -normal
            fade = 0.5 + 0.5 * math.cos(math.pi * share)
            thick = _polyline(mass["thickness"], u) * fade - TUCK_M * (1.0 - fade)
            point = p + normal * thick
            if u == 0.0:
                point = Vector((0.0, point.y, point.z))
            row.append(point)
        outer.append(row)
    return outer, {"missed": missed}


def build(head, chart, definition, material=None, name="FacialHair"):
    """The facial hair `definition` on `head` (world space, before the character's root
    scale), with the chart (low, height, half_width) the face was fitted with. Returns
    (object, report)."""
    tree = _head_tree(head)
    points = [head.matrix_world @ v.co for v in head.data.vertices]
    ys = [p.y for p in points]
    y_front, y_mid = min(ys) - 0.2, 0.5 * (min(ys) + max(ys))
    head_box = (min(ys), max(ys) - min(ys), min(p.z for p in points))
    widths = local_half_widths(points)
    bm = bmesh.new()
    report = {}
    for mass in definition["design"]["masses"]:
        for side in (1.0, -1.0):
            if mass.get("kind") == "under":
                outer, found = build_under(tree, chart, mass, side, head_box)
            else:
                outer, _skin, found = build_mass(tree, chart, mass, side, y_front, y_mid, widths)
            label = "%s.%s" % (mass["name"], "L" if side > 0 else "R")
            report[label] = found
            verts = [[bm.verts.new(p) if p is not None else None for p in row] for row in outer]
            for i in range(len(verts) - 1):
                for j in range(len(verts[i]) - 1):
                    quad = (verts[i][j], verts[i][j + 1], verts[i + 1][j + 1], verts[i + 1][j])
                    if all(q is not None for q in quad):
                        bm.faces.new(quad if side > 0 else tuple(reversed(quad)))
            loose = [v for row in verts for v in row if v is not None and not v.link_faces]
            if loose:
                bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    solidify = obj.modifiers.new("Shell", "SOLIDIFY")
    solidify.thickness = SHELL_M
    solidify.offset = -1.0
    with bpy.context.temp_override(object=obj, active_object=obj, selected_objects=[obj], selected_editable_objects=[obj]):
        bpy.ops.object.modifier_apply(modifier=solidify.name)
    bpy.context.scene.collection.objects.unlink(obj)
    ## Smooth across a clump, an edge between clumps (angular in design, soft in normals).
    obj.data.shade_smooth()
    obj.data.set_sharp_from_angle(angle=math.radians(CLUMP_EDGE_DEG))
    if material is not None:
        obj.data.materials.append(material)
    report["faces"] = len(obj.data.polygons)
    return obj, report
