"""Twelve copies of the masonry bay around one basin.

Inner and outer rings share arena_section.json. The fighting floor is not
in this file. Arch crowns stay under the floor soffit and the first tread.

Run: blender --background --factory-startup --python tools/blender/bootstrap/build_arena_bowl.py

See also: docs/concepts/presentation.md
"""

import math
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
    root = rb.empty("ArenaBowl", (0.0, 0.0, 0.0), size=0.5)
    count = layout["bay_count"]
    for i in range(count):
        bay = rb.empty("Bay%02d" % i, (0.0, 0.0, 0.0), parent=root, size=0.2)
        heading = -(layout["angular_zero"] + math.tau * i / count)

        def _near(angle, target):
            return abs((angle - target + math.pi) % math.tau - math.pi) < 0.05

        cut_gate = _near(heading, math.pi * 0.5) or _near(heading, -math.pi * 0.5)
        am.build_bay(bay, layout, cut_gate=cut_gate)
        am.assert_inside_wedge([child for child in bay.children if child.type == "MESH"], layout)
        bay.rotation_euler.z = heading
        am.join_children(bay)
        print("RIPOSTE_BAY_JOINED", i, flush=True)
    if layout.get("kind") == "pit":
        am.build_gates(root, layout)
    else:
        am.build_water(root, layout)
    return root


def main():
    root = build()
    bpy.context.view_layer.update()
    problems = validate_assets.validate_bowl()
    if problems:
        raise SystemExit("arena bowl: " + "; ".join(problems))
    meshes = [child for child in root.children_recursive if child.type == "MESH"]
    out = os.path.join(ROOT, "art-src", "blender", "arenas", "arena_bowl.blend")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=out, compress=True)
    print("RIPOSTE_BOWL", out, "tris", rb.triangle_count(meshes))


if __name__ == "__main__":
    main()
