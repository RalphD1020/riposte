"""Garments constructed on a resolved body (CHARACTER-ATTACHMENT-001, F9, GARMENT-BUILD-001):
a `riposte.garment` definition (`type: garment`) names its pieces in `design.pieces`;
each piece is built on the character's own body and fitted rig, never on Wolf's, so one
definition fits every height, frame and muscularity the foundation resolves.

Responsibility (GARMENT-VALIDATION-001): this builder owns FIT — adapting an authored garment
shape (its `design` pieces, ease and guide profiles) to the resolved body and the layers
beneath it — and the garment's own weights (MOTION). It does NOT own DESIGN: it must not invent
a garment's artistic form by moving vertices away from the body until tests pass. A visual
defect fixed by one authored shape is fixed in that definition, not by a new universal
parameter here; add a shared mechanism only when several independent garments show the same
structural failure. See docs/reference/blender-art-iteration-protocol.md.

A garment is its own low-resolution basemesh, never the body's surface offset: rings of
a chosen number of columns are laid round the body along bone paths (the parametric
garment-from-sections method), each ring's radius the smoothed upper envelope of the
body's cross-section there (the cloth spans hollows, never traces muscle), plus the
piece's ease; loose cloth hangs from its support (`drape`) and gathers where it is tied
(`cinch`). Openings are smooth loops by construction: a torso's neck and arm openings
are cones of constant angle about their axes, its hem and every tube's ends smooth
curves. A sleeve is set into its arm opening: sewn to it (`set_in: "bridge"`, the opening
cut as an armscye plane across the upper arm, `arms.armscye_m`, so its edge winds once round
the arm) or tucked under the torso's finished armhole edge. A limb's ring is measured on
the limb's own section (its region's vertices, `section`), bounded by the limb's surface
along each column's ray where a bend cuts the section obliquely (`_bounded`); a
trouser leg runs waist to ankle on its own half of the body (`half`), the two legs
meeting at the midline as a centre seam. Thickness is a rim and an inward lip at every
opening; the rest is single-sided.

Pieces:
  torso   rings round the spine from the hem up to the chest, then a yoke of rays from
          the chest centre over the shoulders; `neck` and `arms` openings; optional
          `sleeves` grown from the arm openings;
  tube    rings along a bone path (a trouser leg, belt, bracer, boot with its toe closed),
          closed or over azimuth `arcs` (panels);
  cap     rays from a joint within a cone (a fitted shoulder reinforcement);
  plate   a rigid fitting seated on the garment built before it (a buckle).

Stations name bones: {"bone", "at" (0 head .. 1 tail, may extrapolate), "offset"}.
`sides` ["L", "R"] builds a piece per side ("{s}" in names and bones; x mirrored on R).
Weights: each vertex takes the body's skin weights at its nearest body face (at most four,
normalized); hanging hull rows blend towards Hips; a plate follows its one bone. Faces carry
their piece (`riposte_mass`) and the body region beneath (`riposte_region`).
"""

import math
import os

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

MAX_INFLUENCES = 4
MIN_WEIGHT = 0.01
## Garment weight smoothing (`design.weights.smooth` overrides the passes) and the arm chain
## `design.weights.arm_max` caps.
WEIGHT_SMOOTH_PASSES = 4
WEIGHT_SMOOTH_FACTOR = 0.5
ARM_CHAIN = ("UpperArm", "Forearm", "Hand")
## The share of a capped arm weight that goes to the clavicle; the rest goes to Chest. The
## body beneath carries little clavicle weight, so a vest edge given all of it rises off
## the skin it lies on.
ARM_TO_CLAVICLE = 0.3
## A ring's radius: the body's cross-section smoothed ENVELOPE_PASSES times, never below
## the body (the cloth is stretched over the highest points and spans the hollows).
ENVELOPE_PASSES = 8
## An opening's rim (the cloth's thickness) and its lip folded inward (no see-through
## at a glancing view into a sleeve or neck).
LIP_M = 0.012
## Faces whose dihedral angle exceeds this shade as a crease (rims, hems, folds).
SHARP_DEG = 55.0
## A hanging ring below the crotch takes the body's outer hull (legs bridged); its
## weights blend this share towards Hips (the hem moves with the pelvis, not one leg) where
## it hangs free: none within HANG_REST_M of the skin, all from HANG_FREE_M further.
HULL_TO_HIPS = 0.6
HANG_REST_M = 0.02
HANG_FREE_M = 0.03
## A cap's ray longer than this multiple of its median left the joint's surface.
CAP_REACH = 1.35
## A ring's ray longer than this multiple of the ring's median left its section.
ROW_REACH = 1.6
## A set-in sleeve starts this far inside its arm opening (under the torso's armhole edge).
TUCK_M = 0.03
## Under the torso a sleeve keeps this much closer to the skin than the torso's ease ...
TUCK_CLEAR_M = 0.004
## ... and never closer than this, nor than this share of that under-ease (a sleeve on the
## skin sinks between its vertices).
MIN_UNDER_EASE_M = 0.002
TUCK_FLOOR = 0.7
## Past the opening's outer edge a tucked sleeve eases to its own radius over this length.
TUCK_FADE_M = 0.02
## A set-in sleeve's rows are spaced by (i / (rows - 1)) ** BRIDGE_GRADE along it, its radius
## blends from the armhole's over BRIDGE_BLEND_M, and its surface is cast from no nearer the
## torso than CAP_FROM of its path.
BRIDGE_GRADE = 1.5
BRIDGE_BLEND_M = 0.06
CAP_FROM = 0.03
## The armscye plane's distance in the cone's units where the two bound an opening.
ARMSCYE_DEG_PER_M = 400.0
## Underarm cloth takes the seam's torso weights over this distance from the seam.
SEAM_WEIGHT_M = 0.1
## The cap's first CAP_RELAX_ROWS rows relax CAP_RELAX_PASSES times by CAP_RELAX towards their
## neighbours, held at ease off skin found within CAP_RELAX_REACH_M.
CAP_RELAX_ROWS = 6
CAP_RELAX_PASSES = 10
CAP_RELAX = 0.5
CAP_RELAX_REACH_M = 0.04
## The cap's underside: direction z at or below -UNDERARM_Z is fully under the arm ...
UNDERARM_Z = 0.7
## ... and behind it: none of it at the side of the arm (direction y 0), all from y >= this.
UNDERARM_BACK = 0.5
## Smoothing passes along an arm opening's edge.
LOOP_SMOOTH = 3
## A section's vertices beyond this multiple of the slice's median distance are not its ring.
SECTION_REACH = 1.5
## The most a sample between two rings may raise a ring's radius.
MID_GAIN_M = 0.012
## A limb's section is near round: a column beyond this multiple of its ring's median is
## another surface (a bend's oblique cut), refilled from its neighbours.
SECTION_ROW_REACH = 1.3
## How far a section's bounding ray looks for the limb's surface (`_bounded`).
SECTION_RAY_M = 0.5
## An opening's cut (`_cut`): bisection steps along a crossed edge; a crossing within this
## share of an edge's end moves that vertex onto the curve.
CUT_BISECT = 16
CUT_SNAP = 0.15
## A layer over garments: a ring's surface beneath is the outer face of the stack of garments
## lying on the body along its ray (`_lift`): the first within UNDER_FIRST_M of the body,
## each next within UNDER_NEXT_M of the last (beyond is another limb or a far wall, never
## a layer beneath), at most UNDER_LAYERS deep.
UNDER_FIRST_M = 0.05
UNDER_NEXT_M = 0.03
UNDER_LAYERS = 6
## Collision safety after the fit (`_resolve`), for chords only (a face between two clear
## vertices dipping into a bulge beneath): every sample of the body and of the garments
## beneath looks this far behind itself for cloth facing its own way (normals within
## RESOLVE_ALIGN); cloth nearer than its gap is pushed out, the push shared with the
## neighbours at this rate, over this many passes.
RESOLVE_DEPTH_M = 0.02
## Against the body only a chord's sag (millimetres at the rings' spacing): deeper cloth is
## construction meant to lie hidden (a set-in sleeve's top tucked under its armhole edge),
## never to be dragged out through the layer over it.
RESOLVE_BODY_DEPTH_M = 0.006
RESOLVE_ALIGN = 0.5
RESOLVE_SPREAD = 0.5
RESOLVE_PASSES = 2
## The gap a garment keeps over the skin and over a garment beneath it (faces, not only
## vertices: a chord between two clear vertices never dips into a bulge).
BODY_GAP_M = 0.002
## Face-level clearance passes after the vertex pass (a lifted face can expose its neighbour).
CLEAR_FACE_PASSES = 3
CLEAR_FACE_ALIGN = 0.3
LAYER_GAP_M = 0.005
FRONT = Vector((0.0, -1.0, 0.0))
UP = Vector((0.0, 0.0, 1.0))


def _side(value, side):
    if isinstance(value, str):
        return value.replace("{s}", side or "")
    if isinstance(value, list):
        return [_side(v, side) for v in value]
    if isinstance(value, dict):
        return {k: _side(v, side) for k, v in value.items()}
    return value


