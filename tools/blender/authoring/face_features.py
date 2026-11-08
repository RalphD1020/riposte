"""The shared face-feature builder (FACE-MAPPING-001, FACE-EYE-001): an identity's eyes,
brows and dead-eye X built on any resolved head, for any character.

Placement is the mask's: a mark names an anchor (`face_mask.ANCHORS`) and its spacing;
the brow's bottom edge lies on the measured ridge line (`ridge_lines`, `_settle`), the eye
sits in the recessed eye panel at `eye_recess`. The eye assembly (`eye_assembly`) is
designed in the eye's own space and mapped here onto the head: every point is seated on
the head's surface under it and stood off along the eye's frame normal by its designed
depth, so the eye surface, iris and lids keep their designed layering on any head.

Every component carries its shared channels as relative shape keys (`eye_assembly.
COMPONENT_KEYS`): a key is the component rebuilt with that one channel at full weight, so
keys share the component's topology by construction and a preset is their weighted sum.

Called by `tools/blender/character_assembly.py` (a character candidate) and
`male_base_v2_variation.py` (the configurations); no entry point of its own.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
HEAD = "Head"
SIDES = (("L", 1.0), ("R", -1.0))
RAY_FROM_Y = -0.6
## Where the bevel starts, as a share of the mark's height off the panel.
BEVEL_SHOULDER = 0.35
## A mark's vertices are seated on the nearest surface within this reach (a ray along the
## mark's normal would strike the bridge's side wall beside a brow).
SEAT_REACH_M = 0.03
## An eye-assembly point is seated by a ray along -n from this far in front of its frame.
SEAT_RAY_M = 0.03
## Faces meeting at more than this angle keep a hard edge (the designed planes); softer
## turns shade smooth (soft edges, never a razor).
FACET_DEG = 32.0
## The face attribute holding each face's material slot (component order, eye_assembly.MATERIALS).
SLOT_ATTRIBUTE = "riposte_material_slot"


def _modules():
    sys.path.insert(0, os.path.join(ROOT, "tools", "character_modeling"))
    from character_modeling import eye_assembly, face_mask
    return face_mask, eye_assembly


def _mask_module():
    return _modules()[0]


def _frame(normal, sign, tilt):
    """Box axes on a panel: u across (outward for that side), v up, n out of the panel."""
    n = normal.normalized()
    u = Vector((0.0, 0.0, 1.0)).cross(n).normalized()
    if u.x * sign < 0.0:
        u = -u
    v = n.cross(u).normalized()
    if v.z < 0.0:
        v = -v
    ## A positive tilt raises the outer end on both sides (mirror-symmetric).
    turn = Matrix.Rotation(math.radians(tilt), 3, n)
    if tilt and ((turn @ u).z > 0.0) != (tilt > 0.0):
        turn = Matrix.Rotation(-math.radians(tilt), 3, n)
    return turn @ u, turn @ v, n


def _mark(name, hit, axes, size, mark, tree=None):
    """A designed feature, not a box: the mark's authored outline (u outward from the
    centre line, v up, both in -0.5..0.5 of its width and height) sunk into the surface,
    standing `proud_m` off it, with a bevelled top inset to `inset` of the outline so
    its depth reads as cut planes; with `tree` every vertex is seated on the surface
    under it."""
    u, v, n = axes
    w, h, d = size
    outline = mark["outline"]
    cx = sum(p[0] for p in outline) / len(outline)
    cy = sum(p[1] for p in outline) / len(outline)
    proud = mark["proud_m"]
    inset = mark.get("inset", 1.0)

    def seat(p):
        if tree is None:
            return p
        location = tree.find_nearest(p, SEAT_REACH_M)[0]
        return p if location is None else location

    def ring(scale, height):
        out = []
        for x, y in outline:
            across = cx + (x - cx) * scale
            p = hit + u * (across * w) + v * ((cy + (y - cy) * scale) * h)
            out.append(bm.verts.new(seat(p) + n * height))
        return out

    bm = bmesh.new()
    base = ring(1.0, proud - d)
    shoulder = ring(1.0, proud * BEVEL_SHOULDER)
    top = ring(inset, proud)
    bm.faces.new(list(reversed(base)))
    count = len(outline)
    for low, high in ((base, shoulder), (shoulder, top)):
        for k in range(count):
            bm.faces.new([low[k], low[(k + 1) % count], high[(k + 1) % count], high[k]])
    bm.faces.new(top)
    return _mesh_object(name, bm)


def _mesh_object(name, bm, facet=True):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    if facet:
        mesh.set_sharp_from_angle(angle=math.radians(FACET_DEG))
    obj = bpy.data.objects.new(name, mesh)
    obj["riposte_slot"] = "face"
    obj["riposte_bone"] = HEAD
    return obj


def _add_keys(obj, keys):
    """Relative shape keys on `obj`: {name: [world points]} in the object's vertex order."""
    if not keys:
        return
    obj.shape_key_add(name="Basis", from_mix=False)
    inverse = obj.matrix_world.inverted()
    for name, points in keys.items():
        key = obj.shape_key_add(name=name, from_mix=False)
        if len(points) != len(key.data):
            raise SystemExit("RIPOSTE_FACE: key %s on %s has %d points for %d vertices" % (name, obj.name, len(points), len(key.data)))
        for point, p in zip(key.data, points):
            point.co = inverse @ p


