"""Surface-intersection heuristic (GARMENT-VALIDATION-001, heuristic 1): how far a lower layer
pierces the layer over it, for a declared garment pair in the region where they interact.
Distance alone cannot tell inside from outside, so this casts along each lower vertex's normal
and reports a hit BEHIND the vertex (facing the same way) as a pierce with its depth, separate
from a hit in front (clearance). Evaluated meshes (armature + modifiers applied) so it reads the
posed character, not authoring vertices. Report is per pair: pierced-vertex count, how many are
rim vertices (an opening edge, where some overlap is expected), and the deepest few with
locations — not just the worst value.

    blender -b --factory-startup --python layer_contact.py -- <blend> <upper> <lower> [<upper> <lower> ...]
Prints one `PEN <upper> over <lower>` line per pair."""
import sys

import bpy
from mathutils.bvhtree import BVHTree

REACH_M = 0.06

args = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.open_mainfile(filepath=args[0])
dg = bpy.context.evaluated_depsgraph_get()


def _mesh(name):
    obj = bpy.data.objects[name]
    evaluated = obj.evaluated_get(dg)
    mesh = evaluated.to_mesh()
    world = obj.matrix_world
    rot = world.to_3x3()
    points = [world @ v.co for v in mesh.vertices]
    normals = [(rot @ v.normal).normalized() for v in mesh.vertices]
    polys = [list(p.vertices) for p in mesh.polygons]
    evaluated.to_mesh_clear()
    return points, normals, polys


for upper, lower in zip(args[1::2], args[2::2]):
    up_points, _un, up_polys = _mesh(upper)
    tree = BVHTree.FromPolygons(up_points, up_polys)
    lo_points, lo_normals, lo_polys = _mesh(lower)
    rim_attr = bpy.data.objects[lower].data.attributes.get("riposte_rim")
    rim_vert = set()
    if rim_attr:
        for poly, flag in zip(lo_polys, rim_attr.data):
            if flag.value:
                rim_vert.update(poly)
    pierced = []
    for i, (p, n) in enumerate(zip(lo_points, lo_normals)):
        front = tree.ray_cast(p + n * 1e-4, n, REACH_M)
        back = tree.ray_cast(p - n * 1e-4, -n, REACH_M)
        if back[0] is not None and (front[0] is None or back[3] < front[3]) and back[1].dot(n) > 0.0:
            pierced.append((back[3], p, i in rim_vert))
    pierced.sort(key=lambda x: -x[0])
    print("PEN %s over %s: pierced %d (rim %d), deepest %s" % (
        upper, lower, len(pierced), sum(1 for x in pierced if x[2]),
        [(round(d * 1000, 1), tuple(round(c, 3) for c in p), "rim" if r else "") for d, p, r in pierced[:12]]))