def body_frame(body, rig, regions):
    """What every piece is fitted to: the body's surface tree (world), faces, vertex
    regions, skin weights, the rig's rest bones (world) and the sole height."""
    world = body.matrix_world
    points = [world @ v.co for v in body.data.vertices]
    polys = [list(p.vertices) for p in body.data.polygons]
    region_of = {}
    for name, entry in regions["regions"].items():
        if entry.get("object"):
            continue
        for i in entry["vertices"]:
            region_of.setdefault(i, name)
    groups = {g.index: g.name for g in body.vertex_groups}
    weights = [{groups[g.group]: g.weight for g in v.groups if g.weight > 0.0} for v in body.data.vertices]
    bones = {b.name: (rig.matrix_world @ b.head_local, rig.matrix_world @ b.tail_local) for b in rig.data.bones}
    feet = [points[i] for r in ("foot.L", "foot.R") for i in regions["regions"][r]["vertices"]]
    ## The legs and pelvis alone: a hanging ring spans them, never the arms beside them.
    lower = set()
    for r in HULL_REGIONS:
        lower.update(regions["regions"][r]["vertices"])
    lower_polys = [p for p in polys if all(i in lower for i in p)]
    rot = world.to_3x3()
    normals = [(rot @ v.normal).normalized() for v in body.data.vertices]
    return {"tree": BVHTree.FromPolygons(points, polys), "points": points, "polys": polys, "region_of": region_of,
            "samples": _samples(points, normals),
            "regions": regions, "weights": weights, "bones": bones, "sole_z": min(p.z for p in feet),
            "lower_tree": BVHTree.FromPolygons(points, lower_polys)}


HULL_REGIONS = ("waist", "pelvis", "upper_leg.L", "upper_leg.R", "lower_leg.L", "lower_leg.R")


def with_surface(frame, obj, bone, region):
    """`frame` with another rigid anatomical surface added (the head a scarf wraps,
    `design.fit_head`): its faces join the tree pieces are cast against and cleared from,
    its points carry `bone` alone as their weight and `region` as their region."""
    import numpy as np
    world = obj.matrix_world
    rot = world.to_3x3()
    base = len(frame["points"])
    pts = [world @ v.co for v in obj.data.vertices]
    own = [[base + i for i in p.vertices] for p in obj.data.polygons]
    ## Only visible anatomy is fitted to: the body's faces enclosed by the added surface
    ## (the neck's seat inside the head) would catch the rays first.
    tree = BVHTree.FromPolygons(pts, [list(p.vertices) for p in obj.data.polygons])

    def enclosed(point):
        location, normal, _i, dist = tree.find_nearest(point, 0.08)
        return location is not None and (point - location).dot(normal) < 0.0

    inside = {i for i, p in enumerate(frame["points"]) if enclosed(p)}
    points = frame["points"] + pts
    polys = [p for p in frame["polys"] if not all(i in inside for i in p)] + own
    region_of = dict(frame["region_of"])
    region_of.update({base + i: region for i in range(len(pts))})
    extra = _samples(pts, [(rot @ v.normal).normalized() for v in obj.data.vertices])
    samples = (np.concatenate([frame["samples"][0], extra[0]]), np.concatenate([frame["samples"][1], extra[1]]))
    return dict(frame, tree=BVHTree.FromPolygons(points, polys), points=points, polys=polys, region_of=region_of,
                weights=frame["weights"] + [{bone: 1.0} for _p in pts], samples=samples)


def lie_beneath(under, over, depth):
    """`over` (another component of the outfit: the hair over a scarf) moved outside the
    garment `under` where they overlap: every face of `over` that a sample of `under`'s
    outer surface meets within `depth` behind it is pushed out to LAYER_GAP_M beyond, its
    neighbours a share (the hair rides over the scarf; elsewhere it keeps its shape).
    Works on the character's own copy. Returns the vertices moved."""
    inverse = over.matrix_world.inverted()
    rot = inverse.to_3x3()
    points, normals = garment_samples(under)
    import numpy as np
    local = (np.array([tuple(inverse @ Vector(p)) for p in points]).reshape(-1, 3),
             np.array([tuple((rot @ Vector(n)).normalized()) for n in normals]).reshape(-1, 3))
    bm = bmesh.new()
    bm.from_mesh(over.data)
    bm.faces.ensure_lookup_table()
    bm.verts.index_update()
    moved = _resolve(bm, list(bm.faces), [(local, LAYER_GAP_M, depth)], depth)
    bm.to_mesh(over.data)
    bm.free()
    over.data.update()
    return moved


def centred(frame, points, regions, slab=0.012, reach=0.2):
    """Path points moved onto the centroid of the body's cross-section in `regions` there
    (a bone is a joint landmark, never the middle of the limb): the region vertices within
    `slab` of the plane across the path and `reach` of the point."""
    import numpy as np
    pool = np.array([tuple(frame["points"][i]) for r in regions for i in frame["regions"]["regions"][r]["vertices"]])
    out = []
    for n, p in enumerate(points):
        a = points[max(0, n - 1)]
        b = points[min(len(points) - 1, n + 1)]
        t = np.array(tuple((b - a).normalized())) if (b - a).length > 1e-9 else np.array((0.0, 0.0, 1.0))
        q = np.array(tuple(p))
        d = pool - q
        along = d @ t
        across = np.linalg.norm(d - np.outer(along, t), axis=1)
        mask = (np.abs(along) < slab) & (across < reach)
        if mask.sum() < 12:
            out.append(p.copy())
            continue
        c = pool[mask].mean(axis=0)
        ## Only across the path: the station keeps its height along it.
        shift = Vector(tuple(c - q)) - Vector(tuple(t)) * float((c - q) @ t)
        out.append(p + shift)
    return out


def _station(frame, st, mirror=False):
    head, tail = frame["bones"][st["bone"]]
    offset = Vector(st.get("offset", (0.0, 0.0, 0.0)))
    if mirror:
        offset.x = -offset.x
    return head.lerp(tail, st.get("at", 0.0)) + offset


def _vec(v, mirror):
    out = Vector(v)
    if mirror:
        out.x = -out.x
    return out.normalized()


## ---------------------------------------------------------------- paths and rays

class _Path:
    """A polyline through stations with a frame carried along it (parallel transport):
    `at(s)` (s 0..1 of its length) gives (point, tangent, ref, side); direction theta
    (0 = ref, the front where it can) is ref*cos + side*sin."""

    SAMPLES = 160

    def __init__(self, points):
        self.points = points
        lengths = [0.0]
        for a, b in zip(points, points[1:]):
            lengths.append(lengths[-1] + (b - a).length)
        self.length = max(1e-6, lengths[-1])
        self.samples = []
        ref = None
        for n in range(self.SAMPLES + 1):
            s = n / self.SAMPLES
            p, t = self._raw(s, lengths)
            if ref is None:
                ref = FRONT - t * FRONT.dot(t)
                if ref.length < 1e-3:
                    ref = UP - t * UP.dot(t)
            ref = (ref - t * ref.dot(t)).normalized()
            self.samples.append((p, t, ref.copy(), t.cross(ref).normalized()))

    def _raw(self, s, lengths):
        d = s * lengths[-1]
        for i in range(len(self.points) - 1):
            if d <= lengths[i + 1] or i == len(self.points) - 2:
                span = max(1e-9, lengths[i + 1] - lengths[i])
                u = (d - lengths[i]) / span
                a, b = self.points[i], self.points[i + 1]
                tangent = (b - a).normalized()
                ## Bends round smoothly: the tangent blends with the next segment near a joint.
                if i + 2 < len(self.points) and u > 0.7:
                    nxt = (self.points[i + 2] - b).normalized()
                    tangent = tangent.lerp(nxt, (u - 0.7) / 0.6).normalized()
                if i > 0 and u < 0.3:
                    prev = (a - self.points[i - 1]).normalized()
                    tangent = prev.lerp(tangent, 0.5 + u / 0.6).normalized()
                return a.lerp(b, u), tangent
        return self.points[-1], (self.points[-1] - self.points[-2]).normalized()

    def at(self, s):
        x = max(0.0, min(1.0, s)) * self.SAMPLES
        i = min(self.SAMPLES - 1, int(x))
        u = x - i
        a, b = self.samples[i], self.samples[i + 1]
        point = a[0].lerp(b[0], u) if 0.0 <= s <= 1.0 else self._extrapolate(s)
        return point, a[1].lerp(b[1], u).normalized(), a[2].lerp(b[2], u).normalized(), a[3].lerp(b[3], u).normalized()

    def _extrapolate(self, s):
        if s < 0.0:
            p, t = self.samples[0][0], self.samples[0][1]
            return p + t * (s * self.length)
        p, t = self.samples[-1][0], self.samples[-1][1]
        return p + t * ((s - 1.0) * self.length)

    def param(self, point):
        """The s of the path sample nearest `point`; beyond an end, along its tangent (s < 0
        or > 1: a shoulder's armhole edge lies medial to the arm's first station)."""
        best = min(range(self.SAMPLES + 1), key=lambda n: (self.samples[n][0] - point).length)
        if best == 0:
            return min(0.0, (point - self.samples[0][0]).dot(self.samples[0][1]) / self.length)
        if best == self.SAMPLES:
            return 1.0 + max(0.0, (point - self.samples[-1][0]).dot(self.samples[-1][1]) / self.length)
        return best / self.SAMPLES

    def direction(self, s, theta):
        _p, _t, ref, side = self.at(s)
        return (ref * math.cos(theta) + side * math.sin(theta)).normalized()

    def angle(self, s, point):
        p, t, ref, side = self.at(s)
        d = point - p
        d -= t * d.dot(t)
        return math.atan2(d.dot(side), d.dot(ref))


def _cast(frame, origin, direction, hull=False, reach=0.7):
    """The body's distance from `origin` along `direction`: its first surface outward
    (`hull` False, origin inside the body) or its outermost (`hull`, from outside in,
    against the pelvis and legs only)."""
    tree = frame["tree"]
    if hull:
        hit = frame["lower_tree"].ray_cast(origin + direction * reach, -direction, reach)[0]
        return None if hit is None else max(0.005, (hit - origin).dot(direction))
    hit = tree.ray_cast(origin + direction * 1e-4, direction, reach)[0]
    return None if hit is None else (hit - origin).length