def _ridge_mark(name, tree, chart, columns, crease, mark, eye_assembly):
    """A ridge mark (a brow): a swept, variable cross-section attached by its bottom contour
    to the ridge line. Each resolved column (t, u, v_bottom, v_top, v_anchor) starts at the
    line at its u (`crease`) and goes along the surface by its offsets from the anchor (chart
    v times the chart height), each point on its own surface frame. The section from bottom
    to top: the lower face straight forward from the bottom contour (from the front it lies on
    the ridge line), a lower plane, the crest (at the mark's `section.crest` share of the
    height), an upper plane and a softened upper edge, standing `proud_m` times the
    section's `depth` along the column off the surface and sinking `depth_m` into it. Faces
    meeting sharper than FACET_DEG keep their plane; the rest shade smooth. Its channels
    (`eye_assembly.BROW_CHANNELS`) are shape keys: the brow rebuilt with that channel."""
    face_mask = _mask_module()
    height = chart[1]
    proud, sunk = mark["proud_m"], mark["depth_m"]
    section = mark["section"]
    up, forward = Vector((0.0, 0.0, 1.0)), Vector((0.0, -1.0, 0.0))

    def along(start, offset):
        p, normal = start, None
        steps = max(1, int(abs(offset) / 0.002) + 1)
        for _k in range(steps):
            p, normal, _i, _d = tree.find_nearest(p + up * (offset / steps))
        if normal is None:
            p, normal, _i, _d = tree.find_nearest(p)
        return p, (-normal if normal.y > 0.0 else normal)

    def seat(p):
        location, normal, _i, _d = tree.find_nearest(p)
        return location, (-normal if normal.y > 0.0 else normal)

    def points(channel=None):
        out = []
        for t, u, bottom, top, anchor in columns:
            d_bottom, d_top, d_depth, inward = eye_assembly.brow_delta(channel, t) if channel else (0.0, 0.0, 0.0, 0.0)
            c = crease(max(0.0, u - inward))
            b, nb = along(c, (bottom - anchor) * height + d_bottom)
            e, ne = along(c, (top - anchor) * height + d_top)
            depth = proud * face_mask._interpolate(section["depth"], t) * (1.0 + d_depth)
            crest = face_mask._interpolate(section["crest"], t)
            column = [b + forward * -sunk, b + forward * (depth * section["lower_edge"])]
            for share, scale in ((crest * 0.45, 0.88), (crest, 1.0), (crest + (1.0 - crest) * 0.55, 0.82)):
                p, n = seat(b.lerp(e, share))
                column.append(p + n * depth * scale)
            column += [e + ne * (depth * section["upper_edge"]), e + ne * -sunk]
            out.append(column)
        return out

    rest = points()
    rows = len(rest[0])
    bm = bmesh.new()
    verts = [[bm.verts.new(p) for p in column] for column in rest]
    for a, b in zip(verts, verts[1:]):
        for k in range(rows - 1):
            bm.faces.new([a[k], b[k], b[k + 1], a[k + 1]])
    for cap in (verts[0], verts[-1]):
        bm.faces.new(cap)
    obj = _mesh_object(name, bm)
    order = [p for column in rest for p in column]
    _add_keys(obj, {channel: [p for column in points(channel) for p in column] for channel in eye_assembly.BROW_CHANNELS})
    if len(order) != len(obj.data.vertices):
        raise SystemExit("RIPOSTE_FACE: brow %s lost vertices" % name)
    return obj


