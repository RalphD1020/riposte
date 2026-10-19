"""Seated and cheer block figures at Wolf's head proportion.

Blender faces the figure along +Y, which the glTF export turns into Godot -Z,
so a node that looks at the arena centre is facing the fight. Skin, cloth,
and hair are separate meshes so a MultiMesh can tint each one.

Run: blender --background --factory-startup --python tools/blender/bootstrap/build_crowd.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import bpy  # noqa: E402

import riposte_blocks as rb  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))


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
    rb.prism("HeadSkin", 5, 0.125, 0.98, 1.23, material, parent=parent, spin=math.pi * 0.5)


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


def _save_hair(name, location):
    rb.reset_scene()
    root = rb.empty(name, (0.0, 0.0, 0.0), size=0.2)
    rb.box("Hair", (0.22, 0.16, 0.1), location, _mat("hair", "2a2420", 0.9), parent=root)
    _join_materials()
    out = os.path.join(ROOT, "art-src", "blender", "crowd", "%s.blend" % name)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=out, compress=True)
    print("RIPOSTE_CROWD", out)


def main():
    _save("seated", False)
    _save("cheer", True)
    _save_hair("hair_crop", (0.0, 0.02, 1.24))
    _save_hair("hair_bun", (0.0, -0.06, 1.28))


if __name__ == "__main__":
    main()
