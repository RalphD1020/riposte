"""Seated and cheer block figures at Wolf's head proportion.

Blender faces the figure along +Y, which the glTF export turns into Godot -Z,
so a node that looks at the arena centre is facing the fight. Wolf faces -Y,
so his face numbers are mirrored in Y and shifted down onto this shorter body.
Skin, cloth, hair, and the face are separate meshes so a MultiMesh can tint
each one. The hair is the same pentagon as the head. The eyes and the brow
bar are Wolf's, on that face.

Run: blender --background --factory-startup --python tools/blender/bootstrap/build_crowd.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import bpy  # noqa: E402

import riposte_blocks as rb  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))

## Wolf's HeadSkin in game/content/characters/wolf.character.json, moved from
## z 1.50 onto this figure's neck. The point faces +Y here and -Y on Wolf.
HEAD_RADIUS = 0.125
HEAD_Z0 = 0.98
HEAD_Z1 = 1.23
HEAD_DEPTH = 0.95
HEAD_SPIN = math.pi * 0.5
HEAD_BEVEL = 0.008
WOLF_HEAD_Z0 = 1.5
## Wolf's Eye and Brow, same file. Y is mirrored because he faces the other way.
EYE_SIZE = (0.035, 0.012, 0.02)
EYE_Z = 1.635 + (HEAD_Z0 - WOLF_HEAD_Z0)
EYE_Y = 0.093
EYE_X = 0.04
BROW_SIZE = (0.12, 0.02, 0.022)
## Wolf's bar sits just inside the point. This one is a few millimetres prouder
## so the bar still reads once the head is a few metres from the match camera.
BROW_AT = (0.0, 0.100, 1.668 + (HEAD_Z0 - WOLF_HEAD_Z0))
## The crown overhangs the head the way Wolf's hair slab overhangs his prism.
HAIR_RADIUS = 0.128
HAIR_OVERLAP = 0.015
CROP_THICK = 0.032
BUN_THICK = 0.05


def _mat(name, hex_code, roughness=0.8):
    def channel(value):
        return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4

    color = int(hex_code, 16)
    linear = tuple(channel(((color >> shift) & 0xFF) / 255.0) for shift in (16, 8, 0))
    return rb.material(name, linear, roughness=roughness)


def _figure(parent, cheer):
    skin = _mat("skin", "c8b09a")
    cloth = _mat("fabric", "8a6748")
    rb.box("Pelvis", (0.28, 0.22, 0.16), (0.0, 0.02, 0.48), cloth, parent=parent)
    rb.box("Torso", (0.32, 0.2, 0.34), (0.0, 0.0, 0.72), cloth, parent=parent)
    rb.box("Thigh.L", (0.1, 0.28, 0.1), (-0.08, 0.16, 0.4), cloth, parent=parent)
    rb.box("Thigh.R", (0.1, 0.28, 0.1), (0.08, 0.16, 0.4), cloth, parent=parent)
    rb.box("Shin.L", (0.09, 0.1, 0.22), (-0.08, 0.28, 0.2), skin, parent=parent)
    rb.box("Shin.R", (0.09, 0.1, 0.22), (0.08, 0.28, 0.2), skin, parent=parent)
    if cheer:
        rb.box("Arm.L", (0.08, 0.08, 0.28), (-0.22, 0.0, 1.05), skin, parent=parent)
        rb.box("Arm.R", (0.08, 0.08, 0.28), (0.22, 0.0, 1.05), skin, parent=parent)
    else:
        rb.box("Arm.L", (0.08, 0.22, 0.08), (-0.2, 0.16, 0.62), skin, parent=parent)
        rb.box("Arm.R", (0.08, 0.22, 0.08), (0.2, 0.16, 0.62), skin, parent=parent)


def _head(parent, material):
    rb.prism(
        "HeadSkin", 5, HEAD_RADIUS, HEAD_Z0, HEAD_Z1, material,
        parent=parent, depth_scale=HEAD_DEPTH, spin=HEAD_SPIN, bevel=HEAD_BEVEL,
    )


def _face(parent, material):
    ## The same dark marks as Wolf: two eyes and one brow bar, on the point.
    rb.box("Eye.L", EYE_SIZE, (EYE_X, EYE_Y, EYE_Z), material, parent=parent)
    rb.box("Eye.R", EYE_SIZE, (-EYE_X, EYE_Y, EYE_Z), material, parent=parent)
    rb.box("Brow", BROW_SIZE, BROW_AT, material, parent=parent)


def _cap(parent, material, thick):
    z0 = HEAD_Z1 - HAIR_OVERLAP
    rb.prism(
        "HairCap", 5, HAIR_RADIUS, z0, z0 + thick, material,
        parent=parent, depth_scale=HEAD_DEPTH, spin=HEAD_SPIN, bevel=0.006,
    )


def _back_edge_y():
    ## A five-sided head has an edge opposite the forward point, not a vertex.
    step = math.tau / 5.0
    samples = []
    for index in (2, 3):
        angle = HEAD_SPIN + step * index
        samples.append(math.sin(angle) * HEAD_RADIUS * HEAD_DEPTH)
    return 0.5 * (samples[0] + samples[1])


def _bun(parent, material):
    ## Sit on that back edge. The width stays inside the edge so it does not
    ## square off the pentagon.
    edge_y = _back_edge_y()
    rb.box(
        "HairBun", (0.12, 0.06, 0.1),
        (0.0, edge_y - 0.01, HEAD_Z0 + 0.16),
        material, parent=parent, bevel=0.006,
    )


def _join_materials():
    bpy.context.view_layer.update()
    groups = {}
    for obj in list(bpy.data.objects):
        if obj.type != "MESH" or not obj.data.materials:
            continue
        groups.setdefault(obj.data.materials[0].name, []).append(obj)
    for name, objs in groups.items():
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objs:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        if len(objs) > 1:
            bpy.ops.object.join()
        bpy.context.view_layer.objects.active.name = name


def _save(name, cheer):
    rb.reset_scene()
    root = rb.empty(name, (0.0, 0.0, 0.0), size=0.2)
    _figure(root, cheer)
    _head(root, _mat("skin", "c8b09a"))
    _join_materials()
    out = os.path.join(ROOT, "art-src", "blender", "crowd", "%s.blend" % name)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=out, compress=True)
    print("RIPOSTE_CROWD", out)


def _save_part(name, build):
    rb.reset_scene()
    ## The joined mesh takes the material name. The empty must not take it first.
    root = rb.empty(name if name != "face" else "crowd_face", (0.0, 0.0, 0.0), size=0.2)
    build(root)
    _join_materials()
    out = os.path.join(ROOT, "art-src", "blender", "crowd", "%s.blend" % name)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=out, compress=True)
    print("RIPOSTE_CROWD", out)


def _build_crop(root):
    _cap(root, _mat("hair", "2a2420", 0.9), CROP_THICK)


def _build_bun(root):
    hair = _mat("hair", "2a2420", 0.9)
    _cap(root, hair, BUN_THICK)
    _bun(root, hair)


def _build_face(root):
    _face(root, _mat("face", "08080c", 0.6))


def main():
    _save("seated", False)
    _save("cheer", True)
    _save_part("hair_crop", _build_crop)
    _save_part("hair_bun", _build_bun)
    _save_part("face", _build_face)


if __name__ == "__main__":
    main()