class _EyeFrame:
    """The eye's frame on the head: its centre, axes and scale; `at(x, y, depth)` is a design
    point seated on the head surface under it and stood `depth` off along the normal."""

    def __init__(self, tree, hit, axes, width_m, height_m):
        self.tree, self.hit = tree, hit
        self.u, self.v, self.n = axes
        self.width_m, self.height_m = width_m, height_m

    def at(self, x, y, depth):
        base = self.hit + self.u * (x * self.width_m) + self.v * (y * self.height_m)
        location, _normal, _i, _d = self.tree.ray_cast(base + self.n * SEAT_RAY_M, -self.n, SEAT_RAY_M * 2.0)
        if location is None:
            location = self.tree.find_nearest(base)[0]
        return location + self.n * depth


def _layer(name, frame, design, keys, flat=True):
    """A graphic layer: `design(weights)` -> (points [(x, y, depth)], faces, face material
    slots), every point seated on the head (`frame.at`); its channels' shape keys are the
    layer redrawn with that channel alone, so they share its topology by construction."""
    points, faces, materials = design({})
    bm = bmesh.new()
    verts = [bm.verts.new(frame.at(*p)) for p in points]
    bm.verts.ensure_lookup_table()
    for f in faces:
        bm.faces.new([verts[i] for i in f])
    obj = _mesh_object(name, bm, facet=False)
    ## An open sheet has no outside for `recalc_face_normals` to find: a layer faces the eye
    ## frame's normal (the taller fixed white came out facing the head, shaded dark).
    if sum((p.normal.dot(frame.n) for p in obj.data.polygons)) < 0.0:
        for polygon in obj.data.polygons:
            polygon.flip()
    if flat:
        ## A drawing, not a form: one even tone per layer. Seated on a faceted head, each
        ## column's own normal would shade it in bands; the layer takes the eye frame's one
        ## normal instead.
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
        obj.data.normals_split_custom_set_from_vertices([tuple(frame.n)] * len(obj.data.vertices))
    ## A face's material slot is applied once the slots exist (`character_assembly.
    ## dress_face`); a mesh without slots would clamp it to 0.
    slots = obj.data.attributes.new(SLOT_ATTRIBUTE, "INT", "FACE")
    slots.data.foreach_set("value", list(materials))
    _add_keys(obj, {k: [frame.at(*p) for p in design({k: 1.0})[0]] for k in keys})
    return obj


def _strip_faces(columns, rows, offset=0):
    return [[offset + i * rows + k, offset + (i + 1) * rows + k, offset + (i + 1) * rows + k + 1, offset + i * rows + k + 1]
            for i in range(columns - 1) for k in range(rows - 1)]


## Rows of the eye white from its lower edge to its upper: enough that a tall aperture on
## the recessed panel follows the face's curve under the seated iris (with three rows its
## faces were chords standing off the surface the iris sits on, measured 2026-11-01).
WHITE_ROWS = 7
## Rows of a masked eye's fixed white backing: taller than any aperture and without keys, it
## takes the rows it needs to stay off the panel between its vertices (with seven rows its
## faces came within 0.02 mm of the head, measured 2026-11-06).
BACKING_ROWS = 15


def _eye_white(name, frame, profile, eye_assembly):
    """The eye-white shape (the aperture; a masked eye's fixed backing): columns from the
    lower edge to the upper, in rows enough that the drawing follows the face's curve."""
    depth = profile["depth"]["white_m"]
    rows = BACKING_ROWS if eye_assembly.fixed_white(profile) else WHITE_ROWS

    def design(weights):
        strip = eye_assembly.white_strip(profile, weights)
        points = [(x, lo + (hi - lo) * k / (rows - 1), depth) for x, lo, hi in strip for k in range(rows)]
        faces = _strip_faces(len(strip), rows)
        return points, faces, [0] * len(faces)
    return _layer(name, frame, design, eye_assembly.component_keys(profile, "eye"))


