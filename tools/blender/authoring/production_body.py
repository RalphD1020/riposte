"""F8 production body (Milestone D): one connected, mirrored, deformation-ready body fitted to the
pinned processed default (RETOPOLOGY-REFERENCE-001), never to the raw BodyV2 sculpt.

Every region is built in this one build from the one observed reference, so no region can fit
a different body revision. The construction (the +X half; centre columns on x = 0):

- trunk: rings of 13 columns (front centre c0, side c6, back centre c12) from the leg sockets
  up through the waist and chest to the neck (whose top stays open inside the separate HeadV2);
- shoulders: an 8-edge armhole in the side of the chest rings (rim on the armpit's bottom, the
  pectoral and latissimus folds and the shoulder cap, every point cast where its first hit is
  the surface meant: the approved body folds through itself at the posterior axilla), the arm's
  8-vertex loops perpendicular to its bones, denser across the elbow, through the wrist to a
  quad-capped hand;
- pelvis: a 16-edge leg socket opening downward — its front edge follows the inguinal crease
  diagonally from the groin up to the front of the hip, its back edge the gluteal fold — with
  three midline points (groin front, crotch apex at the thighs' separation, buttock-cleft base)
  shared by both legs as one perineum strip (the sculpt's crotch is a zero-width slit, so the
  crotch is defined, never traced); a loop each side of the crease gives the fold room to close;
- legs: 16-vertex loops perpendicular to the bones, denser across the knee, a turning ankle and
  a quad-capped foot.
Then one Catmull-Clark level; only the +X half is seated on the reference's outer surface (rays
inward from just outside, accepted when the hit faces the same way) and the -X half is its exact
mirror, so the body is symmetric by construction.

    blender -b --factory-startup --python production_body.py -- --scene <junction.blend>
        (--pin-out <pin.json> --foundation <foundation.json> | --pin <pin.json> --out <dir>)
        [--target RetopoTarget] [--rig WolfRigNeutral]
`--pin-out` observes the approved reference and writes its pin; `--pin` builds, and refuses to
fit anything when the observed inputs are not the pinned ones."""
import argparse
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "character_modeling"))
sys.path.insert(0, os.path.join(ROOT, "tools", "blender"))
from character_modeling import ownership, retopology_reference, symmetry  # noqa: E402

COLUMNS = 13
ARM_SIDES = 8
LEG_SIDES = 16
## The approved body's creases, measured on the reference (`_selfx.py`, `_pelvis_probe.py`):
## the posterior-axilla fold's top and the height where the thighs separate.
AXILLA_FOLD_TOP_Z = 1.267
THIGH_SEPARATION_Z = 0.785
## Trunk ring heights (m), bottom to top, above the leg sockets.
PELVIS_Z = (0.94, 1.00)
WAIST_Z = (1.06, 1.12, 1.18)
CHEST_Z = {"mid": 1.355, "line": 1.415, "neck_base": 1.47}
NECK_Z = (1.51, 1.55, 1.585)
## The leg socket's height per column, front centre to back centre: low at the groin, rising
## along the inguinal crease to the front of the hip, level over the trochanter, descending to
## the gluteal fold behind.
SOCKET_Z = (0.83, 0.845, 0.865, 0.885, 0.9, 0.905, 0.9, 0.885, 0.865, 0.845, 0.83, 0.83, 0.83)
## Arm loops along joint->elbow. Concentrating extra hinge loops here (d7, UA .8/.88/.94/.98 +
## FA .02/.06/.12) cut the 120-deg penetration 26->22 mm but RAISED collapsed faces 6->16 and
## left the supported guard elbow unchanged (18.8->18.4 mm): the elbow fold is a weight problem,
## not a loop-density one (ALIGN 'wrong when posed' -> weights before topology). Loops kept at d6.
UPPER_ARM_T = (0.25, 0.4, 0.55, 0.7, 0.82, 0.9, 0.96)
## Deltoid cap rings: shares of the way from the armhole rim to the first arm loop. Each ring is
## SEATED on the reference by radial casting from a swept interior centre (the way the arm loops
## and trunk rings are seated), not the earlier inward lerp-cast toward the joint which rippled
## the deltoid top (`board_shoulder_smooth_d3_vs_d5.png`). This is the v1 CAP_RINGS move — the
## deltoid flows from the socket into the upper arm instead of one bridge row spanning the gap.
DELTOID_CAP_SHARES = (0.33, 0.66)
FOREARM_T = (0.04, 0.1, 0.2, 0.4, 0.6, 0.8, 0.94)
## The hand is the reference's own form: a 9 cm closed fist on the rig's single Hand bone (no
## finger bones, no finger geometry to trace). These loops and the cap hold it within 5.7 mm
## everywhere (the knuckle face's rim is that much softer; `_gap_where.py`), so D1 added no
## loop. A wrist bends; it never twists (`_wrist_untwist.py`): there is no twist support here.
HAND_T = (0.25, 0.55, 0.8)
UPPER_LEG_T = (0.27, 0.4, 0.55, 0.7, 0.82, 0.9, 0.96)
LOWER_LEG_T = (0.04, 0.1, 0.2, 0.4, 0.6, 0.8, 0.92)
## Foot loops: shares of the way from the ankle turn's pivot plane to the toe bone's tip.
FOOT_STEPS = (0.0, 0.4, 0.8)
## The ankle turn: ring planes at these angles (from the shin's horizontal toward the foot's
## vertical) about a lateral pivot this far in front of the ankle's front surface, each ring
## cast from a centre this deep into the ankle along its plane.
ANKLE_TURN_DEG = (30.0, 60.0)
## 6 mm bunched the turning rings' instep vertices (spacing ~ clearance x 30 deg); 15 mm
## spreads them ~8 mm apart.
ANKLE_PIVOT_CLEARANCE_M = 0.015
ANKLE_RING_DEPTH_M = 0.05
MEDIAL_MIN_X = 0.003
SEAT_OUT, SEAT_REACH = 0.02, 0.03
NON_DEFORMING = ("Root", "SwordMount")
FRAME = retopology_reference.FRAME