def _fill(grid, cyclic):
    """Rays that met nothing take their nearest neighbour's value in the row."""
    for row in grid:
        known = [i for i, v in enumerate(row) if v is not None]
        if not known:
            continue
        for i, v in enumerate(row):
            if v is None:
                j = min(known, key=lambda k: min(abs(k - i), len(row) - abs(k - i)) if cyclic else abs(k - i))
                row[i] = row[j]
    for r in range(len(grid)):
        if all(v is None for v in grid[r]):
            src = grid[r - 1] if r > 0 else next(g for g in grid if g[0] is not None)
            grid[r] = list(src)
    return grid


def _envelope(raw, cyclic, passes=ENVELOPE_PASSES):
    """The smooth upper envelope of a radius grid: blurred, never below the body."""
    rows, cols = len(raw), len(raw[0])
    out = [list(r) for r in raw]
    for _p in range(passes):
        nxt = [list(r) for r in out]
        for i in range(rows):
            for k in range(cols):
                ks = [(k - 1) % cols, (k + 1) % cols] if cyclic else [max(0, k - 1), min(cols - 1, k + 1)]
                vals = [out[i][j] for j in ks] + [out[max(0, i - 1)][k], out[min(rows - 1, i + 1)][k]]
                nxt[i][k] = max(raw[i][k], (out[i][k] * 2.0 + sum(vals)) / 6.0)
        out = nxt
    return out


def _profile(spec, key, t, default):
    """A value along a piece: a number, or [start, end] (linear), or [[t, v], ...]."""
    v = spec.get(key, default)
    if isinstance(v, (int, float)):
        return float(v)
    if v and isinstance(v[0], (int, float)):
        return v[0] + (v[1] - v[0]) * t
    pts = sorted(v)
    if t <= pts[0][0]:
        return pts[0][1]
    for (t0, v0), (t1, v1) in zip(pts, pts[1:]):
        if t <= t1:
            return v0 + (v1 - v0) * (t - t0) / max(1e-9, t1 - t0)
    return pts[-1][1]


def _end_offset(curve, theta, u=None):
    """An end's offset along the path (m) at azimuth theta: c1 cos + c2 cos 2 (+ `round`
    over an arc, its middle lowest)."""
    if not curve:
        return 0.0
    out = curve.get("c1", 0.0) * math.cos(theta) + curve.get("c2", 0.0) * math.cos(2.0 * theta)
    ## `s1`: a diagonal edge (higher on one side), a wrap that crosses the body.
    out += curve.get("s1", 0.0) * math.sin(theta)
    if u is not None:
        out += curve.get("round", 0.0) * (1.0 - u * u)
    return out


## ---------------------------------------------------------------- the radius field

def _section(frame, regions):
    """The limb's own body vertices (numpy, world): a section is cut from these alone, so
    the torso beside a shoulder or the pelvis above a thigh never enters a limb's ring."""
    import numpy as np
    return np.array([tuple(frame["points"][i]) for r in regions for i in frame["regions"]["regions"][r]["vertices"]])


def _section_raw(pool, path, rows, thetas, param):
    """Raw radii from cross-sections: ring i's column k is the farthest limb vertex from the
    path within half a ring's spacing along it and half a column's angle round it (the
    section's outer envelope, the bulge between rings included). None where it is empty."""
    import numpy as np
    cols = len(thetas)
    half = math.pi / cols
    out = []
    for i in range(rows):
        row = []
        for k in range(cols):
            s = param(i, k)
            p, t, ref, side = path.at(s)
            spacing = abs(param(min(rows - 1, i + 1), k) - param(max(0, i - 1), k)) * path.length / (2 if 0 < i < rows - 1 else 1)
            slab = max(0.01, spacing * 0.5)
            d = pool - np.array(tuple(p))
            along = d @ np.array(tuple(t))
            near = np.abs(along) < slab
            if not near.any():
                row.append(None)
                continue
            dn = d[near]
            x = dn @ np.array(tuple(ref))
            y = dn @ np.array(tuple(side))
            ## The slice is the limb's ring, not every region vertex the plane crosses: a
            ## vertex much farther than the slice's median is another lobe of the region.
            across = np.hypot(x, y)
            ring = across < np.median(across) * SECTION_REACH
            ang = np.arctan2(y, x)
            diff = np.abs((ang - thetas[k] + math.pi) % (2.0 * math.pi) - math.pi)
            sel = (diff < half) & ring
            if not sel.any():
                row.append(None)
                continue
            ## The radius along this column's direction (its projection, not the slant).
            r = (x[sel] * math.cos(thetas[k]) + y[sel] * math.sin(thetas[k]))
            row.append(float(r.max()))
        out.append(row)
    return out


def _bounded(frame, measured, origin_dir):
    """A section's radii bounded by the body's surface along each column's own ray: where
    the path bends (a shoulder, the hip into the thigh, the ankle into the foot) a slice
    across it cuts the limb obliquely and reads far too wide, while a ray from inside the
    limb leaves it at its true surface. A ray counts only where it exits the body (its
    origin is inside); a column the slice missed takes the ray alone."""
    tree = frame["tree"]
    out = []
    for i, row in enumerate(measured):
        bounded = []
        for k, m in enumerate(row):
            origin, direction = origin_dir(i, k)
            hit, normal, _f, dist = tree.ray_cast(origin + direction * 1e-4, direction, SECTION_RAY_M)
            ray = dist if hit is not None and normal.dot(direction) > 0.0 else None
            bounded.append(ray if m is None else (m if ray is None else min(m, ray + MID_GAIN_M)))
        out.append(bounded)
    return out