def _iris(name, frame, profile, side, eye_assembly):
    """The iris layer, clipped to the aperture: the darker rim (`iris_rim`), the iris, the
    pupil and the highlight, each a little proud of the one under it."""
    d = profile["depth"]
    n = eye_assembly.IRIS_RAYS

    def design(weights):
        shape = eye_assembly.iris_shape(profile, side, weights)
        points = [(x, y, d["iris_m"]) for x, y in shape["iris"] + shape["rim"]]
        points += [(x, y, d["pupil_m"]) for x, y in shape["pupil"] + [shape["pupil_centre"]]]
        points += [(x, y, d["catchlight_m"]) for x, y in shape["catchlight"]]
        faces, materials = [], []
        for ring, slot in ((0, 0), (n, 1)):
            for k in range(n):
                k1 = (k + 1) % n
                faces.append([ring + k, ring + k1, ring + n + k1, ring + n + k])
                materials.append(slot)
        g = 3 * n + 1
        if profile.get("occlusion") != eye_assembly.MASK:
            for k in range(n):
                faces.append([2 * n + k, 2 * n + (k + 1) % n, 3 * n])
                materials.append(2)
        else:
            ## A masked eye's large pupil in PUPIL_RINGS concentric rings (appended after
            ## the highlight, so every other index is the clipped eye's), so it follows the
            ## panel's curve instead of cutting chords under the white.
            cx, cy = shape["pupil_centre"]
            rings = [2 * n] + [g + 4 + r * n for r in range(len(PUPIL_RINGS))]
            for t in PUPIL_RINGS:
                points += [(cx + (x - cx) * t, cy + (y - cy) * t, d["pupil_m"]) for x, y in shape["pupil"]]
            for a, b in zip(rings, rings[1:]):
                for k in range(n):
                    faces.append([a + k, a + (k + 1) % n, b + (k + 1) % n, b + k])
                    materials.append(2)
            for k in range(n):
                faces.append([rings[-1] + k, rings[-1] + (k + 1) % n, 3 * n])
                materials.append(2)
        faces.append([g, g + 1, g + 2, g + 3])
        materials.append(3)
        return points, faces, materials
    return _layer(name, frame, design, eye_assembly.component_keys(profile, "iris"))


## A masked pupil's inner rings (shares of its radius).
PUPIL_RINGS = (0.75, 0.5, 0.25)


def _lash_line(name, frame, profile, eye_assembly):
    """The graphic lines: the upper lash line riding the upper edge with its pointed outer
    wing and inner tip, and the short accent under the outer corner."""
    depth = profile["depth"]["line_m"]

    def design(weights):
        line = eye_assembly.lash_line(profile, weights)
        upper, accent = line["upper"], line["accent"]
        points = [(x, y, depth) for x, lo, hi in upper for y in (lo, hi)]
        faces = _strip_faces(len(upper), 2)
        last = 2 * (len(upper) - 1)
        wing = len(points)
        points.append((line["wing"][0], line["wing"][1], depth))
        faces.append([last, wing, last + 1])
        tip = len(points)
        points.append((line["tip"][0], line["tip"][1], depth))
        faces.append([tip, 0, 1])
        base = len(points)
        points += [(x, y, depth) for x, top, bottom in accent for y in (bottom, top)]
        faces += _strip_faces(len(accent), 2, base)
        return points, faces, [0] * len(faces)
    return _layer(name, frame, design, eye_assembly.component_keys(profile, "line"))


def _eye_assembly(prefix_side, tree, hit, axes, mark, side, chart, eye_assembly):
    """The anime eye's layers of one eye: {component: object}."""
    _low, height, half_width = chart
    frame = _EyeFrame(tree, hit, axes, mark["width"] * half_width, mark["height"] * height)
    names = eye_assembly.COMPONENTS
    made = {"eye": _eye_white("%s.%s" % (names["eye"], side), frame, mark, eye_assembly),
            "iris": _iris("%s.%s" % (names["iris"], side), frame, mark, side, eye_assembly),
            "line": _lash_line("%s.%s" % (names["line"], side), frame, mark, eye_assembly)}
    if mark.get("occlusion") == eye_assembly.MASK:
        made["mask"] = _eye_mask("%s.%s" % (names["mask"], side), frame, mark, eye_assembly)
    return made


## Rows of each band of the eye mask, from the aperture's edge to its outer bound: enough
## that its faces follow the panel's curve over the seated iris (with four rows a band's
## chords passed through the pupil, measured 2026-11-01).
MASK_ROWS = 16


def _eye_mask(name, frame, profile, eye_assembly):
    """The eye mask (occlusion "mask"): a skin layer above the iris and below the lash line,
    a band over the aperture's upper edge and one under its lower edge, so the round iris
    shows only through the aperture. Dense and seated on the head, it shades smoothly from
    its own surface as the smooth-shaded head does (faces turned outward), so it reads as the
    face, never as a lid."""
    depth = profile["depth"]["mask_m"]

    def design(weights):
        strip = eye_assembly.mask_strip(profile, weights)
        points, faces = [], []
        for band in ("upper", "lower"):
            base = len(points)
            points += [(x, a + (b - a) * k / (MASK_ROWS - 1), depth) for x, a, b in strip[band] for k in range(MASK_ROWS)]
            faces += _strip_faces(len(strip[band]), MASK_ROWS, base)
        return points, faces, [0] * len(faces)
    obj = _layer(name, frame, design, eye_assembly.component_keys(profile, "mask"), flat=False)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    obj.data.update()
    return obj


