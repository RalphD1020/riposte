"""The foundation's ears on a resolved head (`character_modeling.ear`): both sides built in
the head's own frame — the root found on the head's surface at the `ear_root` depth, the
size from the head's chart height — skin material, rigid on Head, shaded smooth."""

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "character_modeling"))
from character_modeling import ear  # noqa: E402

HEAD_BONE = "Head"
ROOT_GROUP = "EarRoot"
ROOT_NORMAL_M = 0.003


def _tree(obj):
    points = [obj.matrix_world @ v.co for v in obj.data.vertices]
    return points, BVHTree.FromPolygons(points, [list(p.vertices) for p in obj.data.polygons])


def root_of(head, chart, sign):
    """(root point on the head's side, ear height m) for the side `sign` (+1 left)."""
    low, height, half_width = chart
    points, tree = _tree(head)
    z = low + 0.5 * (ear.EAR_TOP_V + ear.EAR_BOTTOM_V) * height
    band = [p for p in points if abs(p.z - z) < 0.1 * height]
    front, back = min(p.y for p in band), max(p.y for p in band)
    y = 0.5 * (front + back) + ear.ROOT_DEPTH_OFFSET * (back - front)
    hit, _normal, _index, _distance = tree.ray_cast(Vector((sign * (half_width + 0.5), y, z)), Vector((-sign, 0.0, 0.0)))
    if hit is None:
        raise SystemExit("RIPOSTE_EAR: no head surface at the ear root (side %+d)" % sign)
    return hit, ear.EAR_HEIGHT * height


def build_ears(head, chart, collection, prefix, material, flare_deg=ear.FLARE_DEG, scale=1.0):
    """Ear.L and Ear.R on `head`, linked into `collection`, `scale` times the ear height about
    its root (which stays on the skull); returns the objects."""
    points, quads, tris = ear.grid(flare_deg=flare_deg)
    blend = ear.root_blend()
    rig = next((o for o in collection.objects if o.type == "ARMATURE"), None)
    lean = Matrix.Rotation(-math.radians(ear.TILT_DEG), 3, "X")
    up, forward = lean @ Vector((0.0, 0.0, 1.0)), lean @ Vector((0.0, -1.0, 0.0))
    made = []
    for side, sign in (("L", 1.0), ("R", -1.0)):
        root, size = root_of(head, chart, sign)
        size *= scale
        out = Vector((sign, 0.0, 0.0))
        anchor = root - forward * (ear.ROOT_A * size)
        _head_points, tree = _tree(head)
        verts = []
        for a, b, h in points:
            p = anchor + forward * (a * size) + up * (b * size) + out * (h * size)
            weight = ear.follow_weight(a)
            if weight > 0.0:
                ## The skull's side at this height and depth against the root's: the root
                ## edge follows it inward where the head narrows toward the face.
                hit = tree.ray_cast(Vector((sign * (abs(root.x) + 0.3), p.y, p.z)), -out)[0]
                if hit is not None:
                    p = p + out * ((hit.x - root.x) * sign * weight)
            verts.append(p)
        faces = [f if sign > 0 else f[::-1] for f in list(quads) + list(tris)]
        mesh = bpy.data.meshes.new("%s.Ear.%s" % (prefix, side))
        mesh.from_pydata([tuple(v) for v in verts], [], faces)
        mesh.validate()
        mesh.shade_smooth()
        obj = bpy.data.objects.new(mesh.name, mesh)
        obj.data.materials.append(material)
        collection.objects.link(obj)
        obj.vertex_groups.new(name=HEAD_BONE).add(list(range(len(verts))), 1.0, "REPLACE")
        ## Where the ear meets the skin it shades as the skin: on the attachment arc
        ## (`ear.root_blend`), the head's normals carried onto the ear within ROOT_NORMAL_M
        ## of the head's surface, fading to the ear's own.
        root = obj.vertex_groups.new(name=ROOT_GROUP)
        for i, (p, arc) in enumerate(zip(verts, blend)):
            if arc <= 0.0:
                continue
            location, normal, _i, _d = tree.find_nearest(p)
            if location is not None:
                weight = arc * (1.0 - min(1.0, abs((p - location).dot(normal)) / ROOT_NORMAL_M))
                if weight > 0.0:
                    root.add([i], weight, "REPLACE")
        transfer = obj.modifiers.new("RootNormals", "DATA_TRANSFER")
        transfer.object = head
        transfer.use_loop_data = True
        transfer.data_types_loops = {"CUSTOM_NORMAL"}
        transfer.loop_mapping = "POLYINTERP_NEAREST"
        transfer.vertex_group = ROOT_GROUP
        if rig is not None:
            obj.modifiers.new("Armature", "ARMATURE").object = rig
        made.append(obj)
    return made


