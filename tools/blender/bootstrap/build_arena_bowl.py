"""Twelve copies of the masonry bay, one continuous basin, joined per bay.

The editable one-bay blend stays `arcade_bay.blend`. This file is what Godot
instances: each bay is a handful of material meshes, not a node per block.
Nothing here enters the combat disc.

Run: blender --background --factory-startup --python tools/blender/bootstrap/build_arena_bowl.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import masonry  # noqa: E402
import riposte_blocks as rb  # noqa: E402
from build_arcade_bay import build_into  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
BAYS = 12


def _join_under(parent):
    bpy.context.view_layer.update()
    groups = {}
    for obj in list(parent.children_recursive):
        if obj.type != "MESH" or not obj.data.materials:
            continue
        groups.setdefault(obj.data.materials[0].name, []).append(obj)
    for name, objs in groups.items():
        if len(objs) < 2:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objs:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.join()
        bpy.context.view_layer.objects.active.name = "%s_%s" % (parent.name, name)


def build():
    rb.reset_scene()
    root = rb.empty("ArenaBowl", (0.0, 0.0, 0.0), size=0.5)
    for i in range(BAYS):
        bay = rb.empty("Bay%02d" % i, (0.0, 0.0, 0.0), parent=root, size=0.2)
        build_into(bay)
        bay.rotation_euler.z = math.tau * i / BAYS
        _join_under(bay)
    return root


def main():
    root = build()
    bpy.context.view_layer.update()
    meshes = [child for child in root.children_recursive if child.type == "MESH"]
    lo, hi = rb.world_bounds(meshes)
    reach = min(abs(lo.x), abs(lo.y), abs(hi.x), abs(hi.y))
    ## Rotated bays still leave the disc. The nearest face is the unrotated bay's inner x.
    nearest = math.inf
    for obj in meshes:
        for corner in obj.bound_box:
            point = obj.matrix_world @ Vector(corner)
            nearest = min(nearest, math.hypot(point.x, point.y))
    if nearest <= masonry.PLATFORM_RADIUS + 0.05:
        raise SystemExit("bowl crosses the combat disc (nearest %.3f)" % nearest)
    out = os.path.join(ROOT, "art-src", "blender", "arenas", "arena_bowl.blend")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=out, compress=True)
    print("RIPOSTE_BOWL", out, "tris", rb.triangle_count(meshes), "nearest", round(nearest, 3))


if __name__ == "__main__":
    main()
