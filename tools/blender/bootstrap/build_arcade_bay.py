"""One radial slice: inner arch, moat, outer arch, four treads.

The fighting floor is a separate asset. This file does not replace the bowl.
Water sits on the root so a preview can turn the bay without turning the basin.

Run: blender --background --factory-startup --python tools/blender/bootstrap/build_arcade_bay.py

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
    root = rb.empty("ArcadeBay", (0.0, 0.0, 0.0), size=0.5)
    bay = rb.empty("Bay", (0.0, 0.0, 0.0), parent=root, size=0.2)
    am.build_bay(bay, layout)
    am.assert_inside_wedge([child for child in bay.children if child.type == "MESH"], layout)
    am.build_water(root, layout)
    return root


def main():
    root = build()
    bpy.context.view_layer.update()
    problems = validate_assets.validate_bowl()
    if problems:
        raise SystemExit("arcade bay: " + "; ".join(problems))
    out = os.path.join(ROOT, "art-src", "blender", "arenas", "arcade_bay.blend")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    meshes = [child for child in root.children_recursive if child.type == "MESH"]
    bpy.ops.wm.save_as_mainfile(filepath=out, compress=True)
    print("RIPOSTE_BAY", out, "tris", rb.triangle_count(meshes))


if __name__ == "__main__":
    main()
