"""Shared block-construction helpers for Riposte's Blender sources.

Riposte's look is volumetric block construction: every piece of clothing and
equipment is its own low-poly solid, not paint on a body. These helpers build
those solids deterministically so a bootstrap script always produces the same
source file, which artists (or Blender MCP) then refine by hand.

Axes: Blender is Z-up. Fighters face -Y, so the glTF exporter's Y-up
conversion puts them facing Godot +Z, which is where `SwordPivot` points the
blade at weapon angle 0.
"""

import math

import bmesh
import bpy
from mathutils import Matrix, Vector


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.fps = 60
    return scene


def material(name, color, roughness=0.8, metallic=0.0, emission=None, emission_strength=0.0):
    """One opaque Principled material. Looked up by node type, never by name."""
    existing = bpy.data.materials.get(name)
    if existing is not None:
        return existing
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    mat.diffuse_color = (*color, 1.0)
    return mat


def _object(name, mesh, mat, parent):
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    if mat is not None:
        mesh.materials.append(mat)
    if parent is not None:
        obj.parent = parent
    return obj


def _finish(bm, mesh, bevel):
    if bevel > 0.0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=1, affect="EDGES", clamp_overlap=True)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = False


def box(name, size, location, mat, parent=None, bevel=0.0, rotation=(0.0, 0.0, 0.0)):
    """An axis-aligned block of `size` (x, y, z) centred at `location`."""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=Vector((0, 0, 0)), matrix=Matrix.Rotation(rotation[0], 3, "X") @ Matrix.Rotation(rotation[1], 3, "Y") @ Matrix.Rotation(rotation[2], 3, "Z"))
    bmesh.ops.translate(bm, vec=Vector(location), verts=bm.verts)
    _finish(bm, mesh, bevel)
    return _object(name, mesh, mat, parent)


def prism(name, sides, radius, z0, z1, mat, parent=None, center=(0.0, 0.0), depth_scale=1.0, top_scale=1.0, spin=0.0, bevel=0.0, axis="Z"):
    """A vertical n-gon prism from z0 to z1 (or along -Y when axis == "Y").

    `spin` rotates the polygon; with sides=5 and spin=-pi/2 one vertex points
    to -Y, which is how the pentagonal head points where the fighter faces.
    """
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    rings = []
    for z, scale in ((z0, 1.0), (z1, top_scale)):
        ring = []
        for i in range(sides):
            angle = spin + math.tau * i / sides
            x = math.cos(angle) * radius * scale
            y = math.sin(angle) * radius * scale * depth_scale
            if axis == "Z":
                ring.append(bm.verts.new((center[0] + x, center[1] + y, z)))
            elif axis == "X":
                ring.append(bm.verts.new((z, center[0] + x, center[1] + y)))
            else:
                ring.append(bm.verts.new((center[0] + x, -z, center[1] + y)))
        rings.append(ring)
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[1])
    for i in range(sides):
        j = (i + 1) % sides
        bm.faces.new((rings[0][i], rings[0][j], rings[1][j], rings[1][i]))
    _finish(bm, mesh, bevel)
    return _object(name, mesh, mat, parent)


def blade(name, hilt, tip, width, thickness, point_length, mat, parent=None):
    """A flat hexagonal-section blade along -Y from `hilt` to `tip`, tapering
    to a point over its last `point_length`."""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()

    def section(y, w):
        half_w = w * 0.5
        flat = half_w * 0.45
        half_t = thickness * 0.5
        return [
            bm.verts.new((-half_w, -y, 0.0)),
            bm.verts.new((-flat, -y, -half_t)),
            bm.verts.new((flat, -y, -half_t)),
            bm.verts.new((half_w, -y, 0.0)),
            bm.verts.new((flat, -y, half_t)),
            bm.verts.new((-flat, -y, half_t)),
        ]

    base = section(hilt, width)
    shoulder = section(tip - point_length, width * 0.72)
    point = bm.verts.new((0.0, -tip, 0.0))
    bm.faces.new(base)
    for i in range(6):
        j = (i + 1) % 6
        bm.faces.new((base[i], base[j], shoulder[j], shoulder[i]))
        bm.faces.new((shoulder[i], shoulder[j], point))
    _finish(bm, mesh, 0.0)
    return _object(name, mesh, mat, parent)


def flat_point(name, y0, y1, width, thickness, mat, parent=None):
    """A flat chisel point along -Y: a rectangular base at y0 narrowing to a
    single point at y1. Six triangles, for a chunky angular blade tip."""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    hw, ht = width * 0.5, thickness * 0.5
    base = [
        bm.verts.new((-hw, -y0, -ht)),
        bm.verts.new((hw, -y0, -ht)),
        bm.verts.new((hw, -y0, ht)),
        bm.verts.new((-hw, -y0, ht)),
    ]
    point = bm.verts.new((0.0, -y1, 0.0))
    bm.faces.new(base[::-1])
    for i in range(4):
        bm.faces.new((base[i], base[(i + 1) % 4], point))
    _finish(bm, mesh, 0.0)
    return _object(name, mesh, mat, parent)


def empty(name, location, parent=None, size=0.03):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = size
    obj.location = location
    bpy.context.scene.collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    return obj


def triangle_count(objects):
    total = 0
    for obj in objects:
        if obj.type == "MESH":
            total += sum(len(poly.vertices) - 2 for poly in obj.data.polygons)
    return total


def world_bounds(objects):
    lo = Vector((math.inf, math.inf, math.inf))
    hi = Vector((-math.inf, -math.inf, -math.inf))
    for obj in objects:
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            world = obj.matrix_world @ Vector(corner)
            lo = Vector(map(min, lo, world))
            hi = Vector(map(max, hi, world))
    return lo, hi