def free_rim():
    """The ear's free-rim (helix) vertex indices (one topology for every ear): its outline
    where it is not attached."""
    ring = list(ear.outline_indices())
    return [ring[k] for k in range(len(ring)) if ear.attachment(k / len(ring)) == 0.0]


def ear_report(ears, head, hair=None):
    """Per ear, over the whole outline: the attachment arc's vertices (`ear.attachment` at
    least one half) standing outside the skull (a visible seam) and the arc's shallowest
    burial; the free rim's vertices inside the skull (a rim through the head); the share of
    the ear inside the skull; with `hair`, ear vertices inside the hair (an ear through the
    hairstyle)."""
    _points, tree = _tree(head)
    hair_tree = _tree(hair)[1] if hair is not None else None
    ring = list(ear.outline_indices())
    report = {}
    for obj in ears:
        world = [obj.matrix_world @ v.co for v in obj.data.vertices]
        depths = []
        for p in world:
            location, normal, _i, _d = tree.find_nearest(p)
            depths.append(-(p - location).dot(normal))
        arc = [(k, depths[i]) for k, i in enumerate(ring) if ear.attachment(k / len(ring)) >= 0.5]
        free = [(k, depths[i]) for k, i in enumerate(ring) if ear.attachment(k / len(ring)) == 0.0]
        through = None
        hair_cover = {}
        if hair_tree is not None:
            through = 0
            inside, near = [], []
            for p in world:
                hl, hn, _hi, hd = hair_tree.find_nearest(p)
                inside.append(hl is not None and -(p - hl).dot(hn) > 0.001)
                ## Behind a face this near, and within its footprint, is inside the hair;
                ## further away, or beside an open edge (the nearest point on the edge:
                ## an offset across the normal), the face's side says nothing.
                under = inside[-1] and (p - hl).normalized().dot(-hn) > EAR_UNDER_COS
                near.append(under and hd < EAR_INSIDE_REACH_M)
            through = sum(inside)
            inside = near
            hair_cover = _hair_cover(obj, world, depths, inside, ring, free, hair_tree)
        report[obj.name] = dict({"vertices": len(world), "inside_head_share": round(sum(d > 0.0 for d in depths) / len(world), 3),
                                 "attachment_gap_vertices": sum(d <= 0.0 for _k, d in arc),
                                 "attachment_min_burial_mm": round(min(d for _k, d in arc) * 1000, 2),
                                 "free_rim_inside_vertices": sum(d > 0.0 for _k, d in free),
                                 "inside_hair_vertices": through}, **hair_cover)
    return report


## The ear as a facing cue (HAIR-FIT): seen from beside the head, level and from the match
## camera's pitch, how much of the ear standing outside the skull the hair hides.
EAR_VIEW_PITCH_DEG = (0.0, 48.0)
EAR_INSIDE_REACH_M = 0.01
EAR_UNDER_COS = 0.85


def _hair_cover(obj, world, depths, inside, ring, free, hair_tree):
    """Free-rim (helix) vertices inside the hair, and the share of the ear's visible
    vertices (outside the skull) hidden behind hair from beside, per view pitch."""
    sign = 1.0 if obj.name.endswith(".L") else -1.0
    rim = {ring[k] for k, _d in free}
    visible = [i for i, d in enumerate(depths) if d <= 0.0]
    hidden = {}
    for pitch in EAR_VIEW_PITCH_DEG:
        a = math.radians(pitch)
        view = Vector((sign * math.cos(a), 0.0, math.sin(a)))
        blocked = sum(1 for i in visible if hair_tree.ray_cast(world[i] + view * 0.0005, view, 0.3)[0] is not None)
        hidden["%d" % pitch] = round(blocked / max(1, len(visible)), 3)
    return {"helix_inside_hair_vertices": sum(1 for i in rim if inside[i]),
            "visible_ear_hidden_by_hair": hidden}
