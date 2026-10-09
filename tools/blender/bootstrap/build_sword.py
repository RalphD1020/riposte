"""Bootstrap the bastard sword source (art-src/blender/weapons/bastard_sword.blend).

Dimensions are the physical baseline, held at the baseline grip: the origin
is the swing pivot at the pommel, the guard sits at the duelist's grip radius
(0.25 m), and the 0.97 m blade runs to the tip at 1.22 m. The blade points
down -Y, which the glTF exporter turns into Godot +Z, the direction
`SwordPivot` aims the blade at weapon angle 0.

Markers are semantic, not authoritative: GripDominant / GripOffhand tell the
arms where to hold, TrailStart / TrailEnd / Tip tell effects where the steel
is. None of them tells combat where the sword is.

Run: blender --background --factory-startup --python tools/blender/bootstrap/build_sword.py -- [--variant training]
"""

import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import bpy  # noqa: E402

import riposte_blocks as rb  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
GRIP_RADIUS = 0.25
TIP_RADIUS = 1.22
POMMEL_LENGTH = 0.04
GUARD_SPAN = 0.20
GRIP_DOMINANT = 0.225
GRIP_OFFHAND = 0.15


def build(variant):
    rb.reset_scene()
    training = variant == "training"
    # Clone Drone block language: chunky solids, bright edge bevels over a dark
    # core, restrained emission. Not a laser sword — it still reads as steel.
    steel = rb.material("steel", (0.82, 0.84, 0.88), roughness=0.3, metallic=0.9)
    spine_iron = rb.material("spine_iron", (0.1, 0.1, 0.12), roughness=0.5, metallic=0.85)
    iron = rb.material("metal", (0.16, 0.15, 0.15), roughness=0.55, metallic=0.85, emission=(0.35, 0.22, 0.08), emission_strength=0.08)
    leather = rb.material("leather", (0.2, 0.12, 0.07), roughness=0.62)
    bronze = rb.material("bronze", (0.74, 0.52, 0.22), roughness=0.4, metallic=0.8)
    inlay = rb.material("inlay", (0.78, 0.6, 0.28), roughness=0.4, metallic=0.7, emission=(1.0, 0.74, 0.32), emission_strength=1.6)
    if training:
        steel = rb.material("steel_training", (0.58, 0.56, 0.52), roughness=0.72, metallic=0.35)
        spine_iron = rb.material("spine_iron_training", (0.3, 0.26, 0.2), roughness=0.75)
        leather = rb.material("leather_training", (0.44, 0.32, 0.2), roughness=0.82)
        bronze = rb.material("bronze_training", (0.5, 0.46, 0.38), roughness=0.7, metallic=0.3)
        inlay = steel
    guard_y = GRIP_RADIUS - 0.006
    root = rb.empty("WeaponRoot", (0.0, 0.0, 0.0), size=0.08)

    # Hard-edged on purpose (Clone Drone reads as flat-shaded solids), so no
    # bevels — that also keeps the whole weapon well under the triangle budget.
    # --- Pommel: a chunky faceted pentagonal counterweight with a gold inset -
    rb.prism("Pommel", 5, 0.03, -0.012, POMMEL_LENGTH, iron, parent=root, axis="Y", spin=-math.pi / 2)
    rb.box("PommelInset", (0.016, 0.014, 0.016), (0.0, 0.004, 0.0), bronze if not training else iron, parent=root)

    # --- Grip: a long two-hand grip with raised leather block bands ----------
    rb.prism("Grip", 6, 0.015, POMMEL_LENGTH, guard_y - 0.01, leather, parent=root, axis="Y", spin=math.pi / 6)
    for i in range(3):
        y = POMMEL_LENGTH + 0.04 + i * 0.055
        rb.box("GripBand%d" % i, (0.036, 0.034, 0.018), (0.0, -y, 0.0), leather, parent=root)

    # --- Crossguard: interlocking cuboids, flared quillons, pentagonal caps --
    rb.box("GuardCore", (0.07, 0.05, 0.03), (0.0, -guard_y, 0.0), iron, parent=root)
    for side in (-1.0, 1.0):
        tag = "L" if side > 0 else "R"
        rb.box("Quillon%s" % tag, (GUARD_SPAN * 0.5, 0.03, 0.026), (side * (GUARD_SPAN * 0.25 + 0.02), -guard_y, 0.0), iron, parent=root)
        cap_x = side * (GUARD_SPAN * 0.5 + 0.028)
        # Pentagonal end caps echo Wolf's pentagonal head, point outward.
        rb.prism("QuillonCap%s" % tag, 5, 0.03, cap_x - side * 0.016, cap_x + side * 0.016, bronze, parent=root, center=(0.0, 0.0), axis="X", spin=-math.pi / 2)

    # --- Blade: a broad two-step slab (x wide, y long, z thin), dark spine
    # proud of the lighter steel bevels, a thin emissive inlay, chunky point --
    rb.box("BladeLower", (0.084, 0.44, 0.028), (0.0, -(guard_y + 0.23), 0.0), steel, parent=root)
    rb.box("BladeUpper", (0.06, 0.42, 0.024), (0.0, -(guard_y + 0.66), 0.0), steel, parent=root)
    rb.flat_point("BladePoint", TIP_RADIUS - 0.09, TIP_RADIUS, 0.046, 0.022, steel, parent=root)
    rb.box("BladeSpine", (0.018, 0.9, 0.04), (0.0, -(guard_y + 0.46), 0.0), spine_iron, parent=root)
    rb.box("BladeInlay", (0.007, 0.52, 0.046), (0.0, -(guard_y + 0.32), 0.0), inlay, parent=root)

    rb.empty("GripOffhand", (0.0, -GRIP_OFFHAND, 0.0), parent=root)
    rb.empty("GripDominant", (0.0, -GRIP_DOMINANT, 0.0), parent=root)
    rb.empty("TrailStart", (0.0, -GRIP_RADIUS, 0.0), parent=root)
    rb.empty("TrailEnd", (0.0, -TIP_RADIUS, 0.0), parent=root)
    rb.empty("Tip", (0.0, -TIP_RADIUS, 0.0), parent=root)
    return root


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    variant = argv[argv.index("--variant") + 1] if "--variant" in argv else "base"
    build(variant)
    name = "bastard_sword_training.blend" if variant == "training" else "bastard_sword.blend"
    out = os.path.join(ROOT, "art-src", "blender", "weapons", name)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=out, compress=True)
    print("RIPOSTE_BUILT", out)


if __name__ == "__main__":
    main()