def _anchor_lines(anchor, sign):
    face_mask = _mask_module()
    return [[n if sign > 0 else face_mask.mirrored(n) for n in line] for line in face_mask.ANCHORS[anchor]]


def ridge_controls(face_controls, head, anchor="brow_ridge", parameters=None):
    """{name: (u, world point)} of the anchor's control lines on both sides of `head`, from
    `face_controls` (`male_base_v2.face_controls`): the ridge's crest on the head's own
    vertices."""
    face_mask = _mask_module()
    names = [n for sign in (1.0, -1.0) for line in _anchor_lines(anchor, sign) for n in line]
    points = face_controls(head, names, parameters)
    controls = face_mask.control_points(parameters)
    return {n: (controls[n][0], points[n]) for n in names}


## The ridge line (FACE-MAPPING-001): where the surface turns from facing up to facing
## down (the smooth-shaded normal's z crosses HORIZON_Z), the ridge's most forward point
## in profile — the line the eye reads as the brow ridge on a softened ridge. Found from
## the crest, per sample of u (HORIZON_SAMPLE_U apart, and every control vertex), walking
## the surface in HORIZON_STEP_M steps no further than HORIZON_REACH_M.
HORIZON_Z = 0.0
HORIZON_SAMPLE_U = 0.01
HORIZON_STEP_M = 0.0005
HORIZON_REACH_M = 0.015


def _smooth_surface(head):
    """`at(p)`: the nearest point on `head` and its smooth-shaded normal there (vertex
    normals interpolated across the triangle), outward."""
    from mathutils.interpolate import poly_3d_calc
    mesh = head.data
    mesh.calc_loop_triangles()
    world, rotation = head.matrix_world, head.matrix_world.to_3x3()
    points = [world @ v.co for v in mesh.vertices]
    normals = [(rotation @ v.normal).normalized() for v in mesh.vertices]
    triangles = [tuple(t.vertices) for t in mesh.loop_triangles]
    tree = BVHTree.FromPolygons(points, triangles)

    def at(p):
        location, _normal, index, _distance = tree.find_nearest(p)
        corners = triangles[index]
        weights = poly_3d_calc([points[i] for i in corners], location)
        return location, sum((normals[i] * w for i, w in zip(corners, weights)), Vector()).normalized()
    return at


## A settle is walked down the surface in steps this long.
SETTLE_STEP_M = 0.00025


def _settle(tree, point, distance):
    """`point` (on the surface) walked `distance` down the surface (arc length along the
    head, each step re-seated on it), never a world height: a brow's `settle_m`, its bottom
    edge seated just under the ridge line so the ridge reads above it."""
    here = tree.find_nearest(point)[0]
    travelled = 0.0
    while travelled < distance:
        step = min(SETTLE_STEP_M, distance - travelled)
        there = tree.find_nearest(here - Vector((0.0, 0.0, step)))[0]
        moved = (there - here).length
        if moved == 0.0:
            break
        travelled += moved
        here = there
    return here


def _horizon(at, crest):
    """The ridge line under (or over) the crest point: where the normal's z crosses HORIZON_Z;
    where the surface never turns within reach (the bridge's edge, where the ridge meets the
    nose) the line is the crest itself."""
    p, n = at(crest)
    down = n.z > HORIZON_Z
    step = Vector((0.0, 0.0, -HORIZON_STEP_M if down else HORIZON_STEP_M))
    for _k in range(int(HORIZON_REACH_M / HORIZON_STEP_M)):
        q, m = at(p + step)
        if (m.z <= HORIZON_Z) == down:
            share = (n.z - HORIZON_Z) / (n.z - m.z) if n.z != m.z else 0.0
            return p.lerp(q, share)
        p, n = q, m
    return at(crest)[0]


