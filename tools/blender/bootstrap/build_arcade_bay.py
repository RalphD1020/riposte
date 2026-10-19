"""One masonry arcade bay outside the combat disc.

Blocks stay separate in this blend so a course can be edited. Export joins
them by material. The combat disc is not in this file. Flat materials from
the first block-out are replaced by the shared stone roles, running-bond
courses, radial voussoirs, and per-block vertex color.

Run: blender --background --factory-startup --python tools/blender/bootstrap/build_arcade_bay.py
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import bpy  # noqa: E402

import masonry  # noqa: E402
import riposte_blocks as rb  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
INNER_X = 8.50
PIER_DEPTH = 1.75
PIER_WIDTH = 1.25
OPENING = 2.50
PIER_BASE = -3.00
SPRING = -1.50


def build_into(parent):
    travertine = masonry.role("stone_pillar")
    limestone = masonry.role("stone_edge")
    terracotta = masonry.role("stone_terracotta")
    recess = masonry.role("stone_cliff")
    pier_height = SPRING - PIER_BASE
    pier_y = (OPENING + PIER_WIDTH) * 0.5
    for side, prefix in ((-1.0, "PierL"), (1.0, "PierR")):
        origin_y = side * pier_y - PIER_WIDTH * 0.5
        masonry.courses(
            parent, prefix,
            (INNER_X, origin_y, PIER_BASE),
            (PIER_DEPTH, PIER_WIDTH, pier_height),
            travertine, 0.03, 0.01,
            PIER_BASE + 0.45,
        )
    masonry.voussoirs(
        parent, "Voussoir",
        INNER_X + PIER_DEPTH * 0.45,
        SPRING, OPENING * 0.5, 0.42, PIER_DEPTH * 0.7, 9, travertine,
    )
    deck_z = 0.12
    masonry.courses(
        parent, "Deck",
        (INNER_X, -(OPENING + PIER_WIDTH), deck_z),
        (2.1, (OPENING + PIER_WIDTH) * 2.0, 0.5),
        limestone, 0.025, 0.012, None,
    )
    masonry.block(
        "Coping", (0.55, OPENING + PIER_WIDTH * 2.0 + 0.3, 0.18),
        (INNER_X + 0.28, 0.0, 0.62),
        limestone, parent, masonry.tint_for(2, True), 0.016,
    )
    masonry.courses(
        parent, "Step",
        (INNER_X + 1.05, -(OPENING * 0.5 + PIER_WIDTH), 0.62),
        (1.0, OPENING + PIER_WIDTH * 2.0, 0.5),
        terracotta, 0.03, 0.01, None,
    )
    masonry.courses(
        parent, "Rear",
        (INNER_X + PIER_DEPTH + 0.2, -OPENING * 0.45, SPRING + 0.15),
        (0.5, OPENING * 0.9, 1.15),
        recess, 0.02, 0.0, None,
    )
    masonry.block(
        "Cross", (0.7, 0.22, 0.9),
        (INNER_X + PIER_DEPTH * 0.85, OPENING * 0.42, SPRING + 0.35),
        recess, parent, (0.9, 0.9, 0.9), 0.0,
    )
    masonry.paint(
        rb.box("Water", (3.4, 6.0, 0.22), (INNER_X + 1.7, 0.0, PIER_BASE - 0.12), masonry.role("basin_water"), parent=parent),
        (1.0, 1.0, 1.0),
    )
    masonry.paint(
        rb.box("Glint", (0.45, 0.7, 0.04), (INNER_X + 1.4, -0.4, PIER_BASE + 0.02), masonry.role("basin_glint"), parent=parent),
        (1.0, 1.0, 1.0),
    )
    return parent


def build():
    rb.reset_scene()
    root = rb.empty("ArcadeBay", (0.0, 0.0, 0.0), size=0.5)
    return build_into(root)


def main():
    root = build()
    bpy.context.view_layer.update()
    meshes = [child for child in root.children_recursive if child.type == "MESH"]
    lo, _hi = rb.world_bounds(meshes)
    if lo.x <= masonry.PLATFORM_RADIUS + 0.1:
        raise SystemExit("arcade bay crosses the combat disc (min x %.3f)" % lo.x)
    out = os.path.join(ROOT, "art-src", "blender", "arenas", "arcade_bay.blend")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=out, compress=True)
    print("RIPOSTE_BAY", out, "tris", rb.triangle_count(meshes))


if __name__ == "__main__":
    main()