def _arguments():
    p = argparse.ArgumentParser()
    p.add_argument("--scene", required=True)
    p.add_argument("--target", default="RetopoTarget")
    p.add_argument("--rig", default="WolfRigNeutral")
    p.add_argument("--pin")
    p.add_argument("--pin-out")
    p.add_argument("--foundation")
    p.add_argument("--rig-contract", default="f724fd9d49bb84c2caeb34102bbadb5f2a0b671e07cae6d722408ebd3ff67bd2")
    p.add_argument("--out")
    p.add_argument("--weights", choices=("transfer", "heat"), default="transfer")
    p.add_argument("--weight-source", default="WeightSource")
    p.add_argument("--no-shoulder-fix", dest="shoulder_fix", action="store_false")
    return p.parse_args(sys.argv[sys.argv.index("--") + 1:])


def observe(target, rig):
    """The builder's view of its inputs: the target's evaluated world mesh, the rig's rest, and
    each clip evaluated through the rig (largest bone displacement at its middle frame)."""
    deps = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(target.evaluated_get(deps))
    me.transform(target.matrix_world)
    vertices = [tuple(v.co) for v in me.vertices]
    faces = [tuple(p.vertices) for p in me.polygons]
    bpy.data.meshes.remove(me)
    bones = [(b.name, b.parent.name if b.parent else None, tuple(rig.matrix_world @ b.head_local), tuple(rig.matrix_world @ b.tail_local))
             for b in rig.data.bones]
    rig.animation_data_create()
    motion = {}
    for action in bpy.data.actions:
        rig.animation_data.action = action
        if getattr(action, "slots", None):
            rig.animation_data.action_slot = action.slots[0]
        start, end = action.frame_range
        bpy.context.scene.frame_set(int(round(0.5 * (start + end))))
        bpy.context.view_layer.update()
        worst = 0.0
        for pb in rig.pose.bones:
            worst = max(worst, (pb.head - pb.bone.head_local).length, (pb.tail - pb.bone.tail_local).length)
        motion[action.name] = worst
    rig.animation_data.action = None
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    return retopology_reference.observe(vertices, faces, target.name, bones, motion, FRAME)


class Fit:
    """Ray casts on the one reference."""

    def __init__(self, target):
        self.tree = BVHTree.FromObject(target, bpy.context.evaluated_depsgraph_get())

    def cast(self, origin, direction):
        hit = self.tree.ray_cast(origin, direction.normalized())[0]
        if hit is None:
            raise SystemExit("RIPOSTE_BODY: no surface from %s along %s" % (tuple(origin), tuple(direction)))
        return hit

    def radial_out(self, z, c, centre_y=0.0):
        t = math.radians(180.0 * c / (COLUMNS - 1))
        p = self.cast(Vector((0.0, centre_y, z)), Vector((math.sin(t), -math.cos(t), 0.0)))
        if c in (0, COLUMNS - 1):
            p.x = 0.0
        return p

    def radial_in(self, z, c):
        t = math.radians(180.0 * c / (COLUMNS - 1))
        d = Vector((math.sin(t), -math.cos(t), 0.0))
        p = self.cast(Vector((0.0, 0.0, z)) + d * 0.6, -d)
        if c in (0, COLUMNS - 1):
            p.x = 0.0
        return p

    def loop(self, centre, axis, sides, reference=Vector((0.0, 0.0, 1.0)), medial_min=None):
        axis = axis.normalized()
        up = reference - axis * axis.dot(reference)
        if up.length < 1e-6:
            up = Vector((0.0, -1.0, 0.0)) - axis * axis.dot(Vector((0.0, -1.0, 0.0)))
        up.normalize()
        side = axis.cross(up)
        out = []
        for k in range(sides):
            a = 2.0 * math.pi * k / sides
            p = self.cast(centre, up * math.cos(a) + side * math.sin(a))
            if medial_min is not None:
                p.x = max(p.x, medial_min)
            out.append(p)
        return out

    def mid_height(self, x, y, below, above):
        """The middle of the body's vertical extent at (x, y) between two heights."""
        top = self.tree.ray_cast(Vector((x, y, above)), Vector((0, 0, -1)))[0]
        bottom = self.tree.ray_cast(Vector((x, y, below)), Vector((0, 0, 1)))[0]
        if top is None or bottom is None:
            raise SystemExit("RIPOSTE_BODY: no foot section at %.3f %.3f" % (x, y))
        return 0.5 * (top.z + bottom.z)


