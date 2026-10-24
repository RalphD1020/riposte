"""Seated and cheer block figures at Wolf's head proportion.

Blender faces the figure along +Y, which the glTF export turns into Godot -Z,
so a node that looks at the arena centre is facing the fight. Wolf faces -Y.
Skin, cloth, hair, and the face are separate meshes so a MultiMesh can tint
each one, and every one shares the figure's origin. The face is the pentagon;
the crown and the hair are shrinking rings of that same polygon. The eyes and
the brow bar are Wolf's, placed by the
same fractions of this head (ART-HEAD-001), on its front faces.

Run: blender --background --factory-startup --python tools/blender/bootstrap/build_crowd.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import riposte_blocks as rb  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))

## A default person's head, near Wolf's 0.125 m radius and 0.25 m height.
## The body below stays the simple tunic, not Wolf's armor. It starts inside
## the neck so it sits on it. The point faces +Y here and -Y on Wolf.
HEAD_RADIUS = 0.125
HEAD_HEIGHT = 0.25
HEAD_Z0 = 0.92
HEAD_Z1 = HEAD_Z0 + HEAD_HEIGHT
HEAD_DEPTH = 0.95
HEAD_SPIN = math.pi * 0.5
## Wolf's face as fractions of his head (ART-HEAD-001): eyes at 0.54 of its
## height, the brow at 0.672, sizes and spacing scaled by the head's radius.
## Never his world coordinates: copying those put the marks at mouth height.
WOLF_HEAD_RADIUS = 0.125
FACE_SCALE = HEAD_RADIUS / WOLF_HEAD_RADIUS
EYE_SIZE = (0.035 * FACE_SCALE, 0.012, 0.02 * FACE_SCALE)
EYE_X = 0.04 * FACE_SCALE
EYE_Z = HEAD_Z0 + 0.54 * HEAD_HEIGHT
BROW_SIZE = (0.12 * FACE_SCALE, 0.02, 0.022 * FACE_SCALE)
BROW_Z = HEAD_Z0 + 0.672 * HEAD_HEIGHT
## How far an eye's centre stands in front of the face, as on Wolf.
EYE_PROUD = 0.002
## Hair is a thin dome just outside the skull, not a slab on a flat lid.
HAIR_RADIUS = 0.131
## The face prism ends just above the brow. The crown uses the rest of the
## 0.25 m head, so the seated height stays put and the lid is no longer flat.
FACE_FRACTION = 0.74
## The bun sits on the back edge at this share of the head's height.
BUN_HEIGHT = 0.42


def _mat(name, hex_code, roughness=0.8):
    def channel(value):
        return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4

    color = int(hex_code, 16)
    linear = tuple(channel(((color >> shift) & 0xFF) / 255.0) for shift in (16, 8, 0))
    return rb.material(name, linear, roughness=roughness)


def _segment(name, a, b, width, depth, mat, parent):
    """A block from a to b. Local +Y points at the sand once the seat looks inward."""
    start = Vector(a)
    end = Vector(b)
    span = end - start
    length = span.length
    if length < 1.0e-4:
        return None
    obj = rb.box(name, (width, depth, length), (0.0, 0.0, 0.0), mat, parent=parent, bevel=0.004)
    obj.location = (start + end) * 0.5
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(span.normalized())
    return obj


def _limb(name, a, b, width, depth, skin, cloth, parent):
    """Skin segment, then a slightly larger cloth shell on the same line."""
    _segment(name, a, b, width, depth, skin, parent)
    _segment(name + "Cloth", a, b, width + 0.018, depth + 0.018, cloth, parent)


def _figure(parent, cheer):
    skin = _mat("skin", "c8b09a")
    cloth = _mat("fabric", "8a5a3c")
    leather = _mat("leather", "6b4226", 0.7)
    rb.box("Pelvis", (0.22, 0.16, 0.14), (0.0, 0.0, 0.48), skin, parent=parent)
    rb.box("Torso", (0.26, 0.16, 0.28), (0.0, 0.0, 0.7), skin, parent=parent)
    rb.box("Tunic", (0.32, 0.2, 0.28), (0.0, 0.02, 0.72), cloth, parent=parent)
    rb.box("Hem", (0.34, 0.22, 0.06), (0.0, 0.03, 0.56), cloth, parent=parent)
    rb.box("Panel", (0.16, 0.04, 0.16), (0.0, 0.12, 0.5), cloth, parent=parent)
    rb.box("Collar", (0.18, 0.12, 0.05), (0.0, 0.02, 0.86), cloth, parent=parent)
    rb.box("Belt", (0.34, 0.22, 0.05), (0.0, 0.03, 0.6), leather, parent=parent)
    rb.box("Neck", (0.08, 0.08, 0.08), (0.0, 0.0, 0.9), skin, parent=parent)
    for side, sign in (("L", -1.0), ("R", 1.0)):
        hip = (0.09 * sign, 0.02, 0.46)
        knee = (0.09 * sign, 0.30, 0.42)
        ankle = (0.09 * sign, 0.38, 0.16)
        _limb("Thigh." + side, hip, knee, 0.09, 0.1, skin, cloth, parent)
        _limb("Shin." + side, knee, ankle, 0.07, 0.08, skin, cloth, parent)
        rb.box(
            "Boot." + side, (0.1, 0.16, 0.08),
            (0.09 * sign, 0.44, 0.1), leather, parent=parent, bevel=0.004,
        )
        rb.box(
            "Cuff." + side, (0.11, 0.1, 0.04),
            (0.09 * sign, 0.36, 0.16), leather, parent=parent, bevel=0.003,
        )
        shoulder = (0.18 * sign, 0.0, 0.82)
        if cheer:
            elbow = (0.22 * sign, 0.02, 1.05)
            wrist = (0.16 * sign, 0.0, 1.26)
        else:
            elbow = (0.2 * sign, 0.14, 0.62)
            wrist = (0.08 * sign, 0.22, 0.5)
        _limb("UpperArm." + side, shoulder, elbow, 0.06, 0.06, skin, cloth, parent)
        _limb("Forearm." + side, elbow, wrist, 0.05, 0.05, skin, cloth, parent)
        _segment(
            "Bracer." + side,
            (
                elbow[0] * 0.35 + wrist[0] * 0.65,
                elbow[1] * 0.35 + wrist[1] * 0.65,
                elbow[2] * 0.35 + wrist[2] * 0.65,
            ),
            wrist, 0.062, 0.062, leather, parent,
        )
        rb.box(
            "Hand." + side, (0.05, 0.04, 0.06),
            (wrist[0], wrist[1] + (0.0 if cheer else 0.03), wrist[2]),
            skin, parent=parent, bevel=0.003,
        )


def _head(parent, material):
    face_top = HEAD_Z0 + FACE_FRACTION * HEAD_HEIGHT
    rb.prism(
        "HeadSkin", 5, HEAD_RADIUS, HEAD_Z0, face_top, material,
        parent=parent, depth_scale=HEAD_DEPTH, top_scale=0.9, spin=HEAD_SPIN, bevel=0.0,
    )
    rb.dome(
        "HeadCrown", 5, HEAD_RADIUS,
        (
            (face_top - 0.002, 0.92, 0.0, 0.0),
            (face_top + 0.022, 0.68, 0.0, 0.004),
            (face_top + 0.042, 0.42, 0.0, 0.008),
        ),
        (0.0, 0.01, HEAD_Z1),
        material, parent=parent, depth_scale=HEAD_DEPTH, spin=HEAD_SPIN,
    )


def _face_y(x):
    """The front of the pentagon at `x` across: the point, falling back along
    the two front faces toward the neighbouring corners."""
    step = math.tau / 5.0
    point = HEAD_RADIUS * HEAD_DEPTH
    corner_x = abs(math.cos(HEAD_SPIN + step)) * HEAD_RADIUS
    corner_y = math.sin(HEAD_SPIN + step) * HEAD_RADIUS * HEAD_DEPTH
    return point - abs(x) * (point - corner_y) / corner_x


def _face(parent, material):
    ## The same dark marks as Wolf: two eyes and one brow bar across the point.
    ## Each eye sits on its front face. The bar rests on the faces at its ends
    ## and the point comes through its middle, as on Wolf.
    eye_y = _face_y(EYE_X) + EYE_PROUD
    rb.box("Eye.L", EYE_SIZE, (EYE_X, eye_y, EYE_Z), material, parent=parent)
    rb.box("Eye.R", EYE_SIZE, (-EYE_X, eye_y, EYE_Z), material, parent=parent)
    brow_y = _face_y(BROW_SIZE[0] * 0.5) + BROW_SIZE[1] * 0.5
    rb.box("Brow", BROW_SIZE, (0.0, brow_y, BROW_Z), material, parent=parent)


def _cap(parent, material):
    face_top = HEAD_Z0 + FACE_FRACTION * HEAD_HEIGHT
    z0 = face_top - 0.01
    rb.dome(
        "HairCap", 5, HAIR_RADIUS,
        (
            (z0, 0.98, 0.0, 0.0),
            (z0 + 0.028, 0.7, 0.0, 0.004),
            (z0 + 0.048, 0.4, 0.0, 0.008),
        ),
        (0.0, 0.012, HEAD_Z1 + 0.01),
        material, parent=parent, depth_scale=HEAD_DEPTH, spin=HEAD_SPIN,
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
        (0.0, edge_y - 0.01, HEAD_Z0 + BUN_HEIGHT * HEAD_HEIGHT),
        material, parent=parent, bevel=0.006,
    )


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
    _cap(root, _mat("hair", "2a2420", 0.9))


def _build_bun(root):
    hair = _mat("hair", "2a2420", 0.9)
    _cap(root, hair)
    _bun(root, hair)


def _build_face(root):
    _face(root, _mat("face", "08080c", 0.6))


def _build_fringe(root):
    hair = _mat("hair", "2a2420", 0.9)
    _cap(root, hair)
    rb.box(
        "HairFringe", (0.1, 0.04, 0.05),
        (0.0, HEAD_RADIUS * 0.72, HEAD_Z1 - 0.02),
        hair, parent=root, bevel=0.004,
    )


def main():
    _save("seated", False)
    _save("cheer", True)
    _save_part("hair_crop", _build_crop)
    _save_part("hair_bun", _build_bun)
    _save_part("hair_fringe", _build_fringe)
    _save_part("face", _build_face)


if __name__ == "__main__":
    main()
