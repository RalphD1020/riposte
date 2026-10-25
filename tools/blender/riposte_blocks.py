"""Shared block-construction helpers for Riposte's Blender sources.

Riposte's look is volumetric block construction: every piece of clothing and
equipment is its own low-poly solid, not paint on a body. These helpers build
those solids deterministically so a bootstrap script always produces the same
source file, which artists (or Blender MCP) then refine by hand.

Axes: Blender is Z-up. Fighters face -Y, so the glTF exporter's Y-up
conversion puts them facing Godot +Z, which is where the proxy's
`WeaponOrigin` points the blade at weapon angle 0.
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


def stubble_mask(color):
    """Opaque face paint. `color` is the linear skin from the one conversion.
    Beard pixels are that color pulled down, in stepped clusters on the jaw
    and lower cheeks. The nose, the upper lip, and any mouth-shaped bar stay
    the plain skin color."""
    size = 32
    image = bpy.data.images.new("wolf_stubble", size, size, alpha=False, float_buffer=True)
    image.colorspace_settings.name = "sRGB"
    pixels = []
    for _pixel in range(size * size):
        pixels.extend((color[0], color[1], color[2], 1.0))
    shade = tuple(channel * 0.72 for channel in color)

    def put(x, y):
        if 0 <= x < size and 0 <= y < size:
            index = (y * size + x) * 4
            pixels[index] = shade[0]
            pixels[index + 1] = shade[1]
            pixels[index + 2] = shade[2]

    for x, y in (
        (4, 3), (5, 3), (5, 4), (6, 4), (6, 5), (7, 5),
        (4, 6), (5, 6), (8, 6), (8, 7),
        (24, 3), (25, 3), (25, 4), (26, 4), (26, 5), (27, 5),
        (24, 6), (27, 6), (23, 7), (28, 7),
        (15, 1), (16, 1), (15, 2), (16, 2), (14, 2), (17, 3),
    ):
        put(x, y)
    image.pixels.foreach_set(pixels)
    image.pack()
    return image


def material_with_mask(name, color, image, roughness=0.75):
    """HeadSkin only. The image is the albedo, so the shared skin material
    stays untouched. The image already holds the linear skin color."""
    mat = material(name, (1.0, 1.0, 1.0), roughness=roughness)
    tree = mat.node_tree
    bsdf = next(node for node in tree.nodes if node.type == "BSDF_PRINCIPLED")
    tex = tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Closest"
    tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
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


def span(name, a, b, width, depth, mat, bevel=0.0, overlap_from=0.0, overlap_to=0.0):
    """A block whose long axis runs from `a` to `b`. Local +Z is that axis
    until the caller bakes the transform. Fighters and the crowd both use this
    for limbs, sleeves, and bracers.

    `overlap_from` and `overlap_to` are metres along that axis, past the
    anchors. They bury one segment in the next so a bent joint is not two
    caps touching at a point. The anchors stay where the rig put them. A
    zero overlap is a cap that ends on the anchor, which is what the grip
    end of a hand must stay.
    """
    start, end = Vector(a), Vector(b)
    delta = end - start
    length = delta.length
    unit = delta / length if length > 1.0e-8 else Vector((0.0, 0.0, 1.0))
    start = start - unit * float(overlap_from)
    end = end + unit * float(overlap_to)
    length = (end - start).length
    obj = box(name, (width, depth, length), (0.0, 0.0, 0.0), mat, bevel=bevel)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference((end - start).normalized())
    obj.location = (start + end) * 0.5
    return obj


def tapered_segment(
    name, a, b, width0, depth0, width1, depth1, mat,
    bevel=0.0, overlap_from=0.0, overlap_to=0.0, rings=2, sides=6,
):
    """A faceted limb from `a` to `b`. Width and depth are full sizes at each
    end. The anchors stay put; overlap buries the caps the same way `span`
    does. Two rings are a straight taper. More rings only add stations along
    that same line. Hands that must stop on a grip stay on `span`."""
    start, end = Vector(a), Vector(b)
    delta = end - start
    unit = delta.normalized() if delta.length > 1.0e-8 else Vector((0.0, 0.0, 1.0))
    start = start - unit * float(overlap_from)
    end = end + unit * float(overlap_to)
    axis = end - start
    tangent = axis.normalized() if axis.length > 1.0e-8 else Vector((0.0, 0.0, 1.0))
    up = Vector((0.0, 0.0, 1.0))
    if abs(tangent.dot(up)) > 0.85:
        up = Vector((0.0, 1.0, 0.0))
    side = tangent.cross(up).normalized()
    lift = side.cross(tangent).normalized()
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    count = max(int(rings), 2)
    corners = max(int(sides), 4)
    loops = []
    for index in range(count):
        t = index / (count - 1)
        point = start.lerp(end, t)
        half_w = (float(width0) + (float(width1) - float(width0)) * t) * 0.5
        half_d = (float(depth0) + (float(depth1) - float(depth0)) * t) * 0.5
        ring = []
        for corner in range(corners):
            angle = math.tau * corner / corners
            ring.append(bm.verts.new(point + side * (math.cos(angle) * half_w) + lift * (math.sin(angle) * half_d)))
        loops.append(ring)
    bm.faces.new(loops[0][::-1])
    bm.faces.new(loops[-1])
    for index in range(count - 1):
        begin, finish = loops[index], loops[index + 1]
        for corner in range(corners):
            nxt = (corner + 1) % corners
            bm.faces.new((begin[corner], begin[nxt], finish[nxt], finish[corner]))
    _finish(bm, mesh, bevel)
    return _object(name, mesh, mat, None)


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


def _profile(kind):
    ## (side, lift) pairs. Width and depth scale them. A gem has a ridge,
    ## so a lock is not a rectangular plank.
    if kind == "gem":
        return ((0.0, 0.5), (0.5, 0.15), (0.32, -0.5), (-0.32, -0.5), (-0.5, 0.15))
    if kind == "ridge":
        return ((0.0, 0.5), (0.5, -0.5), (-0.5, -0.5))
    return ((-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5))


def clump(name, points, widths, depths, mat, parent=None, bevel=0.0, profile="gem"):
    """A faceted solid along a centerline. `profile` is gem, ridge, or rect.
    Width and depth taper along the path. A gem is the hair lock. A rect is
    a block, and a short wide one is the plank this exists to avoid."""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    stations = [Vector(point) for point in points]
    tangents = []
    for index, point in enumerate(stations):
        if index == 0:
            tangent = stations[1] - stations[0]
        elif index == len(stations) - 1:
            tangent = stations[-1] - stations[-2]
        else:
            tangent = stations[index + 1] - stations[index - 1]
        tangents.append(tangent.normalized() if tangent.length > 1e-8 else Vector((0.0, 0.0, 1.0)))
    rings = []
    up = Vector((0.0, 0.0, 1.0))
    for index, point in enumerate(stations):
        tangent = tangents[index]
        side = tangent.cross(up)
        if side.length < 1e-6:
            side = tangent.cross(Vector((0.0, 1.0, 0.0)))
        side.normalize()
        lift = side.cross(tangent).normalized()
        half_w = float(widths[index])
        half_d = float(depths[index])
        ring = []
        for sx, sy in _profile(profile):
            ring.append(bm.verts.new(point + side * (sx * half_w) + lift * (sy * half_d)))
        rings.append(ring)
    count = len(rings[0])
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])
    for index in range(len(rings) - 1):
        start, end = rings[index], rings[index + 1]
        for corner in range(count):
            nxt = (corner + 1) % count
            bm.faces.new((start[corner], start[nxt], end[nxt], end[corner]))
    _finish(bm, mesh, bevel)
    return _object(name, mesh, mat, parent)


def _crown_ring(bm, sides, radius, ring, center, depth_scale, spin, inset):
    z = float(ring[0])
    scale = float(ring[1])
    ox = float(ring[2]) if len(ring) > 2 else 0.0
    oy = float(ring[3]) if len(ring) > 3 else 0.0
    radial = max(radius * scale, 1.0e-4)
    ratio = max(radial - inset, 0.004) / radial
    loop = []
    for index in range(int(sides)):
        angle = spin + math.tau * index / int(sides)
        x = center[0] + ox + math.cos(angle) * radius * scale * ratio
        y = center[1] + oy + math.sin(angle) * radius * scale * depth_scale * ratio
        loop.append(bm.verts.new((x, y, z)))
    return loop


def dome(name, sides, radius, rings, apex, mat, parent=None, center=(0.0, 0.0), depth_scale=1.0, spin=0.0, bevel=0.0, thickness=0.0):
    """A faceted crown of the same polygon as the face.

    `apex` None closes the last ring as a pentagonal face: a solid cap, not
    a point. `thickness` 0 with an apex is the bald skull, open at the
    bottom, sitting on the face prism. A positive thickness is a hollow
    shell. The ring scales are the roundness. A bevel is optional and is
    not what makes the cap round.
    """
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    count = int(sides)
    outer = [_crown_ring(bm, count, radius, ring, center, depth_scale, spin, 0.0) for ring in rings]
    if apex is None:
        bm.faces.new(outer[0][::-1])
        for lower, upper in zip(outer, outer[1:]):
            for index in range(count):
                nxt = (index + 1) % count
                bm.faces.new((lower[index], lower[nxt], upper[nxt], upper[index]))
        bm.faces.new(outer[-1])
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        if bevel > 0.0:
            bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=1, affect="EDGES", clamp_overlap=True)
        bm.to_mesh(mesh)
        bm.free()
        for poly in mesh.polygons:
            poly.use_smooth = False
        return _object(name, mesh, mat, parent)
    tip = bm.verts.new((float(apex[0]), float(apex[1]), float(apex[2])))
    if thickness <= 0.0:
        bottom = bm.faces.new(outer[0][::-1])
        _dome_shell(bm, outer, tip, count)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.faces.remove(bottom)
    else:
        inner = [_crown_ring(bm, count, radius, ring, center, depth_scale, spin, thickness) for ring in rings]
        inner_tip = bm.verts.new((float(apex[0]), float(apex[1]), float(apex[2]) - thickness))
        _dome_shell(bm, outer, tip, count)
        _dome_shell(bm, inner, inner_tip, count, inward=True)
        for index in range(count):
            nxt = (index + 1) % count
            bm.faces.new((outer[0][index], outer[0][nxt], inner[0][nxt], inner[0][index]))
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    if bevel > 0.0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=1, affect="EDGES", clamp_overlap=True)
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = False
    return _object(name, mesh, mat, parent)


def _dome_shell(bm, rings, tip, count, inward=False):
    for lower, upper in zip(rings, rings[1:]):
        for index in range(count):
            nxt = (index + 1) % count
            if inward:
                bm.faces.new((lower[nxt], lower[index], upper[index], upper[nxt]))
            else:
                bm.faces.new((lower[index], lower[nxt], upper[nxt], upper[index]))
    last = rings[-1]
    for index in range(count):
        nxt = (index + 1) % count
        if inward:
            bm.faces.new((last[nxt], last[index], tip))
        else:
            bm.faces.new((last[index], last[nxt], tip))


def _uv_face(mesh, sides):
    """UVs for the pentagonal face only. The two quads that meet at the
    forward vertex carry the beard mask. Every other face sits on white."""
    layer = mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        loops = list(poly.loop_indices)
        if poly.index < 2 or poly.index - 2 >= sides:
            for loop_index in loops:
                layer.data[loop_index].uv = (0.02, 0.98)
            continue
        side = poly.index - 2
        if side == sides - 1:
            u0, u1 = 0.06, 0.46
        elif side == 0:
            u0, u1 = 0.54, 0.94
        else:
            u0, u1 = 0.02, 0.02
        coords = ((u0, 0.0), (u1, 0.0), (u1, 1.0), (u0, 1.0))
        for loop_index, coord in zip(loops, coords):
            layer.data[loop_index].uv = coord


def prism(name, sides, radius, z0, z1, mat, parent=None, center=(0.0, 0.0), depth_scale=1.0, top_scale=1.0, spin=0.0, bevel=0.0, axis="Z", face_uv=False):
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
    if face_uv:
        _uv_face(mesh, sides)
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
