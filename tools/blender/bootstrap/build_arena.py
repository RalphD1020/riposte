"""Bootstrap the standard arena (art-src/blender/arenas/standard_arena.blend).

The combat footprint stays quiet; richness lives on the perimeter. The
platform top ends exactly at the physical edge (`platform_radius`) — the
visible cliff IS the boundary, so the ornamental relief sits on the cliff
face below the floor, never on top of it. The warning ring and the two
home-end marks are drawn by the game from the rules, not authored here.

Floor colours are the theme's world tokens converted from sRGB to linear, so
the imported albedo is exactly the colour the contrast tests prove.

Run: blender --background --factory-startup --python tools/blender/bootstrap/build_arena.py
"""

import math
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import bpy  # noqa: E402

import riposte_blocks as rb  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
PLATFORM_RADIUS = 8.27
CLIFF_DEPTH = 1.6
SEGMENTS = 48


def srgb(hex_code):
    def channel(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    value = int(hex_code, 16)
    return tuple(channel(((value >> shift) & 0xFF) / 255.0) for shift in (16, 8, 0))


def build():
    rb.reset_scene()
    rng = random.Random(7)
    floor = rb.material("stone_floor", srgb("8a7f6c"), roughness=0.95)
    edge = rb.material("stone_edge", srgb("5e5648"), roughness=0.95)
    cliff = rb.material("stone_cliff", srgb("3a352d"), roughness=1.0)
    pillar = rb.material("stone_pillar", srgb("6b6252"), roughness=0.9)
    iron = rb.material("metal", srgb("2a2522"), roughness=0.5, metallic=0.8)
    ember = rb.material("ember", srgb("ff9a3c"), roughness=0.6, emission=srgb("ff9a3c"), emission_strength=4.0)
    cloth = rb.material("banner_cloth", srgb("5a1f1c"), roughness=0.95)
    gold = rb.material("gold_trim", srgb("c4a050"), roughness=0.45, metallic=0.7)
    root = rb.empty("ArenaRoot", (0.0, 0.0, 0.0), size=0.5)
    rb.prism("PlatformTop", SEGMENTS, PLATFORM_RADIUS, -0.004, 0.0, floor, parent=root)
    rb.prism("PlatformCliff", SEGMENTS, PLATFORM_RADIUS, -CLIFF_DEPTH, -0.004, cliff, parent=root, top_scale=1.0)
    rb.prism("PlatformUnderside", 16, PLATFORM_RADIUS * 0.94, -CLIFF_DEPTH - 0.9, -CLIFF_DEPTH, cliff, parent=root, top_scale=1.06)
    # Carved duelling motif: an eight-point compass of low wedges, flush with
    # the floor and only a shade darker, so it never competes with the fight.
    for i in range(8):
        angle = math.tau * i / 8
        length = 0.9 if i % 2 == 0 else 0.55
        rb.box("Motif%d" % i, (0.05, length, 0.002), (math.sin(angle) * length * 0.5, -math.cos(angle) * length * 0.5, 0.001), edge, parent=root, rotation=(0.0, 0.0, -angle))
    rb.prism("MotifHub", 8, 0.14, 0.0, 0.002, edge, parent=root, spin=math.pi / 8)
    # Ornamental relief on the cliff face: blocks just below the floor line.
    for i in range(SEGMENTS):
        angle = math.tau * (i + 0.5) / SEGMENTS
        r = PLATFORM_RADIUS + 0.03
        size = (0.42, 0.08, 0.22 if i % 3 else 0.34)
        rb.box("Relief%d" % i, size, (math.cos(angle) * r, math.sin(angle) * r, -0.2 - size[2] * 0.5), edge, parent=root, rotation=(0.0, 0.0, angle + math.pi / 2))
    # Perimeter: pillars (some broken) carrying braziers, banners between.
    count = 8
    for i in range(count):
        angle = math.tau * (i + 0.5) / count
        r = PLATFORM_RADIUS + 1.6
        x, y = math.cos(angle) * r, math.sin(angle) * r
        broken = i % 3 == 1
        height = 1.4 if broken else 3.2
        rb.box("Pillar%d" % i, (0.7, 0.7, height + 2.0), (x, y, height * 0.5 - 1.0), pillar, parent=root, bevel=0.03, rotation=(0.0, 0.0, angle))
        rb.box("PillarCap%d" % i, (0.86, 0.86, 0.16), (x, y, height + 0.08), pillar, parent=root, bevel=0.02, rotation=(0.0, 0.0, angle))
        if not broken:
            rb.prism("Brazier%d" % i, 6, 0.32, height + 0.16, height + 0.42, iron, parent=root, center=(x, y), top_scale=1.25)
            rb.prism("BrazierEmber%d" % i, 6, 0.3, height + 0.42, height + 0.6, ember, parent=root, center=(x, y), top_scale=0.55)
        else:
            for k in range(3):
                rb.box("Rubble%d_%d" % (i, k), (0.3, 0.26, 0.2), (x + rng.uniform(-0.6, 0.6), y + rng.uniform(-0.6, 0.6), -0.9 + rng.uniform(-0.2, 0.2)), pillar, parent=root, rotation=(rng.uniform(0, 1), rng.uniform(0, 1), rng.uniform(0, 3)))
        # Banners hang between pillars, angled to face the arena.
        b_angle = math.tau * (i + 1.0) / count
        br = PLATFORM_RADIUS + 1.9
        bx, by = math.cos(b_angle) * br, math.sin(b_angle) * br
        rb.box("BannerPole%d" % i, (0.08, 0.08, 3.6), (bx, by, 0.8), iron, parent=root)
        rb.box("Banner%d" % i, (0.7, 0.04, 1.4), (bx, by, 1.6), cloth, parent=root, rotation=(0.0, 0.0, b_angle + math.pi / 2))
        rb.box("BannerTrim%d" % i, (0.72, 0.05, 0.08), (bx, by, 2.25), gold, parent=root, rotation=(0.0, 0.0, b_angle + math.pi / 2))
    # Floating stone fragments drifting in the void below the platform rim.
    for k in range(14):
        angle = rng.uniform(0, math.tau)
        r = PLATFORM_RADIUS + rng.uniform(0.6, 3.2)
        s = rng.uniform(0.25, 0.7)
        rb.box("Fragment%d" % k, (s, s * 0.8, s * 0.6), (math.cos(angle) * r, math.sin(angle) * r, rng.uniform(-3.5, -1.2)), cliff, parent=root, rotation=(rng.uniform(0, 1), rng.uniform(0, 1), rng.uniform(0, 3)))
    rb.empty("SpawnSouth", (0.0, -2.5, 0.0), parent=root)
    rb.empty("SpawnNorth", (0.0, 2.5, 0.0), parent=root)


def main():
    build()
    out = os.path.join(ROOT, "art-src", "blender", "arenas", "standard_arena.blend")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=out, compress=True)
    print("RIPOSTE_BUILT", out)


if __name__ == "__main__":
    main()