def _radii(frame, spec, rows, cols, origin_dir, cyclic, hull_rows=(), downward=True, drape_rows=None, raw=None):
    """Raw body distances and the cloth's radius field. `downward`: row index grows down
    the body (a tube hung from its first station); else up it (the torso, hem first).
    `drape_rows`: how many rows (from index 0) the drape may run over. `raw`: radii already
    measured (a limb's sections, `_section_raw`); else rays are cast (`_cast_rows`)."""
    if raw is not None:
        rows_in = raw
        raw = []
        for row in rows_in:
            known = sorted(v for v in row if v is not None)
            limit = known[len(known) // 2] * SECTION_ROW_REACH if known else None
            raw.append([v if v is not None and v <= limit else None for v in row] if known else row)
    else:
        raw = _cast_rows(frame, rows, cols, origin_dir, hull_rows)
    raw = _fill(raw, cyclic)
    if spec.get("reach_m") is not None:
        ## Neckwear stays at the neck: a ray along the sloping shoulder reaches no further
        ## than the row's reach (the cloth spans above the slope, never out along it).
        for i in range(rows):
            cap = _profile(spec, "reach_m", i / max(1, rows - 1), 1.0)
            raw[i] = [min(v, cap) for v in raw[i]]
    raw = _lift(frame, raw, lambda i, k: origin_dir(i, k))
    radius = _envelope(raw, cyclic, spec.get("smooth", ENVELOPE_PASSES))
    return raw, _drape(spec, radius, rows, cols, downward, drape_rows)


def _lift(frame, raw, origin_dir):
    """A layer over garments: each ray's surface beneath is the outer face of the garments
    (built before this one, `under_tree`) stacked on the body along it, plus LAYER_GAP_M, so
    the radius field (and its envelope) is fitted to the clothed body: an outer layer is
    smooth over what it covers, never pierced by it, never reaching to another limb."""
    tree = frame.get("under_tree")
    if tree is None:
        return raw
    out = []
    for i, row in enumerate(raw):
        lifted = []
        for k, r in enumerate(row):
            origin, direction = origin_dir(i, k)
            at, under, reach = r - BODY_GAP_M, None, UNDER_FIRST_M
            for _n in range(UNDER_LAYERS):
                hit = tree.ray_cast(origin + direction * at, direction, reach)[0]
                if hit is None:
                    break
                at = (hit - origin).dot(direction) + 1e-4
                under, reach = at, UNDER_NEXT_M
            lifted.append(r if under is None or under < r else under + LAYER_GAP_M)
        out.append(lifted)
    return out


def _cast_rows(frame, rows, cols, origin_dir, hull_rows):
    """Ray radii; `origin_dir(i, k)` takes a fractional row: each ring also samples the body
    halfway to its neighbours and keeps the highest (faces between rings never dip into a
    bulge)."""
    raw = []
    for i in range(rows):
        row = []
        for k in range(cols):
            o0, d0 = origin_dir(i, k)
            own = _cast(frame, o0, d0, hull=i in hull_rows)
            best = own
            if own is not None:
                for di in (-0.5, -0.25, 0.25, 0.5):
                    fi = i + di
                    if fi < 0.0 or fi > rows - 1:
                        continue
                    origin, direction = origin_dir(fi, k)
                    r = _cast(frame, origin, direction, hull=i in hull_rows)
                    if r is None:
                        continue
                    ## A neighbour's sample measured along this ring's own ray; a bulge
                    ## between rings is millimetres (an oblique surface reads further).
                    r = min((origin + direction * r - o0).dot(d0), own + MID_GAIN_M)
                    best = max(best, r)
            row.append(best)
        ## A ray far longer than its ring's median ran out of this section (through the
        ## shoulder into the arm, past a bend): it is refilled from its neighbours.
        known = sorted(v for v in row if v is not None)
        if known:
            limit = known[len(known) // 2] * ROW_REACH
            row = [v if v is not None and v <= limit else None for v in row]
        raw.append(row)
    return raw


def _drape(spec, radius, rows, cols, downward, drape_rows):
    support = spec.get("drape_from")
    if support is not None:
        ## Loose cloth hangs from its support (a share of the piece from its top): below
        ## it, it never follows the body back in.
        if downward:
            top = int(round(support * (rows - 1)))
            for i in range(top + 1, rows):
                for k in range(cols):
                    radius[i][k] = max(radius[i][k], radius[i - 1][k])
        else:
            span = (drape_rows or rows) - 1
            top = int(round((1.0 - support) * span))
            for i in range(top - 1, -1, -1):
                for k in range(cols):
                    radius[i][k] = max(radius[i][k], radius[i + 1][k])
    return radius


def _shape(spec, t, theta, radius, raw, direction=None):
    """The cloth's offset off the body: ease, a flare to the hem, cinches and folds, and
    `allowance`s: movement room where a joint needs it (a gusset's job), each {t: [from,
    to], toward: a body-frame direction (x mirrored on the right), deg, m} — `m` more ease
    at the middle of its span, facing `toward`, fading to none `deg` away and at its ends."""
    ease = _profile(spec, "ease_m", t, 0.004) + _profile(spec, "flare_m", t * t, 0.0)
    if direction is not None:
        for a in spec.get("allowance", ()):
            t0, t1 = a["t"]
            if not t0 <= t <= t1:
                continue
            aim = _vec(a["toward"], spec.get("_mirror", False))
            off = math.degrees(direction.angle(aim, 0.0))
            if off < a["deg"]:
                span = math.sin(math.pi * (t - t0) / max(1e-9, t1 - t0))
                ease += a["m"] * span * 0.5 * (1.0 + math.cos(math.pi * off / a["deg"]))
    out = radius + ease
    for c in spec.get("cinch", ()):
        w = max(0.0, 1.0 - abs(t - c["t"]) / c["width"])
        w = w * w * (3.0 - 2.0 * w)
        out = out + (raw + c["ease_m"] - out) * w
    folds = spec.get("folds")
    if folds and t > folds.get("from", 0.5):
        ## A few broad folds, growing from `from` to the piece's end (the hem).
        ramp = (t - folds["from"]) / max(1e-6, 1.0 - folds["from"])
        out += folds["amp_m"] * ramp * 0.5 * (1.0 + math.cos(folds["count"] * theta + folds.get("phase", 0.0)))
    return max(out, raw + 0.6 * _profile(spec, "ease_m", t, 0.004))


## ---------------------------------------------------------------- pieces

## Per vertex: the skin point its ray was cast to (the anatomy it was built over). Weights
## are sampled there, never at the skin nearest the cloth: at a crease such as the armpit
## the nearest skin is often the other side's (a torso vertex taking the arm's weights).
ANCHOR = "riposte_anchor"


def _vert(bm, co, anchor):
    v = bm.verts.new(co)
    layer = bm.verts.layers.float_vector.get(ANCHOR)
    if layer is not None:
        v[layer] = anchor
    return v


def _grid_faces(bm, grid, cyclic):
    faces = []
    for r0, r1 in zip(grid, grid[1:]):
        n = len(r0)
        for k in range(n if cyclic else n - 1):
            a, b = r0[k], r0[(k + 1) % n]
            c, d = r1[(k + 1) % n], r1[k]
            if len({a, b, c, d}) == 4:
                faces.append(bm.faces.new([a, b, c, d]))
    return faces


def _tube(frame, bm, spec, mirror):
    """Rings along a bone path: closed (`around` columns) or over azimuth `arcs` (each
    `columns` wide); `start` / `end` shape its two edges as smooth curves (`_end_offset`);
    `hull` (or rows below `hull_below`) spans the legs; `cap_end` closes the far end (a toe);
    `sole_m` flattens it on the sole."""
    points = [_station(frame, s, mirror) for s in spec["path"]]
    if spec.get("centre_on"):
        ## Only the first `centre_stations` stations' span is centred (a slice across a bend
        ## cuts the limb above it and pulls the path off); the rest carries its last shift.
        n = spec.get("centre_stations", len(points))
        dense = _dense(points[:n])
        head = centred(frame, dense, _side(spec["centre_on"], "R" if mirror else "L"))
        shift = head[-1] - dense[-1]
        points = head + [p + shift for p in (_dense(points[n - 1:])[1:] if n < len(points) else [])]
    path = _Path(points)
    rows = spec.get("rows", 8)
    hull_z = _station(frame, spec["hull_below"], mirror).z if spec.get("hull_below") else None
    faces, hanging = [], set()
    for arc in (spec.get("arcs") or [None]):
        if arc is None:
            n = spec.get("around", 16)
            thetas = [2.0 * math.pi * k / n for k in range(n)]
            us = [None] * n
            cyclic = True
        else:
            a0, a1 = (-arc[1], -arc[0]) if mirror else arc
            n = max(2, spec.get("columns", 6))
            thetas = [math.radians(a0 + (a1 - a0) * k / (n - 1)) for k in range(n)]
            us = [-1.0 + 2.0 * k / (n - 1) for k in range(n)]
            cyclic = False
        s0 = [_end_offset(spec.get("start"), th, u) / path.length for th, u in zip(thetas, us)]
        s1 = [1.0 + _end_offset(spec.get("end"), th, u) / path.length for th, u in zip(thetas, us)]
        def param(i, k, s0=s0, s1=s1):
            return s0[k] + (s1[k] - s0[k]) * i / (rows - 1)

        hull_rows = {i for i in range(rows) if spec.get("hull") or (hull_z is not None and path.at(param(i, 0))[0].z < hull_z)}

        def origin_dir(i, k, param=param, thetas=thetas):
            s = param(i, k)
            return path.at(s)[0], path.direction(s, thetas[k])

        sections = spec.get("section", spec.get("centre_on"))
        pool = None
        if sections:
            pool = _section(frame, sections)
            if spec.get("half"):
                ## Its own half of the body only: two legs of trousers meet at the midline.
                mid = frame["bones"]["Hips"][0].x
                pool = pool[pool[:, 0] < mid] if mirror else pool[pool[:, 0] > mid]
        measured = _bounded(frame, _section_raw(pool, path, rows, thetas, param), origin_dir) if pool is not None else None
        raw, radius = _radii(frame, spec, rows, n, origin_dir, cyclic, hull_rows, raw=measured)
        grid = []
        for i in range(rows):
            row = []
            for k in range(n):
                origin, direction = origin_dir(i, k)
                row.append(_vert(bm, origin + direction * _shape(spec, i / (rows - 1), thetas[k], radius[i][k], raw[i][k], direction),
                                 origin + direction * raw[i][k]))
            grid.append(row)
        mine = _grid_faces(bm, grid, cyclic)
        if spec.get("cap_end") and cyclic:
            tangent = path.at(1.0)[1]
            ring = sum((v.co for v in grid[-1]), Vector()) / n
            tip = bm.verts.new(ring + tangent * spec.get("cap_m", 0.01))
            mine += [bm.faces.new([grid[-1][k], grid[-1][(k + 1) % n], tip]) for k in range(n)]
        if spec.get("sole_m") is not None:
            for v in {v for f in mine for v in f.verts}:
                v.co.z = max(v.co.z, frame["sole_z"] - spec["sole_m"])
        faces += mine
        hanging |= {v for i in hull_rows for v in grid[i]}
    return faces, hanging


def _dense(points, step=0.03):
    """A polyline resampled every `step` m (stations for `centred`)."""
    out = [points[0]]
    for a, b in zip(points, points[1:]):
        n = max(1, int((b - a).length / step))
        out += [a.lerp(b, k / n) for k in range(1, n + 1)]
    return out


def _cone_angle(direction, axis):
    return math.degrees(direction.angle(axis))


def _crossing(a, b, field, fa, fb):
    """The point on edge a-b where `field` is zero (bisection; the field is not linear)."""
    lo, hi, flo = 0.0, 1.0, fa
    for _n in range(CUT_BISECT):
        mid = (lo + hi) * 0.5
        fm = field(a.lerp(b, mid))
        if (fm < 0.0) == (flo < 0.0):
            lo, flo = mid, fm
        else:
            hi = mid
    return (lo + hi) * 0.5


def _cut(bm, faces, field):
    """`faces` cut along the curve field == 0 and its negative side removed: every edge the
    curve crosses is split exactly on it and each face joined across, so an opening's edge
    is the curve itself, never a staircase of whole faces. A vertex within CUT_SNAP of a
    crossing (along its edge) is moved onto the curve instead (no sliver faces)."""
    bm.edges.index_update()
    bm.faces.index_update()
    mine = sorted(set(faces), key=lambda f: f.index)
    value = {v: field(v.co) for f in faces for v in f.verts}

    def edges():
        bm.edges.index_update()
        return sorted({e for f in mine if f.is_valid for e in f.edges}, key=lambda e: e.index)

    for e in edges():
        a, b = e.verts
        fa, fb = value[a], value[b]
        if fa == 0.0 or fb == 0.0 or (fa < 0.0) == (fb < 0.0):
            continue
        t = _crossing(a.co, b.co, field, fa, fb)
        if t < CUT_SNAP:
            a.co, value[a] = a.co.lerp(b.co, t), 0.0
        elif t > 1.0 - CUT_SNAP:
            b.co, value[b] = a.co.lerp(b.co, t), 0.0
    for e in edges():
        a, b = e.verts
        fa, fb = value[a], value[b]
        if fa == 0.0 or fb == 0.0 or (fa < 0.0) == (fb < 0.0):
            continue
        t = _crossing(a.co, b.co, field, fa, fb)
        _edge, v = bmesh.utils.edge_split(e, a, t)
        v.co = a.co.lerp(b.co, t)
        value[v] = 0.0
    out = []
    for f in [f for f in mine if f.is_valid]:
        zeros = [v for v in f.verts if value.get(v) == 0.0]
        split = None
        if len(zeros) == 2 and not any(e for e in f.edges if zeros[0] in e.verts and zeros[1] in e.verts):
            split = bmesh.utils.face_split(f, zeros[0], zeros[1])[0]
        for g in (f, split) if split is not None else (f,):
            out.append(g)
    doomed = [f for f in out if f.is_valid and sum(value.get(v, 0.0) for v in f.verts) < 0.0
              and all(value.get(v, 0.0) <= 0.0 for v in f.verts)]
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    return [f for f in out if f.is_valid]


def _torso(frame, bm, spec, mirror):
    """The torso: rings round the spine (hem -> chest), a yoke of rays from the chest
    centre over the shoulders, its neck and arm openings cones of constant angle, and
    sleeves grown from the arm openings."""
    ## `spine` runs from the hem station up to the chest centre (the yoke's origin).
    spine = _Path([_station(frame, s) for s in spec["spine"]])
    centre = spine.at(1.0)[0] + Vector(spec.get("centre_offset", (0.0, 0.0, 0.0)))
    n = spec.get("around", 28)
    rows_t, rows_y = spec.get("rows", 8), spec.get("yoke_rows", 6)
    thetas = [2.0 * math.pi * k / n for k in range(n)]
    yoke_top = math.radians(spec.get("yoke_deg", 84.0))
    hem = [_end_offset(spec.get("hem"), th) / spine.length for th in thetas]

    def origin_dir(i, k):
        if i <= rows_t - 1:
            ## Ring i of the tube: from the hem curve (i = 0) up to the chest ring.
            s = hem[k] + (1.0 - hem[k]) * i / (rows_t - 1)
            return spine.at(s)[0], spine.direction(s, thetas[k])
        phi = yoke_top * (i - rows_t + 1) / rows_y
        d = spine.direction(1.0, thetas[k])
        return centre, (d * math.cos(phi) + UP * math.sin(phi)).normalized()

    rows = rows_t + rows_y
    hull_rows = set()
    if spec.get("hull_below"):
        z = _station(frame, spec["hull_below"]).z
        hull_rows = {i for i in range(rows_t) if origin_dir(i, 0)[0].z < z}
    ## The drape hangs from the chest ring down (the yoke's rays rise from the chest centre;
    ## their lengths are not the rings').
    raw, radius = _radii(frame, spec, rows, n, origin_dir, True, hull_rows, downward=False, drape_rows=rows_t)
    grid = []
    for i in range(rows):
        row = []
        for k in range(n):
            origin, direction = origin_dir(i, k)
            row.append(_vert(bm, origin + direction * _shape(spec, 1.0 - i / (rows - 1), thetas[k], radius[i][k], raw[i][k], direction),
                             origin + direction * raw[i][k]))
        grid.append(row)
    faces = _grid_faces(bm, grid, True)
    ## The yoke before its openings are cut: a sleeve tucks under it continuously.
    bm.verts.index_update()
    whole = BVHTree.FromPolygons([v.co.copy() for v in bm.verts], [[v.index for v in f.verts] for f in faces])
    ## Openings: cones from the chest centre; their boundary vertices are carried onto the
    ## cone (constant angle), so every opening is a smooth loop.
    openings = []
    neck = spec.get("neck")
    if neck:
        axis = (_station(frame, {"bone": "Neck", "at": 0.6}) - centre).normalized()
        v_deg, v_width = neck.get("v_deg", 0.0), math.radians(neck.get("v_width_deg", 40.0))

        def neck_limit(direction, axis=axis):
            flat = direction - UP * direction.dot(UP)
            front = math.atan2(flat.x, -flat.y) if flat.length > 1e-6 else 0.0
            x = max(0.0, 1.0 - abs(front) / v_width)
            return neck["deg"] + v_deg * x ** 1.5

        openings.append((axis, neck_limit))
    fields = []
    for axis, limit in openings:
        def field(co, axis=axis, limit=limit):
            u = (co - centre).normalized()
            return _cone_angle(u, axis) - limit(u)
        fields.append(field)
    arms = spec.get("arms") or {}
    for side in arms.get("sides", ()):
        joint = _station(frame, {"bone": "UpperArm.%s" % side, "at": 0.0})
        axis = (joint - centre).normalized()

        def cone(co, axis=axis, deg=arms["deg"]):
            return _cone_angle((co - centre).normalized(), axis) - deg
        if arms.get("armscye_m") is not None:
            ## A set-in sleeve's armscye: a plane across the upper arm's own axis at the
            ## shoulder joint (a cone about the chest-to-shoulder line is tilted against an
            ## arm hanging in the rest pose; no sleeve can follow its edge without folding),
            ## within the cone `deg` (the plane alone runs on down the torso's side).
            arm = (_station(frame, {"bone": "UpperArm.%s" % side, "at": 1.0}) - joint).normalized()
            fields.append(lambda co, joint=joint, arm=arm, m=arms["armscye_m"], cone=cone:
                          max((m - (co - joint).dot(arm)) * ARMSCYE_DEG_PER_M, cone(co)))
        else:
            fields.append(cone)
    for field in fields:
        faces = _cut(bm, faces, field)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    faces = [f for f in faces if f.is_valid]
    hanging = {v for i in hull_rows for v in grid[i] if v.is_valid}
    yoke_ease = _profile(spec, "ease_m", 0.0, 0.004)
    for side in (spec.get("sleeves") or {}).get("sides", ()):
        faces += _grow(frame, bm, spec["sleeves"], side, centre, faces, yoke_ease, whole)
    return faces, hanging


def _limb_path(frame, spec, side):
    points = [_station(frame, _side(s, side)) for s in spec["path"]]
    if spec.get("centre_on"):
        points = centred(frame, _dense(points), _side(spec["centre_on"], side))
    return _Path(points)


def _grow(frame, bm, spec, side, centre, faces, torso_ease, torso):
    """A sleeve set into its arm opening (see `_extend`): of the torso's closed boundary
    loops, the one aimed most squarely at the arm."""
    path = _limb_path(frame, spec, side)
    toward = (path.at(0.0)[0] - centre).normalized()
    mine = set(faces)
    loops = [lp for lp in _loops(bm, mine) if len(lp) >= 6]
    if not loops:
        return []
    loop = max(loops, key=lambda lp: ((sum((v.co for v in lp), Vector()) / len(lp)) - centre).normalized().dot(toward))
    ## The armhole edge is a smooth curve (the cone's cut is irregular on the torso's grid),
    ## lifted back to the torso's ease where smoothing pulled it into the convex shoulder.
    for _p in range(LOOP_SMOOTH):
        moved = [v.co * 0.5 + (loop[n - 1].co + loop[(n + 1) % len(loop)].co) * 0.25 for n, v in enumerate(loop)]
        for v, co in zip(loop, moved):
            v.co = co
    for v in loop:
        location, normal, _i, _d = frame["tree"].find_nearest(v.co)
        if location is not None and (v.co - location).dot(normal) < torso_ease:
            v.co = location + normal * torso_ease
    under = max(MIN_UNDER_EASE_M, torso_ease - TUCK_CLEAR_M)
    spec = dict(spec, _mirror=side == "R")
    return _extend(frame, bm, spec, path, loop, under, torso, _side(spec.get("section", spec.get("centre_on")), side))


def _loops(bm, faces):
    """The closed boundary loops of `faces`, each an ordered vertex list."""
    edges = [e for e in bm.edges if e.is_boundary and e.link_faces and e.link_faces[0] in faces]
    adj = {}
    for e in edges:
        a, b = e.verts
        adj.setdefault(a, []).append(b)
        adj.setdefault(b, []).append(a)
    seen, out = set(), []
    for start in adj:
        if start in seen or len(adj[start]) != 2:
            continue
        loop, prev, cur = [start], None, start
        seen.add(start)
        while True:
            nxt = [v for v in adj[cur] if v is not prev]
            if not nxt or nxt[0] is start or nxt[0] in seen or len(adj[nxt[0]]) != 2:
                break
            prev, cur = cur, nxt[0]
            seen.add(cur)
            loop.append(cur)
        if start in adj[cur]:
            out.append(loop)
    return out


def _extend(frame, bm, spec, path, loop, under_ease, torso, sections=None):
    """A set-in sleeve tucked under its arm opening `loop`: its own rings of `around`
    columns centred on the arm, from `tuck_m` inside the opening's innermost point to `end`.
    Where the torso lies over it (up to the opening's outermost point) the sleeve keeps
    within `under_ease` of the skin and TUCK_CLEAR_M inside the torso's surface (`torso`)
    along its own ray, so the torso's finished armhole edge (rim and lip) sits over it as
    a seam and the body never shows between them. (A sleeve welded to the cone's cut, which
    is tilted and irregular on the torso's converging yoke, folds and webs.)"""
    rows = spec.get("rows", 8)
    cols = spec.get("around", 14)
    end = spec.get("end", 1.0)
    seats = [path.param(v.co) for v in loop]
    thetas = [2.0 * math.pi * k / cols for k in range(cols)]
    ## Each column is tucked up to where the opening's edge crosses it (the edge is tilted).
    edge = sorted(((path.angle(s, v.co) % (2.0 * math.pi), s) for s, v in zip(seats, loop)))
    edge = [(edge[-1][0] - 2.0 * math.pi, edge[-1][1])] + edge + [(edge[0][0] + 2.0 * math.pi, edge[0][1])]

    def edge_at(theta):
        theta %= 2.0 * math.pi
        for (a0, s0), (a1, s1) in zip(edge, edge[1:]):
            if a0 <= theta <= a1:
                return s0 + (s1 - s0) * (theta - a0) / max(1e-9, a1 - a0)
        return max(seats)

    covered = [edge_at(t) for t in thetas]
    if spec.get("set_in") == "bridge":
        return _bridged(frame, bm, spec, path, loop, end, sections)
    ## Each column starts `tuck_m` inside the opening's edge where it crosses that column (the
    ## sleeve's top follows the armhole like a set-in sleeve's cap), never from the opening's
    ## innermost point (its tuck would run across the back as a sheet).
    starts = [max(-0.5, c - spec.get("tuck_m", TUCK_M) / path.length) for c in covered]

    def param(i, k):
        return starts[k] + (end - starts[k]) * i / (rows - 1)

    def origin_dir(i, k):
        s = param(i, k)
        return path.at(s)[0], path.direction(s, thetas[k])

    measured = _bounded(frame, _section_raw(_section(frame, sections), path, rows, thetas, param), origin_dir) if sections else None
    raw, radius = _radii(frame, spec, rows, cols, origin_dir, True, raw=measured)
    grid = []
    for i in range(rows):
        row = []
        for k in range(cols):
            origin, direction = origin_dir(i, k)
            free = _shape(spec, i / (rows - 1), thetas[k], radius[i][k], raw[i][k], direction)
            tucked = min(free, radius[i][k] + under_ease)
            hit = torso.ray_cast(origin, direction, free + TUCK_CLEAR_M)[0]
            if hit is not None:
                tucked = min(tucked, (hit - origin).length - TUCK_CLEAR_M)
            tucked = max(raw[i][k] + max(MIN_UNDER_EASE_M, under_ease * TUCK_FLOOR), tucked)
            ## Tucked under the yoke to the opening's outer edge, free a little beyond it.
            w = max(0.0, min(1.0, (param(i, k) - covered[k]) * path.length / TUCK_FADE_M))
            r = tucked + (free - tucked) * w * w * (3.0 - 2.0 * w)
            row.append(_vert(bm, origin + direction * r, origin + direction * raw[i][k]))
        grid.append(row)
    return _grid_faces(bm, grid, True)


def _bridged(frame, bm, spec, path, loop, end, sections):
    """A sleeve sewn into its arm opening (`set_in: "bridge"`): the opening's loop is the
    sleeve's first ring, so shirt and sleeve are one continuous surface (no tucked second
    layer to step out of the yoke at the front of the armpit)."""
    rows = spec.get("rows", 8)
    ## One column per vertex of the opening, in its own order round the arm: the opening is
    ## the sleeve's first ring (explicit pairing; a bridge of unequal loops fans and twists).
    seats = [path.param(v.co) for v in loop]
    thetas = [path.angle(s, v.co) % (2.0 * math.pi) for s, v in zip(seats, loop)]
    turn = sum(((b - a + math.pi) % (2.0 * math.pi)) - math.pi for a, b in zip(thetas, thetas[1:] + thetas[:1]))
    if turn < 0.0:
        loop, seats, thetas = loop[::-1], seats[::-1], thetas[::-1]
    cols = len(loop)
    grade = spec.get("cap_grade", BRIDGE_GRADE)

    def param(i, k):
        ## Rows graded towards the shoulder: the cap turns and the joint bends there.
        return seats[k] + (end - seats[k]) * (i / (rows - 1)) ** grade

    def origin_dir(i, k):
        ## The sleeve's surface is cast from the arm's own axis only: behind the shoulder
        ## joint the axis runs into the torso.
        s = max(param(i, k), CAP_FROM)
        return path.at(s)[0], path.direction(s, thetas[k])

    measured = _bounded(frame, _section_raw(_section(frame, sections), path, rows, thetas, param), origin_dir) if sections else None
    raw, radius = _radii(frame, spec, rows, cols, origin_dir, True, raw=measured)
    layer = bm.verts.layers.float_vector.get(ANCHOR)
    grid = [list(loop)]
    for i in range(1, rows):
        row = []
        for k in range(cols):
            origin, direction = origin_dir(i, k)
            r = _shape(spec, (i / (rows - 1)) ** grade, thetas[k], radius[i][k], raw[i][k], direction)
            along = (param(i, k) - seats[k]) * path.length
            ## The cap leaves the armhole seam and blends onto the sleeve's surface (no step).
            w = _smooth01(along / BRIDGE_BLEND_M)
            anchor = origin + direction * raw[i][k]
            ## Underarm cloth near the seam spans the armpit hollow: it follows the hollow's
            ## own skin, the skin nearest it, so a forward reach does not carry it off the
            ## hollow with the arm (a ray from the arm's axis lands on the arm). The top of the
            ## cap follows the arm.
            under = min(1.0, max(0.0, -direction.z / UNDERARM_Z)) * (1.0 - _smooth01(along / SEAM_WEIGHT_M))
            co = loop[k].co.lerp(origin + direction * r, w)
            if under > 0.0:
                beneath = frame["tree"].find_nearest(co)[0]
                if beneath is not None:
                    anchor = anchor.lerp(beneath, under)
            row.append(_vert(bm, co, anchor))
        grid.append(row)
    _relax_cap(frame, bm, grid, spec.get("cap_relax_rows", CAP_RELAX_ROWS), _profile(spec, "ease_m", 0.0, 0.004))
    return _grid_faces(bm, grid, True)


def _relax_cap(frame, bm, grid, rows, ease):
    """Rows cast round a shoulder joint fold where the cap turns. The cap's first `rows` rows
    relax towards their grid neighbours (seam and the sleeve beyond held), each pass held at
    the cap's ease off the skin: a smooth cap between two fixed edges. A vertex's anchor moves
    with it along the skin (its weights are those of the skin beneath it)."""
    cols = len(grid[0])
    layer = bm.verts.layers.float_vector.get(ANCHOR)
    for _ in range(CAP_RELAX_PASSES):
        moved = {}
        for i in range(1, min(rows, len(grid) - 1) + 1):
            for k in range(cols):
                v = grid[i][k]
                mean = (grid[i - 1][k].co + grid[i + 1][k].co + grid[i][k - 1].co + grid[i][(k + 1) % cols].co) * 0.25
                skin, normal, _f, _d = frame["tree"].find_nearest(v.co, CAP_RELAX_REACH_M)
                step = (mean - v.co) * CAP_RELAX
                if skin is not None:
                    ## Along the skin only: a convex cap relaxed freely shrinks into the deltoid.
                    step -= normal * step.dot(normal)
                co = v.co + step
                skin, normal, _f, _d = frame["tree"].find_nearest(co, CAP_RELAX_REACH_M)
                if skin is not None and (co - skin).dot(normal) < ease:
                    co = skin + normal * ease
                moved[v] = (co, step)
        for v, (co, step) in moved.items():
            v.co = co
            if layer is not None:
                v[layer] = Vector(v[layer]) + step

def _smooth01(x):
    x = min(1.0, max(0.0, x))
    return x * x * (3.0 - 2.0 * x)


def _cap(frame, bm, spec, mirror):
    """A dome of rays from a joint within a cone about `axis`: a fitted shoulder piece whose
    edge is a smooth loop by construction."""
    centre = _station(frame, spec["centre"], mirror)
    axis = _vec(spec["axis"], mirror)
    ref = (FRONT - axis * FRONT.dot(axis)).normalized()
    side = axis.cross(ref).normalized()
    rings, around = spec.get("rings", 5), spec.get("around", 16)
    limit = math.radians(spec["deg"])
    apex = bm.verts.new(centre)
    grid, dirs = [], []
    for i in range(1, rings + 1):
        psi = limit * i / rings
        row = []
        for k in range(around):
            beta = 2.0 * math.pi * k / around
            d = (axis * math.cos(psi) + (ref * math.cos(beta) + side * math.sin(beta)) * math.sin(psi)).normalized()
            row.append(d)
        dirs.append(row)
    raw = [[_cast(frame, centre, d) for d in row] for row in dirs]
    ## A ray that runs out through the torso is not the shoulder's surface: dropped.
    known = sorted(v for row in raw for v in row if v is not None)
    if known:
        limit_r = known[len(known) // 2] * CAP_REACH
        raw = [[v if v is not None and v <= limit_r else None for v in row] for row in raw]
    raw = _lift(frame, _fill(raw, True), lambda i, k: (centre, dirs[i][k]))
    radius = _envelope(raw, True, spec.get("smooth", ENVELOPE_PASSES))
    top = _lift(frame, [[_cast(frame, centre, axis) or radius[0][0]]], lambda i, k: (centre, axis))[0][0]
    apex.co = centre + axis * (top + _profile(spec, "ease_m", 0.0, 0.01))
    for i, row in enumerate(dirs):
        grid.append([_vert(bm, centre + d * _shape(spec, (i + 1) / rings, 0.0, radius[i][k], raw[i][k]), centre + d * raw[i][k])
                     for k, d in enumerate(row)])
    faces = [bm.faces.new([apex, grid[0][k], grid[0][(k + 1) % around]]) for k in range(around)]
    faces += _grid_faces(bm, grid, True)
    return faces, set()


def _plate(frame, bm, spec, mirror, over):
    point = _station(frame, spec, mirror)
    toward = _vec(spec["toward"], mirror)
    origin = point + toward * 0.6
    hit, normal = None, None
    if over is not None:
        hit, normal, _i, _d = over.ray_cast(origin, -toward, 0.8)
    if hit is None:
        hit, normal, _i, _d = frame["tree"].ray_cast(origin, -toward, 0.8)
    if hit is None:
        hit, normal = point, toward
    normal = normal.normalized()
    w, h, d = spec["size"]
    made = bmesh.new()
    bmesh.ops.create_cube(made, size=1.0)
    x = UP.cross(normal).normalized() if abs(UP.dot(normal)) < 0.95 else Vector((1.0, 0.0, 0.0))
    y = normal.cross(x).normalized()
    basis = Matrix((x * w, y * h, normal * d)).transposed().to_4x4()
    basis.translation = hit + normal * (d * 0.5)
    bmesh.ops.transform(made, matrix=basis, verts=made.verts)
    bmesh.ops.bevel(made, geom=list(made.edges), offset=min(w, h, d) * 0.25, segments=1, affect="EDGES")
    mesh = bpy.data.meshes.new("_plate")
    made.to_mesh(mesh)
    made.free()
    start = len(bm.faces)
    bm.from_mesh(mesh)
    bpy.data.meshes.remove(mesh)
    bm.faces.ensure_lookup_table()
    return list(bm.faces[start:]), set()


def _rims(bm, faces, thickness):
    """Every opening of `faces` gets its rim (the cloth's thickness) and a lip folded
    inward, so an edge reads as cloth or leather with substance, never a paper cut."""
    mine = set(faces)
    for f in faces:
        f.normal_update()
    edges = [e for e in bm.edges if e.is_boundary and e.link_faces and e.link_faces[0] in mine]
    if thickness <= 0.0 or not edges:
        return []
    boundary = {v for e in edges for v in e.verts}
    normal, inner = {}, {}
    for v in boundary:
        n = sum((f.normal for f in v.link_faces if f in mine), Vector())
        normal[v] = n.normalized() if n.length > 1e-9 else Vector((0.0, 0.0, 1.0))
        ## Along the surface, away from the opening (where the lip folds back to).
        away = [e.other_vert(v) for e in v.link_edges if e.other_vert(v) not in boundary]
        inner[v] = ((sum((w.co for w in away), Vector()) / len(away)) - v.co).normalized() if away else -normal[v]
    rim = bmesh.ops.extrude_edge_only(bm, edges=edges)
    made = [g for g in rim["geom"] if isinstance(g, bmesh.types.BMFace)]
    origin = {}
    for v in [g for g in rim["geom"] if isinstance(g, bmesh.types.BMVert)]:
        src = next(e.other_vert(v) for e in v.link_edges if e.other_vert(v) in boundary)
        origin[v] = src
        v.co = src.co - normal[src] * thickness
    rim_edges = [g for g in rim["geom"] if isinstance(g, bmesh.types.BMEdge) and all(x in origin for x in g.verts)]
    lip = bmesh.ops.extrude_edge_only(bm, edges=rim_edges)
    made += [g for g in lip["geom"] if isinstance(g, bmesh.types.BMFace)]
    for v in [g for g in lip["geom"] if isinstance(g, bmesh.types.BMVert)]:
        src = next(e.other_vert(v) for e in v.link_edges if e.other_vert(v) in origin)
        v.co = src.co + inner[origin[src]] * LIP_M
    return made


BUILDERS = {"tube": _tube, "torso": _torso, "cap": _cap}


def _under_tree(objects):
    """One surface tree of the garments `objects` (world, rims and lips left out)."""
    points, polys = [], []
    for obj in objects:
        rims = obj.data.attributes.get("riposte_rim")
        rim = [d.value for d in rims.data] if rims else [False] * len(obj.data.polygons)
        start = len(points)
        points += [obj.matrix_world @ v.co for v in obj.data.vertices]
        polys += [[start + i for i in p.vertices] for p, is_rim in zip(obj.data.polygons, rim) if not is_rim]
    return BVHTree.FromPolygons(points, polys) if polys else None


def build(frame, definition, materials, name, under=()):
    """The garment `definition` constructed on `frame` (`body_frame`) over the garment objects
    `under` (built before it, beneath it): one object, its pieces as tagged faces, the body's
    weights, its materials. Returns (object, report)."""
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bm = bmesh.new()
    bm.verts.layers.float_vector.new(ANCHOR)
    pieces, slots, owner, rigid, hanging, rims = [], [], {}, {}, set(), set()
    frame = dict(frame, under_tree=_under_tree(under))
    obstacles = [(frame["samples"], BODY_GAP_M, RESOLVE_BODY_DEPTH_M)] + [(garment_samples(o), LAYER_GAP_M, RESOLVE_DEPTH_M) for o in under]
    pushed = 0
    for piece in definition["design"]["pieces"]:
        for side in piece.get("sides", [None]):
            ## A piece built per side fills its "{s}"; a piece that builds both sides itself
            ## (trousers, a torso's sleeves) keeps them for its own parts.
            spec = _side(piece, side) if side else piece
            mirror = side == "R"
            kind = spec.get("kind", "tube")
            if kind == "plate":
                bm.verts.index_update()
                built = [f for f in bm.faces]
                over = BVHTree.FromPolygons([v.co for v in bm.verts], [[v.index for v in f.verts] for f in built]) if built else None
                faces, hang = _plate(frame, bm, spec, mirror, over)
            else:
                faces, hang = BUILDERS[kind](frame, bm, spec, mirror)
                faces = [f for f in faces if f.is_valid]
                if "noresolve" not in os.environ.get("RIPOSTE_GARMENT_DEBUG", ""):
                    bm.verts.index_update()
                    pushed += _resolve(bm, faces, obstacles)
                bmesh.ops.recalc_face_normals(bm, faces=faces)
                _outward(frame, faces)
                if "norims" not in os.environ.get("RIPOSTE_GARMENT_DEBUG", ""):
                    made = _rims(bm, faces, spec.get("thickness_m", 0.003))
                    rims.update(made)
                    faces += made
                bmesh.ops.recalc_face_normals(bm, faces=faces)
                _outward(frame, faces)
            hanging |= hang
            pieces.append(spec["name"])
            ## `edge_material`: the rims and lips in their own slot (a leather edge's value).
            edge = spec.get("edge_material", spec["material"])
            for m in (spec["material"], edge):
                if m not in slots:
                    slots.append(m)
            for f in faces:
                f.material_index = slots.index(edge if f in rims else spec["material"])
                owner[f] = len(pieces) - 1
                if kind == "plate":
                    rigid[f] = spec["bone"]
    if "noclear" not in os.environ.get("RIPOSTE_GARMENT_DEBUG", ""):
        _clear(frame, bm, [f for f in bm.faces if f not in rigid], definition["design"].get("min_gap_m", 0.002))
    bm.faces.ensure_lookup_table()
    owners = [owner.get(f, 0) for f in bm.faces]
    bones = [rigid.get(f) for f in bm.faces]
    rim_flags = [f in rims for f in bm.faces]
    hang_index = set()
    bm.verts.index_update()
    hang_index = {v.index for v in hanging if v.is_valid}
    bm.to_mesh(mesh)
    bm.free()
    for slot in slots:
        mesh.materials.append(materials[slot])
    mesh.shade_smooth()
    _crease(mesh)
    mesh.attributes.new("riposte_mass", "INT", "FACE").data.foreach_set("value", owners)
    mesh.attributes.new("riposte_rim", "BOOLEAN", "FACE").data.foreach_set("value", rim_flags)
    obj["riposte_masses"] = pieces
    regions = sorted(set(frame["region_of"].values()))
    mesh.attributes.new("riposte_region", "INT", "FACE").data.foreach_set(
        "value", [regions.index(_region_under(frame, p.center)) for p in mesh.polygons])
    obj["riposte_regions"] = regions
    _weights(obj, frame, bones, hang_index, definition["design"].get("weights"))
    if ANCHOR in mesh.attributes:
        mesh.attributes.remove(mesh.attributes[ANCHOR])
    inside, deepest = _inside_body(frame, mesh)
    return obj, {"triangles": sum(len(p.vertices) - 2 for p in mesh.polygons), "pieces": pieces, "materials": slots,
                 "inside_body_vertices": inside, "deepest_mm": round(deepest * 1000, 1), "resolved_vertices": pushed}


def _samples(points, normals):
    """Obstacle samples (numpy points, numpy outward normals) for `_resolve`."""
    import numpy as np
    return np.array([tuple(p) for p in points], dtype=float).reshape(-1, 3), np.array([tuple(n) for n in normals], dtype=float).reshape(-1, 3)


def garment_samples(obj):
    """A built garment as obstacle samples for the layers over it: its vertices and face
    centres with their outward normals, its rims and lips (thickness, facing any way) left out."""
    mesh = obj.data
    world = obj.matrix_world
    rot = world.to_3x3()
    rims = mesh.attributes.get("riposte_rim")
    rim = [d.value for d in rims.data] if rims else [False] * len(mesh.polygons)
    points, normals, normal_sum = [], [], {}
    for poly, is_rim in zip(mesh.polygons, rim):
        if is_rim:
            continue
        n = (rot @ poly.normal).normalized()
        points.append(world @ poly.center)
        normals.append(n)
        for i in poly.vertices:
            normal_sum[i] = normal_sum.get(i, Vector()) + n
    for i in sorted(normal_sum):
        if normal_sum[i].length > 1e-9:
            points.append(world @ mesh.vertices[i].co)
            normals.append(normal_sum[i].normalized())
    return _samples(points, normals)


def _resolve(bm, faces, obstacles, reach=RESOLVE_DEPTH_M):
    """Collision with what lies beneath: for each obstacle (samples, gap, depth), every sample
    casts outward from `depth` behind itself; a face of `faces` met before the sample's gap
    is pushed out along the sample's normal by the shortfall, its neighbours a share of it (a
    smooth bulge over a bulge beneath, never a dent or a spike)."""
    import numpy as np
    verts = sorted({v for f in faces for v in f.verts}, key=lambda v: v.index)
    if not verts:
        return 0
    local = {v: n for n, v in enumerate(verts)}
    moved = 0
    for _p in range(RESOLVE_PASSES):
        co = np.array([tuple(v.co) for v in verts])
        lo, hi = co.min(axis=0) - reach, co.max(axis=0) + reach
        tree = BVHTree.FromPolygons([v.co for v in verts], [[local[v] for v in f.verts] for f in faces])
        push = {}
        for (points, normals), gap, depth in obstacles:
            if not len(points):
                continue
            near = np.nonzero(np.all((points >= lo) & (points <= hi), axis=1))[0]
            for j in near:
                p, n = Vector(points[j]), Vector(normals[j])
                hit, hn, fi, dist = tree.ray_cast(p - n * depth, n, depth + gap)
                if hit is None or abs(hn.dot(n)) < RESOLVE_ALIGN:
                    continue
                need = depth + gap - dist
                for v in faces[fi].verts:
                    if v not in push or need > push[v][0]:
                        push[v] = (need, n)
        if not push:
            break
        moved = max(moved, len(push))
        spread = dict(push)
        for v, (need, n) in push.items():
            for e in v.link_edges:
                w = e.other_vert(v)
                if w in local and w not in push and (w not in spread or need * RESOLVE_SPREAD > spread[w][0]):
                    spread[w] = (need * RESOLVE_SPREAD, n)
        for v in sorted(spread, key=lambda v: v.index):
            need, n = spread[v]
            v.co += n * need
    return moved


def _outward(frame, faces):
    """Faces point away from the body (single-sided cloth is seen from outside)."""
    flip = []
    for f in faces:
        c = f.calc_center_median()
        location, normal, _i, _d = frame["tree"].find_nearest(c)
        if location is not None and f.normal.dot(c - location) < 0.0:
            flip.append(f)
    if len(flip) > len(faces) / 2:
        for f in faces:
            f.normal_flip()


def _clear(frame, bm, faces, gap):
    """No cloth vertex nearer the skin than `gap`, then no face centre or edge midpoint
    (a sparse ring's chord or a sheared sleeve quad dips into a convex muscle between its
    vertices): such a face is lifted whole by its deepest shortfall."""
    for v in {v for f in faces for v in f.verts}:
        location, normal, _i, _d = frame["tree"].find_nearest(v.co)
        if location is not None and (v.co - location).dot(normal) < gap:
            v.co = location + normal * gap
    for _p in range(CLEAR_FACE_PASSES):
        lift = {}
        for f in faces:
            if not f.is_valid:
                continue
            probes = [f.calc_center_median()] + [(e.verts[0].co + e.verts[1].co) * 0.5 for e in f.edges]
            f.normal_update()
            facing = f.normal.copy()
            worst, along = 0.0, None
            for p in probes:
                location, normal, _i, _d = frame["tree"].find_nearest(p)
                ## Only the skin the cloth lies over (between the thighs the nearest skin
                ## can be the other leg's, facing the cloth).
                if location is None or normal.dot(facing) < CLEAR_FACE_ALIGN:
                    continue
                short = gap - (p - location).dot(normal)
                if short > worst:
                    worst, along = short, normal
            if along is not None:
                for v in f.verts:
                    if v not in lift or worst > lift[v][0]:
                        lift[v] = (worst, along)
        if not lift:
            break
        bm.verts.index_update()
        for v in sorted(lift, key=lambda v: v.index):
            v.co += lift[v][1] * lift[v][0]


def _region_under(frame, point):
    _loc, _n, face, _d = frame["tree"].find_nearest(point)
    for i in frame["polys"][face]:
        if i in frame["region_of"]:
            return frame["region_of"][i]
    return sorted(set(frame["region_of"].values()))[0]


def _crease(mesh):
    bm = bmesh.new()
    bm.from_mesh(mesh)
    sharp = [e.index for e in bm.edges if len(e.link_faces) == 2 and math.degrees(e.calc_face_angle(0.0)) > SHARP_DEG]
    bm.free()
    attr = mesh.attributes.get("sharp_edge") or mesh.attributes.new("sharp_edge", "BOOLEAN", "EDGE")
    values = [False] * len(mesh.edges)
    for i in sharp:
        values[i] = True
    attr.data.foreach_set("value", values)


## A garment vertex deeper than this behind the (untrimmed) body surface is inside the body.
INSIDE_TOL_M = 0.0015


def _inside_body(frame, mesh):
    count, deepest = 0, 0.0
    for v in mesh.vertices:
        location, normal, _i, _d = frame["tree"].find_nearest(v.co)
        depth = -(v.co - location).dot(normal)
        if depth > INSIDE_TOL_M:
            count += 1
            deepest = max(deepest, depth)
    return count, deepest


def _arm_side(bone):
    for prefix in ARM_CHAIN:
        if bone.startswith(prefix + "."):
            return bone.rsplit(".", 1)[1]
    return None


def _policy(mixes, obj, bone_of, policy):
    """A garment's weights corrected for its construction (`design.weights`): smoothed over
    the garment's own edges (`smooth` passes; the body's weights sampled at a sparse cloth
    vertex jump across a crease like the armpit, and one edge between an arm-weighted and a
    chest-weighted vertex stretches into a web), then the arm chain capped at `arm_max`, the
    excess moved to that side's clavicle (a vest or tunic follows the torso and the shoulder
    girdle, never the humerus)."""
    passes = policy.get("smooth", WEIGHT_SMOOTH_PASSES)
    near = [[] for _v in obj.data.vertices]
    for e in obj.data.edges:
        a, b = e.vertices
        near[a].append(b)
        near[b].append(a)
    for _p in range(passes):
        out = []
        for i, mix in enumerate(mixes):
            if i in bone_of or not near[i]:
                out.append(mix)
                continue
            avg = {}
            for j in near[i]:
                for bone, w in mixes[j].items():
                    avg[bone] = avg.get(bone, 0.0) + w / len(near[i])
            keep = 1.0 - WEIGHT_SMOOTH_FACTOR
            blended = {bone: w * keep for bone, w in mix.items()}
            for bone, w in avg.items():
                blended[bone] = blended.get(bone, 0.0) + w * WEIGHT_SMOOTH_FACTOR
            out.append(blended)
        mixes = out
    cap = policy.get("arm_max")
    clavicle = policy.get("arm_to_clavicle", ARM_TO_CLAVICLE)
    if cap is not None:
        for i, mix in enumerate(mixes):
            if i in bone_of:
                continue
            for side in ("L", "R"):
                arm = sum(w for b, w in mix.items() if _arm_side(b) == side)
                if arm > cap:
                    scale = cap / arm
                    for b in [b for b in mix if _arm_side(b) == side]:
                        mix[b] *= scale
                    excess = arm - cap
                    mix["Shoulder.%s" % side] = mix.get("Shoulder.%s" % side, 0.0) + excess * clavicle
                    mix["Chest"] = mix.get("Chest", 0.0) + excess * (1.0 - clavicle)
    return mixes


def _skin_mix(frame, at):
    """The body's skin weights at the nearest body face to `at` (inverse-distance over the
    face's corners)."""
    location, _n, face, _d = frame["tree"].find_nearest(at)
    corners = frame["polys"][face]
    inv = [1.0 / max(1e-6, (frame["points"][i] - location).length) for i in corners]
    total = sum(inv)
    mix = {}
    for i, w in zip(corners, inv):
        for bone, weight in frame["weights"][i].items():
            mix[bone] = mix.get(bone, 0.0) + weight * w / total
    return mix


def _weights(obj, frame, rigid_faces, hanging, policy=None):
    """The body's skin weights at each vertex's nearest body face (inverse-distance over the
    face's corners), corrected by the garment's weight policy (`_policy`), at most
    MAX_INFLUENCES, normalized; hanging hull rows blend towards Hips; a rigid piece's
    vertices on its bone."""
    bone_of = {}
    for poly, bone in zip(obj.data.polygons, rigid_faces):
        if bone:
            for i in poly.vertices:
                bone_of[i] = bone
    mixes = []
    anchor = obj.data.attributes.get(ANCHOR)
    for v in obj.data.vertices:
        if v.index in bone_of:
            mix = {bone_of[v.index]: 1.0}
        else:
            at = Vector(anchor.data[v.index].vector) if anchor is not None else v.co
            mix = _skin_mix(frame, at if at.length_squared > 0.0 else v.co)
            if v.index in hanging:
                ## Only cloth hanging free (spanning between the legs) moves with the hips; where
                ## the hull rests on a thigh it follows the thigh (a flexed hip otherwise pushes
                ## the thigh out through it). RIPOSTE_HANG_FLAT restores the old flat share (the
                ## A/B/C/D regression diagnostic).
                if os.environ.get("RIPOSTE_HANG_FLAT"):
                    share = HULL_TO_HIPS
                else:
                    free = frame["tree"].find_nearest(v.co)[3] or 0.0
                    share = HULL_TO_HIPS * _smooth01((free - HANG_REST_M) / HANG_FREE_M)
                mix = {b: w * (1.0 - share) for b, w in mix.items()}
                mix["Hips"] = mix.get("Hips", 0.0) + share
        mixes.append(mix)
    ## `rigid_above` {bone, from (a station), blend_m, over}: the part above the station moves
    ## with the bone alone (a scarf's mouth wrap with the head), blended into the skin's
    ## weights over `blend_m` below it, so a turned or bowed head never slides the covering
    ## off. `over` (fitting regions, e.g. ["head"]) keeps that to the cloth lying over those
    ## regions: drape on the shoulders at the same height follows the skin beneath it, by
    ## anatomy rather than distance, on every physique. The policy's smoothing blends the
    ## edge. Absent means every region.
    rigid = (policy or {}).get("rigid_above")
    if rigid:
        z0 = _station(frame, rigid["from"]).z
        blend = max(1e-6, rigid.get("blend_m", 0.03))
        over = set(rigid.get("over") or ())
        for v in obj.data.vertices:
            s = min(1.0, max(0.0, (v.co.z - (z0 - blend)) / blend))
            if over and _region_under(frame, v.co) not in over:
                s = 0.0
            if s <= 0.0 or v.index in bone_of:
                continue
            mix = {b: w * (1.0 - s) for b, w in mixes[v.index].items()}
            mix[rigid["bone"]] = mix.get(rigid["bone"], 0.0) + s
            mixes[v.index] = mix
            if s >= 1.0:
                bone_of[v.index] = rigid["bone"]
    groups = {}
    for v, mix in zip(obj.data.vertices, _policy(mixes, obj, bone_of, policy or {})):
        top = sorted(mix.items(), key=lambda kv: -kv[1])[:MAX_INFLUENCES]
        top = [(b, w) for b, w in top if w >= MIN_WEIGHT] or top[:1]
        norm = sum(w for _b, w in top)
        for bone, weight in top:
            if bone not in groups:
                groups[bone] = obj.vertex_groups.new(name=bone)
            groups[bone].add([v.index], weight / norm, "REPLACE")
