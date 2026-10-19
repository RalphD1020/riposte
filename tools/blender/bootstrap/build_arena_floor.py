"""The central fighting floor: east-west bond, flush with the fighting plane.

This does not replace standard_arena.blend. The arcades are the bowl.

Run: blender --background --factory-startup --python tools/blender/bootstrap/build_arena_floor.py

See also: docs/concepts/presentation.md
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import bpy  # noqa: E402

import arena_layout  # noqa: E402
import arena_masonry as am  # noqa: E402
import riposte_blocks as rb  # noqa: E402
import validate_assets  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))


def build():
    layout = arena_layout.load()
    rb.reset_scene()
    root = rb.empty("ArenaFloor", (0.0, 0.0, 0.0), size=0.5)
    am.build_floor(root, layout)
    am.join_children(root)
    return root


def main():
    root = build()
    bpy.context.view_layer.update()
    problems = validate_assets.validate_floor()
    if problems:
        raise SystemExit("arena floor: " + "; ".join(problems))
    meshes = [child for child in root.children_recursive if child.type == "MESH"]
    out = os.path.join(ROOT, "art-src", "blender", "arenas", "arena_floor.blend")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=out, compress=True)
    print("RIPOSTE_FLOOR", out, "tris", rb.triangle_count(meshes))


if __name__ == "__main__":
    main()