def bone(rig, name):
    b = rig.data.bones[name]
    return rig.matrix_world @ b.head_local, rig.matrix_world @ b.tail_local


class Builder:
    def __init__(self):
        self.bm = bmesh.new()

    def verts(self, points):
        return [self.bm.verts.new(p) for p in points]

    def quad(self, a, b, c, d):
        self.bm.faces.new([a, b, c, d])

    def bridge(self, a, b, closed=True, faces=True):
        """Quads between two equal rings, b rotated (and if needed reversed) to the least span;
        with `faces` False only the matched ring is returned (nothing is built)."""
        best = None
        for flip in (False, True):
            seq = list(reversed(b)) if flip else list(b)
            for s in range(len(seq)):
                rot = seq[s:] + seq[:s]
                cost = sum((x.co - y.co).length for x, y in zip(a, rot))
                if best is None or cost < best[0]:
                    best = (cost, rot)
        rot = best[1]
        n = len(a)
        for k in range(n if closed and faces else n - 1 if faces else 0):
            self.quad(a[k], a[(k + 1) % n], rot[(k + 1) % n], rot[k])
        return rot

    def cap(self, ring, fit, tip_axis):
        """A quad patch closing a ring of 4m vertices (m x m quads): interior points from the
        ring's Coons blend, cast onto the reference along the tip axis from outside."""
        n = len(ring)
        m = n // 4
        side = [[ring[(s * m + i) % n] for i in range(m + 1)] for s in range(4)]
        grid = [[None] * (m + 1) for _ in range(m + 1)]
        for i in range(m + 1):
            grid[0][i] = side[0][i]
            grid[i][m] = side[1][i]
            grid[m][m - i] = side[2][i]
            grid[m - i][0] = side[3][i]
        for r in range(1, m):
            for c in range(1, m):
                u, v = c / m, r / m
                p = ((1 - v) * grid[0][c].co + v * grid[m][c].co + (1 - u) * grid[r][0].co + u * grid[r][m].co
                     - ((1 - u) * (1 - v) * grid[0][0].co + u * (1 - v) * grid[0][m].co
                        + (1 - u) * v * grid[m][0].co + u * v * grid[m][m].co))
                hit = fit.tree.ray_cast(p + tip_axis * 0.05, -tip_axis)[0]
                grid[r][c] = self.bm.verts.new(hit if hit is not None else p)
        for r in range(m):
            for c in range(m):
                self.quad(grid[r][c], grid[r][c + 1], grid[r + 1][c + 1], grid[r + 1][c])


