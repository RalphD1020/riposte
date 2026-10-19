"""Block courses for the bowl. Joints are gaps between blocks, not outlines.

Vertex color is a per-block multiplier near white. The material holds the
role color. Most blocks stay near that color; a few are lighter or darker,
and wear darkens a coping edge or a pier foot.
"""

import math

import bmesh
import bpy

import riposte_blocks as rb
import stone_palette as stone

PLATFORM_RADIUS = 8.27
MODULE = 0.25


def snap(value):
    return round(value / MODULE) * MODULE


def role(name):
    roughness = 0.95
    metallic = 0.0
    emission = None
    strength = 0.0
    if name == "gold_trim":
        roughness = 0.45
        metallic = 0.65
    elif name == "basin_water":
        roughness = 0.28
    elif name == "basin_glint":
        roughness = 0.4
        metallic = 0.35
        emission = stone.srgb(stone.ROLES["basin_glint"])
        strength = 0.55
    return rb.material(name, stone.srgb(stone.ROLES[name]), roughness=roughness, metallic=metallic, emission=emission, emission_strength=strength)


def paint(obj, tint):
    mesh = obj.data
    attr = mesh.color_attributes.get("Color")
    if attr is None:
        attr = mesh.color_attributes.new("Color", "FLOAT_COLOR", "CORNER")
    for item in attr.data:
        item.color = (tint[0], tint[1], tint[2], 1.0)
    mesh.color_attributes.active_color = attr
    return obj


def tint_for(index, worn=False):
    """Most blocks sit on the role color. Every seventh block shifts."""
    scale = 1.0
    if index % 7 == 3:
        scale = 1.08
    elif index % 7 == 5:
        scale = 0.90
    if worn:
        scale *= 0.78
    return (scale, scale, scale)


def block(name, size, location, material, parent, tint, bevel=0.012, rotation=(0.0, 0.0, 0.0)):
    obj = rb.box(name, size, location, material, parent=parent, bevel=bevel, rotation=rotation)
    return paint(obj, tint)


def courses(parent, prefix, origin, size, material, gap, bevel, worn_below=None):
    """Running-bond courses filling an axis-aligned box from its min corner.

    `origin` is the minimum x, y, z. `size` is depth, width, height. Vertical
    joints alternate by half a block. Returns the blocks.
    """
    block_size = (0.42, 0.40, 0.22)
    made = []
    course = 0
    index = 0
    z = origin[2]
    while z + block_size[2] <= origin[2] + size[2] + 1e-4:
        y_shift = 0.0 if course % 2 == 0 else (block_size[1] + gap) * 0.5
        y = origin[1] - y_shift
        while y + block_size[1] <= origin[1] + size[1] + y_shift + 1e-4:
            if y < origin[1] - 1e-4:
                y += block_size[1] + gap
                continue
            x = origin[0]
            while x + block_size[0] <= origin[0] + size[0] + 1e-4:
                worn = worn_below is not None and z <= worn_below
                center = (
                    x + block_size[0] * 0.5,
                    y + block_size[1] * 0.5,
                    z + block_size[2] * 0.5,
                )
                made.append(block(
                    "%s_%d" % (prefix, index),
                    block_size,
                    center,
                    material,
                    parent,
                    tint_for(index, worn),
                    bevel,
                ))
                index += 1
                x += block_size[0] + gap
            y += block_size[1] + gap
        z += block_size[2] + gap
        course += 1
    return made


def voussoirs(parent, prefix, center_x, spring, inner_radius, thickness, depth, count, material):
    """A semicircular ring in YZ. Length follows the arch so the joints are radial."""
    mid = inner_radius + thickness * 0.5
    arc = math.pi * mid / count
    made = []
    for i in range(count):
        angle = math.pi * (i + 0.5) / count
        y = -math.cos(angle) * mid
        z = spring + math.sin(angle) * mid
        made.append(block(
            "%s_%d" % (prefix, i),
            (depth, arc * 0.96, thickness),
            (center_x, y, z),
            material,
            parent,
            tint_for(i, i == count // 2),
            0.01,
            (math.pi * 0.5 - angle, 0.0, 0.0),
        ))
    return made


def join_by_material():
    """One mesh per material so Godot does not get a node per block.

    The editable blend can keep the blocks; call this on the open file just
    before export. Joining does not change the silhouette.
    """
    bpy.context.view_layer.update()
    groups = {}
    for obj in list(bpy.data.objects):
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
        bpy.context.view_layer.objects.active.name = name
