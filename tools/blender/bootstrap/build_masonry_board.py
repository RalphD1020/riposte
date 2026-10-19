"""Masonry test board. Not part of the match.

Three lanes show joint depths 2 cm, 4 cm, and 8 cm. Bevels are none, a small
arriss, and a larger one. Wear darkens the coping edge and one pier corner.
A water slab and a bronze plaque sit with the stone roles. The combat-floor
swatch is `stone_floor` at the theme hex, unchanged.

Run: blender --background --factory-startup --python tools/blender/bootstrap/build_masonry_board.py
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import bpy  # noqa: E402

import masonry  # noqa: E402
import riposte_blocks as rb  # noqa: E402
import stone_palette as stone  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))


def lane(parent, name, x, gap, bevel, worn):
    travertine = masonry.role("stone_pillar")
    limestone = masonry.role("stone_edge")
    terracotta = masonry.role("stone_terracotta")
    recess = masonry.role("stone_cliff")
    block = (0.46, 0.36, 0.24)
    courses = 4
    across = 3
    index = 0
    for course in range(courses):
        material = terracotta if course == 2 else travertine if course % 2 == 0 else limestone
        shift = 0.0 if course % 2 == 0 else (block[1] + gap) * 0.5
        for column in range(across):
            y = (column - 1) * (block[1] + gap) + shift
            z = course * (block[2] + gap)
            edge = course == courses - 1 or (course == 0 and column == 0)
            masonry.block(
                "%s_%d" % (name, index),
                block,
                (x, y, z + block[2] * 0.5),
                material,
                parent,
                masonry.tint_for(index, worn and edge),
                bevel,
            )
            index += 1
    coping_z = courses * (block[2] + gap) + 0.08
    masonry.block(
        name + "_coping",
        (0.52, across * (block[1] + gap), 0.16),
        (x, 0.0, coping_z),
        limestone,
        parent,
        masonry.tint_for(1, True),
        max(bevel, 0.01),
    )
    masonry.block(
        name + "_recess",
        (0.28, across * (block[1] + gap) * 0.8, courses * (block[2] + gap) * 0.7),
        (x + 0.42, 0.0, 0.55),
        recess,
        parent,
        (0.85, 0.85, 0.85),
        0.0,
    )


def build():
    rb.reset_scene()
    root = rb.empty("MasonryBoard", (0.0, 0.0, 0.0), size=0.4)
    lane(root, "Tight", -1.6, 0.02, 0.0, False)
    lane(root, "Mid", 0.0, 0.04, 0.012, True)
    lane(root, "Open", 1.6, 0.08, 0.02, True)
    floor = rb.material("stone_floor", stone.srgb("8a7f6c"), roughness=0.95)
    masonry.paint(rb.box("FloorSwatch", (0.7, 0.7, 0.08), (0.0, -1.35, 0.04), floor, parent=root), (1, 1, 1))
    masonry.block("Plaque", (0.08, 0.28, 0.18), (0.0, 0.0, 0.7), masonry.role("gold_trim"), root, (1, 1, 1), 0.004)
    masonry.paint(
        rb.box("Water", (3.4, 0.8, 0.06), (0.0, 1.55, 0.03), masonry.role("basin_water"), parent=root),
        (1, 1, 1),
    )
    return root


def main():
    build()
    out = os.path.join(ROOT, "art-src", "blender", "arenas", "masonry_board.blend")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=out, compress=True)
    print("RIPOSTE_BOARD", out, "tris", rb.triangle_count([o for o in bpy.data.objects if o.type == "MESH"]))


if __name__ == "__main__":
    main()
