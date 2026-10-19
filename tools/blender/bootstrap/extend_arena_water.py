"""Replace the bowl's water sheet without rebuilding the arcades.

The bays stay as they are. Water becomes a disc from the centre to the outer
tread, so both arcades stand in it.

Run: blender --background --factory-startup --python tools/blender/bootstrap/extend_arena_water.py

See also: docs/concepts/presentation.md
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import bpy  # noqa: E402

import arena_layout  # noqa: E402
import arena_masonry as am  # noqa: E402
import validate_assets  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
BLEND = os.path.join(ROOT, "art-src", "blender", "arenas", "arena_bowl.blend")


def _drop_water():
    for obj in list(bpy.data.objects):
        if obj.type != "MESH" or not obj.data.materials:
            continue
        if obj.data.materials[0].name not in ("basin_water", "basin_glint"):
            continue
        mesh = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def main():
    bpy.ops.wm.open_mainfile(filepath=BLEND)
    root = bpy.data.objects.get("ArenaBowl")
    if root is None:
        raise SystemExit("arena bowl has no ArenaBowl root")
    _drop_water()
    layout = arena_layout.load()
    am.build_water(root, layout)
    bpy.context.view_layer.update()
    problems = validate_assets.validate_bowl()
    if problems:
        raise SystemExit("arena bowl: " + "; ".join(problems))
    bpy.ops.wm.save_mainfile()
    print("RIPOSTE_WATER", BLEND)


if __name__ == "__main__":
    main()
