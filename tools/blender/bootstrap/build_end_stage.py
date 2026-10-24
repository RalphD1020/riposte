"""The End: an octagonal deck in the void. Not the Arena bowl.

Named parts: Top, Edge, Underside, Orb. They are decoration. The game owns
the one flat disc collider. Do not write standard_arena.blend or arena_bowl.blend.

Run: blender --background --factory-startup --python tools/blender/bootstrap/build_end_stage.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import bmesh  # noqa: E402
import bpy  # noqa: E402

import riposte_blocks as rb  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
## Distance from the centre to a flat. The combat disc is this radius, so the
## deck covers it. The vertices sit further out.
APOTHEM = 8.27
SIDES = 8
VERTEX = APOTHEM / math.cos(math.pi / SIDES)
## A flat of the octagon faces the spawn axis (Blender +Y, Godot -Z).
SPIN = math.pi / 2.0 - math.pi / SIDES


def srgb(hex_code):
    def channel(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    value = int(hex_code, 16)
    return tuple(channel(((value >> shift) & 0xFF) / 255.0) for shift in (16, 8, 0))


def band(name, inner, outer, z0, z1, mat, parent):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()

    def ring(radius, z):
        verts = []
        for i in range(SIDES):
            angle = SPIN + math.tau * i / SIDES
            verts.append(bm.verts.new((math.cos(angle) * radius, math.sin(angle) * radius, z)))
        return verts

    outer_bot = ring(outer, z0)
    outer_top = ring(outer, z1)
    inner_bot = ring(inner, z0)
    inner_top = ring(inner, z1)
    for i in range(SIDES):
        j = (i + 1) % SIDES
        bm.faces.new((outer_bot[i], outer_bot[j], outer_top[j], outer_top[i]))
        bm.faces.new((inner_top[i], inner_top[j], inner_bot[j], inner_bot[i]))
        bm.faces.new((outer_top[i], outer_top[j], inner_top[j], inner_top[i]))
        bm.faces.new((inner_bot[i], inner_bot[j], outer_bot[j], outer_bot[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    mesh.materials.append(mat)
    obj.parent = parent
    return obj


def orb(mat, parent):
    mesh = bpy.data.meshes.new("Orb")
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=8, radius=0.9)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0.0, 0.0, -2.15))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("Orb", mesh)
    bpy.context.scene.collection.objects.link(obj)
    mesh.materials.append(mat)
    obj.parent = parent
    return obj


def build():
    rb.reset_scene()
    deck = rb.material("deck", srgb("1c1630"), roughness=0.92)
    edge = rb.material("edge", srgb("5c4578"), roughness=0.55, emission=srgb("5c4578"), emission_strength=0.45)
    underside = rb.material("underside", srgb("120e1c"), roughness=0.95)
    glow = rb.material("orb", srgb("6e5a90"), roughness=0.4, emission=srgb("6e5a90"), emission_strength=0.8)
    root = rb.empty("EndRoot", (0.0, 0.0, 0.0), size=0.5)
    rb.prism("Top", SIDES, VERTEX, -0.06, 0.0, deck, parent=root, spin=SPIN)
    band("Edge", (APOTHEM - 0.05) / math.cos(math.pi / SIDES), (APOTHEM + 0.23) / math.cos(math.pi / SIDES), -0.05, -0.002, edge, root)
    rb.prism("Underside", SIDES, VERTEX * 0.9, -0.06, -1.55, underside, parent=root, spin=SPIN, top_scale=0.28)
    orb(glow, root)


def main():
    build()
    out = os.path.join(ROOT, "art-src", "blender", "arenas", "end_stage.blend")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=out, compress=True)
    print("RIPOSTE_BUILT", out)


if __name__ == "__main__":
    main()