def build(target, rig):
    fit = Fit(target)
    b = Builder()
    joint, elbow = bone(rig, "UpperArm.L")
    _e, wrist = bone(rig, "Forearm.L")
    _w, hand_tip = bone(rig, "Hand.L")
    hip, knee = bone(rig, "UpperLeg.L")
    _k, ankle = bone(rig, "LowerLeg.L")
    _a, toe = bone(rig, "Foot.L")
    report = {}

    ## Trunk rings, bottom (leg socket) to top (neck).
    rings = []
    socket = [fit.radial_out(SOCKET_Z[c], c) for c in range(COLUMNS)]
    above = [fit.radial_out(0.5 * (SOCKET_Z[c] + PELVIS_Z[0]), c) for c in range(COLUMNS)]
    rings += [socket, above] + [[fit.radial_out(z, c) for c in range(COLUMNS)] for z in PELVIS_Z + WAIST_Z]
    armhole_bottom_z = AXILLA_FOLD_TOP_Z - 0.022
    rings.append([fit.radial_out(armhole_bottom_z, c) for c in range(COLUMNS)])
    mid = {c: fit.radial_in(CHEST_Z["mid"], c) for c in range(COLUMNS) if c not in (5, 6, 7)}
    line = {c: fit.radial_in(CHEST_Z["line"], c) for c in range(COLUMNS) if c not in (5, 6, 7)}
    fold_x = joint.x - 0.05
    mid[5] = fit.cast(Vector((fold_x, -0.6, CHEST_Z["mid"])), Vector((0, 1, 0)))
    mid[7] = fit.cast(Vector((fold_x, 0.6, CHEST_Z["mid"])), Vector((0, -1, 0)))
    cap_x = joint.x - 0.01
    line[5] = fit.cast(Vector((cap_x - 0.01, -0.6, CHEST_Z["line"] + 0.01)), Vector((0, 1, 0)))
    line[7] = fit.cast(Vector((cap_x - 0.01, 0.6, CHEST_Z["line"] + 0.01)), Vector((0, -1, 0)))
    line[6] = fit.cast(Vector((cap_x, joint.y, 2.0)), Vector((0, 0, -1)))
    rings += [[mid.get(c) for c in range(COLUMNS)], [line[c] for c in range(COLUMNS)]]
    rings += [[fit.radial_in(z, c) for c in range(COLUMNS)] for z in (CHEST_Z["neck_base"],) + NECK_Z]
    armhole_row = len(PELVIS_Z) + len(WAIST_Z) + 2
    V = [[b.bm.verts.new(p) if p is not None else None for p in ring] for ring in rings]
    hole = {(armhole_row, 5), (armhole_row, 6), (armhole_row + 1, 5), (armhole_row + 1, 6)}
    for r in range(len(V) - 1):
        for c in range(COLUMNS - 1):
            if (r, c) in hole:
                continue
            q = [V[r][c], V[r][c + 1], V[r + 1][c + 1], V[r + 1][c]]
            if all(q):
                b.quad(*q)
    rim = [V[armhole_row][5], V[armhole_row][6], V[armhole_row][7], V[armhole_row + 1][7],
           V[armhole_row + 2][7], V[armhole_row + 2][6], V[armhole_row + 2][5], V[armhole_row + 1][5]]

    ## The arm: armhole -> upper arm -> elbow -> forearm -> wrist -> hand, capped.
    arm = [fit.loop(joint.lerp(elbow, t), elbow - joint, ARM_SIDES) for t in UPPER_ARM_T]
    arm += [fit.loop(elbow.lerp(wrist, t), wrist - elbow, ARM_SIDES) for t in FOREARM_T]
    arm += [fit.loop(wrist.lerp(hand_tip, t), hand_tip - wrist, ARM_SIDES) for t in HAND_T]
    ## The deltoid cap (the established raised-arm construction, v1 CAP_RINGS): rings between
    ## the armhole and the first arm loop so the deltoid flows into the upper arm instead of
    ## one bridge row joining a socket to a tube. Each cap point lies between its matched rim
    ## and first-loop vertices, cast from outside along the joint's direction onto the outer
    ## surface (the posterior axilla folds through itself; an inside-out cast could land in it).
    first = b.verts(arm[0])
    matched = b.bridge(rim, first, faces=False)
    rim_c = sum((v.co for v in rim), Vector()) / len(rim)
    arm_c = sum((v.co for v in first), Vector()) / len(first)
    ring = rim
    for share in DELTOID_CAP_SHARES:
        centre = rim_c.lerp(arm_c, share)
        cap = []
        for r, f in zip(rim, matched):
            ## Outward radial direction interpolated from the rim's to the arm loop's, so the
            ## cap ring is seated on the deltoid the same way its neighbours are.
            d = (r.co - rim_c).normalized().lerp((f.co - arm_c).normalized(), share).normalized()
            hit = fit.tree.ray_cast(centre - d * 0.02, d, 0.3)[0]
            cap.append(b.bm.verts.new(hit if hit is not None else centre.lerp(f.co, 0.5)))
        ring = b.bridge(ring, cap)
    ring = b.bridge(ring, matched)
    report["armhole_rim"] = [[round(c, 4) for c in v.co] for v in rim]
    for loop in arm[1:]:
        ring = b.bridge(ring, b.verts(loop))
    b.cap(ring, fit, (hand_tip - wrist).normalized())

    ## The pelvis: socket + crotch midline (shared by both legs).
    top_slit = THIGH_SEPARATION_Z + 0.02
    front = fit.cast(Vector((0.0, -0.6, top_slit)), Vector((0, 1, 0)))
    back = fit.cast(Vector((0.0, 0.6, top_slit)), Vector((0, -1, 0)))
    front.x = back.x = 0.0
    apex = Vector((0.0, 0.5 * (front.y + back.y), THIGH_SEPARATION_Z))
    socket_ring = list(V[0]) + b.verts([back, apex, front])
    report["crotch"] = {"front": [round(c, 4) for c in front], "apex": [round(c, 4) for c in apex], "back": [round(c, 4) for c in back]}

    ## The leg: a crease loop under the socket, thigh, knee, shin, ankle turn, foot, capped.
    leg = [fit.loop(hip.lerp(knee, t), knee - hip, LEG_SIDES, Vector((0, -1, 0)), MEDIAL_MIN_X) for t in UPPER_LEG_T]
    first = b.verts(leg[0])
    ## The crease's lower support: each socket vertex and its matched first-loop vertex, the
    ## surface between them cast from the thigh's axis; two rows of quads span socket -> crease
    ## -> first loop.
    ring_first = b.bridge(socket_ring, first, faces=False)
    crease = []
    axis = (knee - hip).normalized()
    for s, l in zip(socket_ring, ring_first):
        m = 0.5 * (s.co + l.co)
        centre = hip + axis * axis.dot(m - hip)
        d = m - centre
        d -= axis * axis.dot(d)
        p = fit.cast(centre, d)
        ## Off the mirror plane: a crease vertex on it would merge with its mirror.
        p.x = max(p.x, MEDIAL_MIN_X)
        crease.append(b.bm.verts.new(p))
    n = len(socket_ring)
    for k in range(n):
        b.quad(socket_ring[k], socket_ring[(k + 1) % n], crease[(k + 1) % n], crease[k])
        b.quad(crease[k], crease[(k + 1) % n], ring_first[(k + 1) % n], ring_first[k])
    ring = ring_first
    for loop in leg[1:] + [fit.loop(knee.lerp(ankle, t), ankle - knee, LEG_SIDES, Vector((0, -1, 0))) for t in LOWER_LEG_T]:
        ring = b.bridge(ring, b.verts(loop))
    foot_axis = (toe - ankle).normalized()
    ## The ankle turns like a bent pipe: the rings between the last (horizontal) shin loop and
    ## the first (vertical) foot loop rotate about a lateral line just in front of the ankle, so
    ## their planes meet only outside the body (rings sharing a centre inside it cross).
    shin_z = knee.lerp(ankle, LOWER_LEG_T[-1]).z
    front_y = fit.cast(Vector((ankle.x, -0.6, shin_z)), Vector((0, 1, 0))).y
    pivot = Vector((ankle.x, front_y - ANKLE_PIVOT_CLEARANCE_M, shin_z))
    for phi in ANKLE_TURN_DEG:
        a = math.radians(phi)
        into = Vector((0.0, math.cos(a), -math.sin(a)))
        normal = Vector((1, 0, 0)).cross(into).normalized()
        centre = pivot + into * ANKLE_RING_DEPTH_M
        ring = b.bridge(ring, b.verts(fit.loop(centre, normal, LEG_SIDES, into)))
    ## The foot: vertical planes from the one through the pivot line (so every ring of the turn
    ## shares that line and none crosses another inside the foot) forward toward the toe.
    forward = Vector((0.0, -1.0, 0.0))
    for s in FOOT_STEPS:
        y = pivot.y + (toe.y - pivot.y) * s
        ## Probed from the pivot's height down: above it, in front of the ankle, the first
        ## surface would be the shin.
        centre = Vector((ankle.x, y, fit.mid_height(ankle.x, y, -0.2, pivot.z)))
        ring = b.bridge(ring, b.verts(fit.loop(centre, forward, LEG_SIDES, Vector((0, 0, 1)))))
    b.cap(ring, fit, forward)

    bmesh.ops.recalc_face_normals(b.bm, faces=b.bm.faces[:])
    mesh = bpy.data.meshes.new("ProductionCage")
    b.bm.to_mesh(mesh)
    b.bm.free()
    cage = bpy.data.objects.new("ProductionCage", mesh)
    bpy.context.scene.collection.objects.link(cage)
    return cage, fit, report