def ridge_lines(face_controls, head, anchor="brow_ridge", parameters=None):
    """{sign: [(u, world point)]}: the ridge line on each side of `head`, sampled from the
    anchor's start (the bridge's top corner) to its end, a ridge mark's bottom edge."""
    face_mask = _mask_module()
    controls = ridge_controls(face_controls, head, anchor, parameters)
    at = _smooth_surface(head)
    out = {}
    for sign in (1.0, -1.0):
        crest = [(abs(controls[n][0]), controls[n][1]) for line in _anchor_lines(anchor, sign) for n in line]
        crest.sort(key=lambda c: c[0])
        start, end = crest[0][0], crest[-1][0]
        us = sorted({round(start + k * HORIZON_SAMPLE_U, 9) for k in range(int((end - start) / HORIZON_SAMPLE_U) + 1)}
                    | {round(u, 9) for u, _p in crest})
        out[sign] = [(u, _horizon(at, face_mask.line_at(crest, u))) for u in us]
    return out


def head_of(obj):
    """Any head object (the approved `HeadV2`, a resolved profile): its faces as a BVH, in
    world space. The chart frame (low, height, half-width) is passed separately, so marks
    keep the character's identity placement while their depth comes from this surface."""
    points = [obj.matrix_world @ v.co for v in obj.data.vertices]
    return BVHTree.FromPolygons(points, [list(p.vertices) for p in obj.data.polygons])


def place_marks(collection, tree, low, height, half_width, marks, eye_spacing_u=0.0, brow_tilt_deg=0.0, offset_x=0.0,
                mask_parameters=None, ridge=None):
    """The identity's eye assemblies, brows and dead-eye X on the head surface `tree` (x a
    chart fraction of `half_width`; the height, tilt and a brow's columns from each mark's
    anchor on the mask, `face_mask.resolve_marks`, for the head's `mask_parameters`).
    `eye_spacing_u` moves eyes, brows and the X apart (chart units); `brow_tilt_deg` adds to
    the brows' own tilt (identity only). `ridge`: {sign: [(u, world point)]}, the ridge line
    a brow's bottom edge lies on (`ridge_lines`). Returns [(object, component, side)]."""
    face_mask, eye_assembly = _modules()
    shifted = {kind: dict(mark, x=mark["x"] + eye_spacing_u) for kind, mark in marks.items()}
    if brow_tilt_deg:
        shifted["Brow"]["tilt_deg"] = shifted["Brow"].get("tilt_deg", 0.0) + brow_tilt_deg
    problems = eye_assembly.profile_problems(shifted["Eye"])
    if problems:
        raise SystemExit("RIPOSTE_FACE: " + "; ".join(problems))
    marks = face_mask.resolve_marks(shifted, height / half_width, mask_parameters)
    chart = (low, height, half_width)
    made = []
    for side, sign in SIDES:
        eye = marks["Eye"]
        hit, normal = _place(tree, low, height, half_width, eye, sign, offset_x)
        tilt = eye.get("tilt_by_side", {}).get(side, eye["tilt_deg"])
        for component, obj in _eye_assembly(side, tree, hit, _frame(normal, sign, tilt), eye, side, chart, eye_assembly).items():
            made.append((obj, component, side))
        brow = marks["Brow"]

        def crease(u, line=ridge[sign], settle=brow.get("settle_m", 0.0)):
            return _settle(tree, face_mask.line_at(line, u), settle)
        made.append((_ridge_mark("Brow.%s" % side, tree, chart, brow["columns"][side], crease, brow, eye_assembly), "brow", side))
    dead = marks["DeadEye"]
    line = dead.get("chord_deg", 0.0)
    for side, sign in SIDES:
        hit, normal = _place(tree, low, height, half_width, dead, sign, offset_x)
        for bar, turn in (("A", 1.0), ("B", -1.0)):
            axes = _frame(normal, sign, line + (dead["tilt_deg"] - line) * turn)
            size = (dead["width"] * half_width, dead["height"] * height, dead["depth_m"])
            made.append((_mark("DeadEye.%s.%s" % (side, bar), hit, axes, size, dead, tree), "dead", side))
    for obj, _component, _side in made:
        collection.objects.link(obj)
    return made


def _place(tree, low, height, half_width, mark, sign, offset_x=0.0):
    target = Vector((offset_x + sign * mark["x"] * half_width, RAY_FROM_Y, low + mark["z"] * height))
    hit, normal, _index, _distance = tree.ray_cast(target, Vector((0.0, 1.0, 0.0)))
    if hit is None:
        raise SystemExit("RIPOSTE_FACE: no panel under %s" % (target,))
    if normal.y > 0.0:
        normal = -normal
    return hit, normal
