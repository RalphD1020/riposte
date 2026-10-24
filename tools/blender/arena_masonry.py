"""Arcade, treads, and the fighting floor. Both read arena_section.json.

Blender is Z-up. A bay is built along +X and rotated about Z by the opposite
of its Godot angle, because the glTF export maps Blender +Y to Godot -Z.
Arch crowns stop at the soffit. They are not a second platform.

See also: docs/concepts/presentation.md
"""

import math

import bmesh
import bpy
from mathutils import Vector

import masonry
import riposte_blocks as rb

BLOCK = (0.36, 0.26, 0.13)
GAP = (0.006, 0.006, 0.006)
COURSE_BEVEL = 0.004
## A hairline so neighbouring bays do not share a face.
WEDGE_INSET = 0.0004
## Crown stones enter the deck by this much so the joint does not crack.
CROWN_OVERLAP = 0.015
## Keep the pier face just inside the curb's outer face.
FACE_INSET = 0.012


def _drop(obj):
    mesh = obj.data
    bpy.data.objects.remove(obj, do_unlink=True)
    if mesh is not None and mesh.users == 0:
        bpy.data.meshes.remove(mesh)


def _aabb(obj):
    corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    xs = [corner.x for corner in corners]
    ys = [corner.y for corner in corners]
    zs = [corner.z for corner in corners]
    return (min(xs), max(xs), min(ys), max(ys), min(zs), max(zs))


def _overlaps(bounds, box):
    return (
        bounds[0] < box[1]
        and bounds[1] > box[0]
        and bounds[2] < box[3]
        and bounds[3] > box[2]
        and bounds[4] < box[5]
        and bounds[5] > box[4]
    )


def _inside(bounds, box):
    return (
        bounds[0] >= box[0]
        and bounds[1] <= box[1]
        and bounds[2] >= box[2]
        and bounds[3] <= box[3]
        and bounds[4] >= box[4]
        and bounds[5] <= box[5]
    )


