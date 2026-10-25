"""Seated and cheer figures from the spectator character file.

Blender faces the figure along +Y, which the glTF export turns into Godot -Z,
so a node that looks at the arena centre is facing the fight. Wolf faces -Y.
Skin, cloth, hair, and the face are separate meshes so a MultiMesh can tint
each one, and every one shares the figure's origin.

The meshes come from the same compiler and part emitter as a fighter. This
file only chooses a baked pose and joins each material into one layer. It
does not build a head, a limb, or a beard of its own.

Run: blender --background --factory-startup --python tools/blender/bootstrap/build_crowd.py
"""

import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import bpy  # noqa: E402
from mathutils import Matrix  # noqa: E402

import character_art  # noqa: E402
import character_build  # noqa: E402
import riposte_blocks as rb  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SPECTATOR = os.path.join(ROOT, "game", "content", "characters", "spectator.character.json")


def _spectator():
    with open(SPECTATOR, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    problems = character_art.validate(data)
    if problems:
        raise ValueError("\n".join(problems))
    return data


def _emit(parent, variant, wears, pose=None):
    data = character_art.compile(_spectator(), pose)
    mats = character_build.materials_for(data, variant)
    for obj in character_build.emit_visible(data, mats, variant, wears):
        obj.parent = parent


def _figure(parent, pose):
    _emit(parent, "bald", ("person", "clothes"), pose)


def _join_materials():
    ## Bake every piece into the figure's frame first. A join keeps the active
    ## object's origin, and the game takes only the mesh, not its node, so an
    ## unbaked origin would draw the whole layer away from the others.
    bpy.context.view_layer.update()
    groups = {}
    for obj in list(bpy.data.objects):
        if obj.type != "MESH" or not obj.data.materials:
            continue
        obj.data.transform(obj.matrix_world)
        obj.matrix_world = Matrix.Identity(4)
        groups.setdefault(obj.data.materials[0].name, []).append(obj)
    for name, objs in groups.items():
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objs:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        if len(objs) > 1:
            bpy.ops.object.join()
        bpy.context.view_layer.objects.active.name = name


def _save(name, pose):
    rb.reset_scene()
    root = rb.empty(name, (0.0, 0.0, 0.0), size=0.2)
    _figure(root, pose)
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
    _emit(root, "crop", ("hair",))


def _build_bun(root):
    _emit(root, "bun", ("hair",))


def _build_face(root):
    _emit(root, "bald", ("person",))
    ## The face layer is the eyes and the brow, not the skull. Limbs come along
    ## with the person wear and leave with everything else.
    for obj in list(bpy.data.objects):
        if obj.type == "MESH" and obj.name not in ("Eye.L", "Eye.R", "Brow"):
            bpy.data.objects.remove(obj, do_unlink=True)


def _build_fringe(root):
    _emit(root, "fringe", ("hair",))


def _build_beard(root):
    _emit(root, "bald", ("beard",))


def main():
    _save("seated", "seated")
    _save("cheer", "cheer")
    _save_part("hair_crop", _build_crop)
    _save_part("hair_bun", _build_bun)
    _save_part("hair_fringe", _build_fringe)
    _save_part("face", _build_face)
    _save_part("beard_full", _build_beard)


if __name__ == "__main__":
    main()