def finish(cage, fit):
    """Mirror, one Catmull-Clark level, seat the +X half on the outer surface, mirror it exactly."""
    mirror = cage.modifiers.new("Mirror", "MIRROR")
    mirror.use_clip = True
    mirror.use_mirror_merge = True
    mirror.merge_threshold = 0.0005
    sub = cage.modifiers.new("Subsurf", "SUBSURF")
    sub.levels = sub.render_levels = 1
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(cage.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    me.name = "ProductionBody"
    from mathutils.kdtree import KDTree
    kd = KDTree(len(me.vertices))
    for v in me.vertices:
        kd.insert(v.co, v.index)
    kd.balance()
    partner = {}
    for v in me.vertices:
        if v.co.x < -1e-6:
            co, index, dist = kd.find(Vector((-v.co.x, v.co.y, v.co.z)))
            if dist > 1e-6:
                raise SystemExit("RIPOSTE_BODY: vertex %d has no mirror partner (%.6f)" % (v.index, dist))
            partner[v.index] = index
    seated = 0
    for v in me.vertices:
        if v.co.x < -1e-6:
            continue
        n = v.normal.normalized()
        on_midline = abs(v.co.x) < 1e-6
        hit, hn, _i, _d = fit.tree.ray_cast(v.co + n * SEAT_OUT, -n, SEAT_OUT + SEAT_REACH)
        if hit is not None and hn.dot(n) > 0.0 and (hit - v.co).length <= SEAT_REACH:
            v.co = hit
            seated += 1
        if on_midline:
            v.co.x = 0.0
    for i, j in partner.items():
        src = me.vertices[j].co
        me.vertices[i].co = Vector((-src.x, src.y, src.z))
    me.update()
    body = bpy.data.objects.new("ProductionBody", me)
    bpy.context.scene.collection.objects.link(body)
    cage.hide_render = cage.hide_viewport = True
    return body, {"seated": seated, "of": sum(1 for v in me.vertices if v.co.x >= -1e-6)}


def validate(body, fit):
    """D4: one closed body but for the neck top; manifold, outward normals, no internal or
    degenerate faces, exact symmetry, fidelity to the reference."""
    bm = bmesh.new()
    bm.from_mesh(body.data)
    boundary = [e for e in bm.edges if e.is_boundary]
    islands, seen = 0, set()
    for v in bm.verts:
        if v.index in seen:
            continue
        islands += 1
        stack = [v]
        seen.add(v.index)
        while stack:
            cur = stack.pop()
            for e in cur.link_edges:
                w = e.other_vert(cur)
                if w.index not in seen:
                    seen.add(w.index)
                    stack.append(w)
    out = {"verts": len(bm.verts), "faces": len(bm.faces), "islands": islands,
           "quads": sum(1 for f in bm.faces if len(f.verts) == 4), "tris": sum(1 for f in bm.faces if len(f.verts) == 3),
           "ngons": sum(1 for f in bm.faces if len(f.verts) > 4),
           "boundary_edges": len(boundary),
           "boundary_min_z": round(min(e.verts[0].co.z for e in boundary), 4) if boundary else None,
           "non_manifold_interior": sum(1 for e in bm.edges if not e.is_manifold and not e.is_boundary),
           "degenerate_faces": sum(1 for f in bm.faces if f.calc_area() < 1e-9),
           "poles_gt5": sum(1 for v in bm.verts if len(v.link_edges) > 5),
           "min_corner_deg": round(min(math.degrees(l.calc_angle()) for f in bm.faces for l in f.loops), 1),
           ## Outward-facing normals enclose a positive signed volume.
           "signed_volume_m3": round(bm.calc_volume(signed=True), 5)}
    bm.free()
    _p, stats = symmetry.mirror_problems([tuple(v.co) for v in body.data.vertices], tolerance=1e-6, midline_eps=1e-6)
    out["symmetry"] = {"unmatched": stats["unmatched"], "worst_offset_m": stats["worst_offset_m"], "symmetric": stats["symmetric"]}
    gaps = sorted(fit.tree.find_nearest(p.center)[3] * 1000 for p in body.data.polygons)
    out["face_centre_gap_mm"] = {"mean": round(sum(gaps) / len(gaps), 2), "p95": round(gaps[int(0.95 * len(gaps))], 2), "max": round(gaps[-1], 2)}
    ## At rest the body must not cross itself anywhere (face pairs sharing no vertex).
    pts = [v.co for v in body.data.vertices]
    polys = [list(p.vertices) for p in body.data.polygons]
    tree = BVHTree.FromPolygons(pts, polys)
    crossing = [(a, b) for a, b in tree.overlap(tree) if a < b and not set(polys[a]) & set(polys[b])]
    bands = {}
    for a, _b in crossing:
        z = body.data.polygons[a].center.z
        key = "foot" if z < 0.2 else "shin_knee" if z < 0.6 else "thigh_pelvis" if z < 1.0 else "torso_arm" if z < 1.45 else "neck"
        bands[key] = bands.get(key, 0) + 1
    out["rest_self_intersections"] = {"pairs": len(crossing), "by_band": bands}
    return out


## The weight source coincides with the verified target within this (m): the same body evaluated
## with and without its rest-pose armature differs by float noise (measured 0.0002 mm), which an
## exact digest at 0.01 mm rounding cannot tell from a different body.
WEIGHT_SOURCE_TOLERANCE_M = 1e-5


def transfer_weights(body, source, rig, target):
    """The production body's weights from the approved body's own foundation skin (the aligned
    anatomical source; the two surfaces coincide by construction, so nearest-face interpolation
    has no overlapping anatomy to confuse). The source must be the pin-verified target, vertex for
    vertex."""
    deps = bpy.context.evaluated_depsgraph_get()
    a = bpy.data.meshes.new_from_object(source.evaluated_get(deps))
    a.transform(source.matrix_world)
    b = bpy.data.meshes.new_from_object(target.evaluated_get(deps))
    b.transform(target.matrix_world)
    same = (len(a.vertices) == len(b.vertices) and len(a.polygons) == len(b.polygons)
            and all(tuple(p.vertices) == tuple(q.vertices) for p, q in zip(a.polygons, b.polygons)))
    worst = max(((u.co - v.co).length for u, v in zip(a.vertices, b.vertices)), default=0.0) if same else math.inf
    bpy.data.meshes.remove(a)
    bpy.data.meshes.remove(b)
    if worst > WEIGHT_SOURCE_TOLERANCE_M:
        raise SystemExit("RIPOSTE_BODY: the weight source %s is not the pin-verified target (%s)" % (
            source.name, "different topology" if not same else "%.4f mm off" % (worst * 1000)))
    for g in source.vertex_groups:
        if g.name not in body.vertex_groups:
            body.vertex_groups.new(name=g.name)
    mod = body.modifiers.new("Weights", "DATA_TRANSFER")
    mod.object = source
    mod.use_vert_data = True
    mod.data_types_verts = {"VGROUP_WEIGHTS"}
    mod.vert_mapping = "POLYINTERP_NEAREST"
    mod.layers_vgroup_select_src = "ALL"
    mod.layers_vgroup_select_dst = "NAME"
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.modifier_apply(modifier=mod.name)
    arm = body.modifiers.new("Armature", "ARMATURE")
    arm.object = rig
    body.parent = rig
    body.matrix_parent_inverse = rig.matrix_world.inverted()


## The shoulder repaint (local, +X half, then mirrored): within SHOULDER_RADIUS_M of the
## shoulder joint the deltoid cap follows the arm and clavicle, and the armpit, scapular and
## pectoral edges grade from chest to arm along the arm's axis; blended in by a smooth radial
## falloff so the transferred weights stand beyond it. Measured cause (`_shoulder_diag.py`):
## the transfer left the cap 52 % Chest / 16 % UpperArm, so a lifted arm swung into a cap that
## stayed with the chest. (The v1 production body's semantic rows, `anatomy.DEFORM_REGIONS`,
## were tuned on WolfRig's guard rest; ported onto the A-pose neutral rig they pulled the chest
## with the arm — guard 38.5 mm, ring-falls 34-36 mm — so the principle carries, not the numbers.)
SHOULDER_RADIUS_M = 0.16
## Along the arm's axis from the joint (m): the torso-side end and the arm-side end of the grade.
SHOULDER_GRADE_M = (-0.10, 0.06)
## At the torso-side end and at the arm-side end: (UpperArm, Shoulder) shares, Chest takes the rest.
SHOULDER_SHARES = ((0.10, 0.25), (0.70, 0.25))


def shoulder_repaint(body, rig):
    head = rig.matrix_world @ rig.data.bones["UpperArm.L"].head_local
    tail = rig.matrix_world @ rig.data.bones["UpperArm.L"].tail_local
    axis = (tail - head).normalized()
    groups = {g.name: g for g in body.vertex_groups}
    for name in ("UpperArm.L", "Shoulder.L", "Chest"):
        if name not in groups:
            groups[name] = body.vertex_groups.new(name=name)
    names = {g.index: g.name for g in body.vertex_groups}
    repainted = 0
    for v in body.data.vertices:
        p = body.matrix_world @ v.co
        d = (p - head).length
        if p.x <= 1e-6 or d >= SHOULDER_RADIUS_M:
            continue
        s = (p - head).dot(axis)
        u = min(1.0, max(0.0, (s - SHOULDER_GRADE_M[0]) / (SHOULDER_GRADE_M[1] - SHOULDER_GRADE_M[0])))
        u = u * u * (3 - 2 * u)
        upper = SHOULDER_SHARES[0][0] + u * (SHOULDER_SHARES[1][0] - SHOULDER_SHARES[0][0])
        clav = SHOULDER_SHARES[0][1] + u * (SHOULDER_SHARES[1][1] - SHOULDER_SHARES[0][1])
        target = {"UpperArm.L": upper, "Shoulder.L": clav, "Chest": 1.0 - upper - clav}
        f = 1.0 - d / SHOULDER_RADIUS_M
        f = f * f * (3 - 2 * f)
        current = {names[g.group]: g.weight for g in v.groups}
        total = sum(current.values()) or 1.0
        current = {k: w / total for k, w in current.items()}
        for name in set(current) | set(target):
            w = (1 - f) * current.get(name, 0.0) + f * target.get(name, 0.0)
            if w > 1e-4:
                groups[name].add([v.index], w, "REPLACE")
            elif name in current:
                groups[name].remove([v.index])
        repainted += 1
    return repainted


## Neck interface findings (D2, d6 with the approved head riding the Head bone, bare): with the
## transferred weights the neck crosses the head only on its underside and nape, the intended
## seam (`male_base_v2.head_face_classes`), at rest, in every frame of every clip and under the
## runtime's head turns; the open neck top stays hidden (nearest 1.8 mm, death_stab frame 64).
## Pinning the skin the head hides to the Head bone (d9) was tried and withdrawn: what it removed
## was neck sliding under the jaw, which is the seam and not a defect, and it stretched the
## visible neck (edges 1.31 -> 1.77 in death_stab). The neck keeps the transferred weights.


## Elbow deformation findings (d6 baseline): the guard elbow (~110 deg, supported) crosses the
## inner elbow ~18.8 mm and the 120-deg stress pose ~26 mm. Neither a hinge-loop pass (d7: cut
## the 120-deg depth but raised collapse 6->16, supported pose flat) nor a UpperArm<->Forearm
## weight crossfade (d8: supported pose 18.8->18.0, collapse 6->8) moved the supported pose, and
## smooth-shaded both read as a rounded bend with no face inversion and nothing visible at the
## gameplay camera (board_d6_elbow.png). Those two interventions did not help; that is not proof
## the contact is unavoidable. It is classified as accepted internal contact (invisible, no
## inversion, no gameplay consequence): d6 elbow stands and the 120-deg extreme is a non-blocking
## stress case (the clips peak at 110.6 deg).
def _mirror_name(name):
    if name.endswith(".L"):
        return name[:-2] + ".R"
    if name.endswith(".R"):
        return name[:-2] + ".L"
    return name


def mirror_weights(body):
    """The -X half's weights are its +X partner's with the bone names mirrored (as the geometry
    is), so the skin is bilaterally exact however it was sampled; midline vertices keep theirs."""
    from mathutils.kdtree import KDTree
    me = body.data
    kd = KDTree(len(me.vertices))
    for v in me.vertices:
        kd.insert(v.co, v.index)
    kd.balance()
    names = {g.index: g.name for g in body.vertex_groups}
    for name in {_mirror_name(n) for n in names.values()} - set(names.values()):
        body.vertex_groups.new(name=name)
    index = {g.name: g.index for g in body.vertex_groups}
    for v in me.vertices:
        if v.co.x >= -1e-6:
            continue
        _co, j, _d = kd.find(Vector((-v.co.x, v.co.y, v.co.z)))
        source = {names[g.group]: g.weight for g in me.vertices[j].groups if g.group in names}
        for g in list(v.groups):
            body.vertex_groups[g.group].remove([v.index])
        for name, w in source.items():
            body.vertex_groups[index[_mirror_name(name)]].add([v.index], w, "REPLACE")


def skin(body, rig, method="transfer", source=None, target=None, shoulder_fix=False):
    """D5: weights from the deforming bones only (transferred from the approved body's skin, or
    bone heat for comparison), at most four influences, normalized, mirrored left/right."""
    for name in NON_DEFORMING:
        rig.data.bones[name].use_deform = False
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    if method == "transfer":
        transfer_weights(body, source, rig, target)
    else:
        body.select_set(True)
        rig.select_set(True)
        bpy.context.view_layer.objects.active = rig
        bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    for name in NON_DEFORMING:
        if name in body.vertex_groups:
            body.vertex_groups.remove(body.vertex_groups[name])
    repainted = shoulder_repaint(body, rig) if shoulder_fix else 0
    mirror_weights(body)
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
    unweighted = sum(1 for v in body.data.vertices if not v.groups or sum(g.weight for g in v.groups) <= 0.0)
    deforming = {b.name for b in rig.data.bones if b.use_deform}
    stray = sorted({g.name for g in body.vertex_groups} - deforming)
    names = {g.index: g.name for g in body.vertex_groups}
    pts = [tuple(v.co) for v in body.data.vertices]
    weights = [{names[g.group]: g.weight for g in v.groups if g.weight > 0} for v in body.data.vertices]

    def mirror_bone(n):
        return n[:-2] + (".R" if n.endswith(".L") else ".L") if n.endswith((".L", ".R")) else n

    problems, stats = symmetry.weight_mirror_problems(pts, weights, mirror_bone, tolerance=1e-6, midline_eps=1e-6)
    return {"method": method, "shoulder_repainted": repainted, "unweighted": unweighted,
            "max_influences": max(sum(1 for g in v.groups if g.weight > 0) for v in body.data.vertices),
            "non_deforming_groups": stray, "weight_mirror_problems": len(problems)}


def main():
    args = _arguments()
    bpy.ops.wm.open_mainfile(filepath=os.path.abspath(args.scene))
    target = bpy.data.objects[args.target]
    rig = bpy.data.objects[args.rig]
    seen = observe(target, rig)
    if args.pin_out:
        import validate_assets
        with open(args.foundation, encoding="utf-8") as h:
            foundation = json.load(h)
        provenance = {"foundation_id": foundation.get("id"), "foundation_sha256": ownership.file_sha256(args.foundation),
                      "foundation_path": os.path.relpath(args.foundation, ROOT).replace("\\", "/"),
                      "configuration": {"identity": "id_reference", "height_m": 1.80, "mass_kg": 80.0, "symmetric": bool(foundation["resolution"].get("symmetric"))},
                      "builder_sha256": ownership.builder_sha256(ROOT), "rig": {"name": args.rig, "contract_sha256": args.rig_contract},
                      "scene": os.path.relpath(os.path.abspath(args.scene), ROOT).replace("\\", "/")}
        doc = retopology_reference.pin(seen, provenance, validate_assets.FIGHTER_ACTIONS)
        with open(args.pin_out, "w", encoding="utf-8", newline="\n") as h:
            json.dump(doc, h, indent=1)
            h.write("\n")
        print("RIPOSTE_BODY_PIN", json.dumps({"geometry": doc["geometry"], "clips": len(doc["clip_contract"])}))
        return
    with open(args.pin, encoding="utf-8") as h:
        pinned = json.load(h)
    found = retopology_reference.problems(pinned, seen)
    if found:
        for p in found:
            print("RIPOSTE_BODY_REJECTED", p)
        raise SystemExit("RIPOSTE_BODY: the inputs are not the pinned reference; nothing was fitted")
    cage, fit, report = build(target, rig)
    body, report["seat"] = finish(cage, fit)
    report["validation"] = validate(body, fit)
    report["skin"] = skin(body, rig, args.weights, bpy.data.objects.get(args.weight_source), target, args.shoulder_fix)
    report["reference"] = {"geometry_sha256": seen["geometry"]["sha256"], "rig_rest_sha256": seen["rig_rest_sha256"]}
    os.makedirs(args.out, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(os.path.abspath(args.out), "production_body.blend"))
    with open(os.path.join(args.out, "production_body.json"), "w", encoding="utf-8", newline="\n") as h:
        json.dump(report, h, indent=1)
        h.write("\n")
    print("RIPOSTE_BODY", json.dumps(report))


if __name__ == "__main__":
    main()