def _cut_door_recess(obj, box):
    """Take the door volume out of one wall block. Stone outside that volume stays."""
    bounds = _aabb(obj)
    if not _overlaps(bounds, box):
        return obj
    if _inside(bounds, box):
        _drop(obj)
        return None
    x0, x1, y0, y1, z0, z1 = box
    cutter = rb.box(
        "_DoorRecess",
        (x1 - x0, y1 - y0, z1 - z0),
        ((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5),
        None,
        parent=obj.parent,
    )
    modifier = obj.modifiers.new("DoorRecess", "BOOLEAN")
    modifier.operation = "DIFFERENCE"
    modifier.object = cutter
    modifier.solver = "FLOAT"
    bpy.context.view_layer.update()
    evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = bpy.data.meshes.new_from_object(evaluated)
    previous = obj.data
    obj.data = mesh
    obj.modifiers.remove(modifier)
    _drop(cutter)
    if previous.users == 0:
        bpy.data.meshes.remove(previous)
    if len(obj.data.polygons) == 0:
        _drop(obj)
        return None
    return obj


def _half_angle(layout):
    return math.pi / layout["bay_count"] - WEDGE_INSET


def _wedge_planes(half):
    """Outward normals. clear_outer drops the geometry past the bay wedge."""
    planes = []
    for sign in (1.0, -1.0):
        angle = sign * half
        direction = (math.cos(angle), math.sin(angle))
        if sign > 0.0:
            normal = (-direction[1], direction[0], 0.0)
        else:
            normal = (direction[1], -direction[0], 0.0)
        planes.append(normal)
    return planes


def _clip_wedge(obj, half):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for normal in _wedge_planes(half):
        geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
        if not geom:
            break
        bmesh.ops.bisect_plane(
            bm,
            geom=geom,
            plane_co=(0.0, 0.0, 0.0),
            plane_no=normal,
            clear_outer=True,
            clear_inner=False,
        )
    if not bm.faces:
        bm.free()
        _drop(obj)
        return None
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    return obj


def _corners(center, size):
    hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
    found = []
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            for sz in (-1.0, 1.0):
                found.append((center[0] + sx * hx, center[1] + sy * hy, center[2] + sz * hz))
    return found


def _wedge_class(corners, half):
    inside = 0
    for x, y, _z in corners:
        if x <= 0.2 or abs(math.atan2(y, x)) > half:
            continue
        inside += 1
    if inside == 0:
        return "out"
    if inside == len(corners):
        return "in"
    return "cut"


def _in_mouth(y, z, arcade):
    if abs(y) >= arcade["opening"] * 0.5:
        return False
    if z <= arcade["spring"]:
        return True
    radius = arcade["arch_radius"]
    if abs(y) >= radius:
        return False
    intrados = arcade["spring"] + math.sqrt(radius * radius - y * y)
    return z < intrados


def _hits_mouth(center, size, arcade):
    for _x, y, z in _corners(center, size):
        if _in_mouth(y, z, arcade):
            return True
    return False


def _in_voussoir(center, arcade):
    """Square courses leave the arch ring to the radial voussoirs."""
    if center[2] < arcade["spring"] - 0.05:
        return False
    dist = math.hypot(center[1], center[2] - arcade["spring"])
    limit = arcade["arch_radius"] + arcade["voussoir_thickness"] + 0.06
    return dist <= limit and abs(center[1]) <= arcade["opening"] * 0.5 + 0.2


def fill(parent, prefix, origin, size, material, mouth, half, index, course_size=BLOCK):
    """Running-bond courses from `origin` through `size` (x, y, z)."""
    made = []
    z = origin[2]
    course = 0
    while z < origin[2] + size[2] - 1.0e-4:
        height = min(course_size[2], origin[2] + size[2] - z)
        if height < 0.04:
            break
        y_shift = 0.0 if course % 2 == 0 else (course_size[1] + GAP[1]) * 0.5
        y = origin[1] - y_shift
        limit = origin[1] + size[1] + y_shift
        while y + 0.04 <= limit:
            if y < origin[1] - 1.0e-4:
                y += course_size[1] + GAP[1]
                continue
            width = min(course_size[1], limit - y)
            if width < 0.08:
                break
            x = origin[0]
            while x < origin[0] + size[0] - 1.0e-4:
                depth = min(course_size[0], origin[0] + size[0] - x)
                if depth < 0.08:
                    break
                center = (x + depth * 0.5, y + width * 0.5, z + height * 0.5)
                block_size = (depth, width, height)
                corners = _corners(center, block_size)
                kind = _wedge_class(corners, half)
                blocked = mouth is not None and (_hits_mouth(center, block_size, mouth) or _in_voussoir(center, mouth))
                if kind != "out" and not blocked:
                    worn = mouth is not None and z < mouth["spring"]
                    obj = masonry.block(
                        "%s_%d" % (prefix, index),
                        block_size,
                        center,
                        material,
                        parent,
                        masonry.course_tint(index, worn),
                        COURSE_BEVEL,
                    )
                    index += 1
                    if kind == "cut":
                        obj = _clip_wedge(obj, half)
                    if obj is not None:
                        made.append(obj)
                x += depth + GAP[0]
            y += width + GAP[1]
        z += height + GAP[2]
        course += 1
    return made, index


def _arch(parent, prefix, arcade, x0, x1, material):
    depth = (x1 - x0) * 0.92
    made = masonry.voussoirs(
        parent,
        prefix,
        (x0 + x1) * 0.5,
        arcade["spring"],
        arcade["arch_radius"],
        arcade["voussoir_thickness"],
        depth,
        arcade["voussoir_count"],
        material,
    )
    for obj in made:
        obj.location.z += CROWN_OVERLAP
    return made


def build_bay(parent, layout, cut_gate=False):
    """One radial slice. A pit is a solid wall and the seats above it.
    The colonnade path keeps both arcades and the gallery.
    """
    if layout.get("kind") == "pit":
        return _pit_bay(parent, layout, cut_gate)
    half = _half_angle(layout)
    floor = layout["floor"]
    inner = layout["inner_arcade"]
    outer = layout["outer_arcade"]
    tiers = layout["tiers"]
    index = 0
    stand = masonry.role("stone_stand")
    inner_x1 = inner["outer_radius"] - FACE_INSET
    inner_span = inner["opening"] * 0.5 + inner["pier_width"] + 0.04
    made, index = fill(
        parent,
        "Inner",
        (inner["inner_radius"], -inner_span, layout["water_height"]),
        (inner_x1 - inner["inner_radius"], inner_span * 2.0, floor["soffit"] + CROWN_OVERLAP - layout["water_height"]),
        stand,
        inner,
        half,
        index,
    )
    made.extend(_arch(parent, "InnerArch", inner, inner["inner_radius"], inner_x1, stand))
    outer_x1 = outer["inner_radius"] + outer["pier_depth"] - 0.01
    outer_span = outer["opening"] * 0.5 + outer["pier_width"] + 0.04
    wall, index = fill(
        parent,
        "Outer",
        (outer["inner_radius"], -outer_span, layout["water_height"]),
        (outer_x1 - outer["inner_radius"], outer_span * 2.0, outer["soffit"] + CROWN_OVERLAP - layout["water_height"]),
        stand,
        outer,
        half,
        index,
    )
    made.extend(wall)
    made.extend(_arch(parent, "OuterArch", outer, outer["inner_radius"], outer_x1, stand))
    ## The bleachers are the top. The arch stops at the soffit. Each step
    ## covers the crown under it, including the part of the arch that sits
    ## behind the tread in front, so no separate roof shows in front of the seats.
    arch_end = outer["inner_radius"] + outer["pier_depth"]
    for tier_index in range(len(tiers)):
        tier = tiers[tier_index]
        top = tier["tread_height"]
        below = outer["soffit"] if tier_index == 0 else tiers[tier_index - 1]["tread_height"]
        band = tier["outer_radius"] - tier["inner_radius"]
        chord = tier["outer_radius"] * math.sin(math.pi / layout["bay_count"]) + 0.3
        shell, index = fill(
            parent,
            "Tread%d" % tier_index,
            (tier["inner_radius"], -chord, below),
            (band, chord * 2.0, top - below),
            stand,
            None,
            half,
            index,
        )
        made.extend(shell)
        if tier["inner_radius"] < arch_end and below > outer["soffit"] + 0.02:
            cover = min(tier["outer_radius"], arch_end) - tier["inner_radius"]
            if cover > 0.05:
                buried, index = fill(
                    parent,
                    "Cover%d" % tier_index,
                    (tier["inner_radius"], -outer_span, outer["soffit"]),
                    (cover, outer_span * 2.0, below - outer["soffit"]),
                    stand,
                    None,
                    half,
                    index,
                )
                made.extend(buried)
    gallery = layout.get("gallery")
    if gallery is not None and len(tiers) > 4:
        g_span = gallery["opening"] * 0.5 + gallery["pier_width"] + 0.04
        g_x1 = gallery["inner_radius"] + gallery["pier_depth"] - 0.01
        supports, index = fill(
            parent,
            "Gallery",
            (gallery["inner_radius"], -g_span, layout["water_height"]),
            (g_x1 - gallery["inner_radius"], g_span * 2.0, gallery["soffit"] + CROWN_OVERLAP - layout["water_height"]),
            stand,
            gallery,
            half,
            index,
        )
        made.extend(supports)
        made.extend(_arch(parent, "GalleryArch", gallery, gallery["inner_radius"], g_x1, stand))
        gallery_end = gallery["inner_radius"] + gallery["pier_depth"]
        for tier_index in range(4, len(tiers)):
            tier = tiers[tier_index]
            below = tiers[tier_index - 1]["tread_height"]
            if tier["inner_radius"] < gallery_end and below > gallery["soffit"] + 0.02:
                cover = min(tier["outer_radius"], gallery_end) - tier["inner_radius"]
                if cover > 0.05:
                    buried, index = fill(
                        parent,
                        "GalleryCover%d" % tier_index,
                        (tier["inner_radius"], -g_span, gallery["soffit"]),
                        (cover, g_span * 2.0, below - gallery["soffit"]),
                        stand,
                        None,
                        half,
                        index,
                    )
                    made.extend(buried)
        podium = tiers[3]["tread_height"]
        haunch_x = gallery_end
        haunch_w = gallery["outer_radius"] - haunch_x
        if haunch_w > 0.05 and podium > gallery["soffit"] + 0.05:
            chord = gallery["outer_radius"] * math.sin(math.pi / layout["bay_count"]) + 0.3
            haunch, index = fill(
                parent,
                "GalleryHaunch",
                (haunch_x, -chord, gallery["soffit"]),
                (haunch_w, chord * 2.0, podium - gallery["soffit"]),
                stand,
                None,
                half,
                index,
                (0.72, 0.52, 0.34),
            )
            made.extend(haunch)
    return made


COARSE = (0.72, 0.52, 0.34)
## ArenaSurfaceState.STONE_FACE_OUTSET. The inner face stays outside the
## combat disc. The sand disc is drawn past this face.
STONE_FACE_OUTSET = 0.08


def _pit_bay(parent, layout, cut_gate):
    """Solid wall from the combat radius, then the seat treads. A gate bay
    loses the inner courses so the door can sit in the opening.
    """
    half = _half_angle(layout)
    wall = layout["wall"]
    gate = layout["gates"]
    tiers = layout["tiers"]
    stand = masonry.role("stone_stand")
    index = 0
    chord = wall["outer_radius"] * math.sin(math.pi / layout["bay_count"]) + 0.3
    ## The inner face sits outside the combat disc so a block corner cannot
    ## enter it. The sand disc tucks under this face.
    inner = wall["inner_radius"] + STONE_FACE_OUTSET
    made, index = fill(
        parent,
        "Wall",
        (inner, -chord, 0.0),
        (wall["outer_radius"] - inner, chord * 2.0, wall["height"]),
        stand,
        None,
        half,
        index,
        COARSE,
    )
    if cut_gate:
        ## The door is a thin slab on the inner face. The old cut deleted every
        ## block whose centre sat in a slot wider than that slab and about a
        ## metre deep, so the wall stopped beside the door. Keep the stone.
        ## Remove only the recess the door occupies.
        recess = (
            inner,
            gate["radius"] + gate["depth"] * 0.5,
            -gate["width"] * 0.5,
            gate["width"] * 0.5,
            -0.02,
            gate["height"],
        )
        kept = []
        for obj in made:
            cut = _cut_door_recess(obj, recess)
            if cut is not None:
                kept.append(cut)
        made = kept
    below = wall["height"]
    for tier_index, tier in enumerate(tiers):
        band = tier["outer_radius"] - tier["inner_radius"]
        tread_chord = tier["outer_radius"] * math.sin(math.pi / layout["bay_count"]) + 0.3
        shell, index = fill(
            parent,
            "Tread%d" % tier_index,
            (tier["inner_radius"], -tread_chord, below),
            (band, tread_chord * 2.0, tier["tread_height"] - below),
            stand,
            None,
            half,
            index,
            COARSE,
        )
        made.extend(shell)
        below = tier["tread_height"]
    return made


def build_gates(parent, layout):
    """Two wooden doors on the north-south axis. Blender +Y becomes Godot -Z,
    which is north, so the north door is +Y and the south door is -Y.
    """
    gate = layout["gates"]
    wood = rb.material("wood_gate", (0.42, 0.33, 0.27), roughness=0.72)
    radius = gate["radius"]
    size = (gate["width"], gate["depth"], gate["height"])
    centre = gate["height"] * 0.5
    rb.box("GateNorth", size, (0.0, radius, centre), wood, parent, bevel=0.01)
    rb.box("GateSouth", size, (0.0, -radius, centre), wood, parent, bevel=0.01)


def build_water(parent, layout):
    """Ground water from the centre out to the outer tread.

    Both arcades stand in it. The open moat is only the gap between them.
    """
    radius = layout["outer_arcade"]["outer_radius"]
    z1 = layout["water_height"]
    z0 = z1 - 0.18
    segments = 96
    mesh = bpy.data.meshes.new("WaterMesh")
    bm = bmesh.new()
    top_center = bm.verts.new((0.0, 0.0, z1))
    bottom_center = bm.verts.new((0.0, 0.0, z0))
    top = []
    bottom = []
    for i in range(segments):
        angle = math.tau * i / segments
        x = math.cos(angle) * radius
        y = math.sin(angle) * radius
        top.append(bm.verts.new((x, y, z1)))
        bottom.append(bm.verts.new((x, y, z0)))
    for i in range(segments):
        j = (i + 1) % segments
        bm.faces.new((top_center, top[i], top[j]))
        bm.faces.new((bottom_center, bottom[j], bottom[i]))
        bm.faces.new((top[i], bottom[i], bottom[j], top[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    top_up = 0.0
    for polygon in mesh.polygons:
        center = Vector()
        for index in polygon.vertices:
            center += mesh.vertices[index].co
        center /= len(polygon.vertices)
        if center.z > (z0 + z1) * 0.5 and math.hypot(center.x, center.y) < radius * 0.5:
            top_up += polygon.normal.z
    if top_up < 0.0:
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
        bm.to_mesh(mesh)
        bm.free()
    water = rb._object("Water", mesh, masonry.role("basin_water"), parent)
    masonry.paint(water, (1.0, 1.0, 1.0))
    made = [water]
    moat = layout["moat"]
    for i in range(8):
        angle = math.tau * (i + 0.5) / 8.0
        glint_radius = (moat["inner_radius"] + moat["outer_radius"]) * 0.5
        made.append(masonry.block(
            "Glint%d" % i,
            (0.55, 0.28, 0.02),
            (math.cos(angle) * glint_radius, math.sin(angle) * glint_radius, z1 + 0.01),
            masonry.role("basin_glint"),
            parent,
            (1.0, 1.0, 1.0),
            0.0,
            (0.0, 0.0, angle),
        ))
    return made


def _ring(parent, name, r0, r1, z0, z1, material, segments):
    made = []
    height = z1 - z0
    for i in range(segments):
        a0 = math.tau * i / segments
        a1 = math.tau * (i + 1) / segments
        mid = (a0 + a1) * 0.5
        radial = r1 - r0
        tangent = (r0 + r1) * 0.5 * (a1 - a0) * 0.94
        center_r = (r0 + r1) * 0.5
        made.append(masonry.block(
            "%s_%d" % (name, i),
            (radial, tangent, height),
            (math.cos(mid) * center_r, math.sin(mid) * center_r, (z0 + z1) * 0.5),
            material,
            parent,
            masonry.tint_for(i, False),
            0.006,
            (0.0, 0.0, mid),
        ))
    return made


def _overlaps_disc(center, half, radius):
    dx = max(abs(center[0]) - half[0], 0.0)
    dy = max(abs(center[1]) - half[1], 0.0)
    return dx * dx + dy * dy <= radius * radius


def _clip_brick(obj, radius):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for vert in bm.verts:
        flat = math.hypot(vert.co.x, vert.co.y)
        if flat > radius:
            vert.co.x *= radius / flat
            vert.co.y *= radius / flat
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()


def _floor_tint(index, flat, floor_data):
    """Small value shifts. The two rim courses are a shade, not a stripe."""
    shift = ((index * 17) % 7) - 3
    scale = 1.0 + shift * 0.008
    if flat >= floor_data["curb_mid_radius"]:
        scale *= 1.045
    elif flat >= floor_data["curb_inner_radius"]:
        scale *= 0.90
    return (scale, scale, scale)


def build_floor(parent, layout):
    """East-west paving, flush with the fighting plane. No arcade and no collider."""
    floor_data = layout["floor"]
    disc = layout["expected_disc_radius"]
    soffit = floor_data["soffit"]
    top = floor_data["paving_top"]
    paving = masonry.role("stone_floor")
    plate = rb.prism(
        "Soffit",
        72,
        disc,
        soffit,
        top - floor_data["brick_thickness"] - 0.02,
        masonry.role("stone_cliff"),
        parent=parent,
    )
    masonry.paint(plate, (1.0, 1.0, 1.0))
    bed = rb.prism(
        "JointBed",
        72,
        disc,
        top - floor_data["brick_thickness"] - 0.02,
        top - 0.006,
        paving,
        parent=parent,
    )
    masonry.paint(bed, (0.78, 0.76, 0.74))
    made = [plate, bed]
    length = floor_data["brick_length"]
    width = floor_data["brick_width"]
    thick = floor_data["brick_thickness"]
    joint = floor_data["joint"]
    limit = disc - 0.002
    y = -disc
    row = 0
    index = 0
    offsets = []
    while y < disc:
        offset = 0.0 if row % 2 == 0 else floor_data["stagger"]
        offsets.append(offset)
        x = -disc + offset
        while x < disc:
            center = (x + length * 0.5, y + width * 0.5, top - thick * 0.5)
            if _overlaps_disc(center, (length * 0.5, width * 0.5), limit):
                flat = math.hypot(center[0], center[1])
                brick = masonry.block(
                    "Brick_%d" % index,
                    (length, width, thick),
                    center,
                    paving,
                    parent,
                    _floor_tint(index, flat, floor_data),
                    0.004,
                )
                furthest = max(math.hypot(corner.co.x, corner.co.y) for corner in brick.data.vertices)
                if furthest > limit:
                    _clip_brick(brick, limit)
                made.append(brick)
                index += 1
            x += length + joint
        y += width + joint
        row += 1
    if len(offsets) < 2 or abs((offsets[1] - offsets[0]) - floor_data["stagger"]) > 1.0e-6:
        raise SystemExit("floor rows did not stagger east-west")
    return made


def join_children(parent):
    """One mesh per material under `parent`."""
    bpy.context.view_layer.update()
    groups = {}
    for obj in list(parent.children_recursive):
        if obj.type != "MESH" or not obj.data.materials:
            continue
        groups.setdefault(obj.data.materials[0].name, []).append(obj)
    for name, objs in groups.items():
        if len(objs) < 2:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objs:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.join()
        bpy.context.view_layer.objects.active.name = "%s_%s" % (parent.name, name)


def assert_inside_wedge(objects, layout):
    bpy.context.view_layer.update()
    half = math.pi / layout["bay_count"] + 1.0e-3
    for obj in objects:
        if obj.type != "MESH":
            continue
        for vert in obj.data.vertices:
            point = obj.matrix_world @ vert.co
            if point.x * point.x + point.y * point.y < 1.0:
                continue
            angle = abs(math.atan2(point.y, point.x))
            if angle > half:
                raise SystemExit("%s leaves its bay (%.3f rad)" % (obj.name, angle))
