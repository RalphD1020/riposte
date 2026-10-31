"""The production body: one connected, deformable surface on WolfRig's rest pose.

Frozen v1 (CHARACTER-SOURCE-001): a regression reference, not the character.
Wolf's anatomy belongs to the Blender master (`male_base.blend`),
which started from this topology and these region weights. No new anatomy is
authored here.

This is not the study mesh. The study fuses lofts with an automatic remesh,
which destroys edge flow and vertex correspondence, so it can judge a
silhouette but cannot bend. The production body is built deliberately around
the construction landmarks (``landmarks.derive_anatomy``):

- One connected primary body. The torso is a quad grid with two shoulder
  sockets and a pelvis opening; each arm is welded to its socket's boundary
  loop through the deltoid cap, and the legs to the two halves of the pelvis
  opening, which share a crotch chain. No piece overlaps another.
- Fixed topology. Ring counts, the socket patch, and the crotch chain are
  constants, so every profile produces the same vertex count and the same
  faces; only positions move (what body variants and morph targets need).
- Edge loops at every joint. Elbows and knees get three rings (before, on,
  after the joint); the spine and neck get rings at each bone boundary.
- Semantic skin weights, applied after the surface exists (``skinning.py``).
  Every vertex is tagged with a deformation region as it is built
  (``regions``; authoring metadata). Weights come from that region's candidate
  bones times a spatial falloff, never from coordinates alone and never from
  treating the region as one bone. Most vertices ride one or two bones; the
  shoulder girdle and the pelvis/groin blend up to four (Compatibility's
  limit), normalized, pruned, ties broken by bone name.
- WolfRig's rest pose, not the modeling A-pose: the production rest pose is
  the combat stance the clips were authored on. Each limb follows its own bone
  chain from the rig contract; the rig's joints are never moved.

``pieces`` names vertex ranges of regions (torso, arms, legs) for diagnostics;
they are regions of one surface, not separate meshes.

Plain Python and plain lists: Blender only turns the result into an object.
"""

from __future__ import annotations

import math

from .anatomy import DELTOID_HANDOFF, derive_anatomy, region_affinity, rig_points
from .skinning import INFLUENCE_LIMIT, PRUNE_WEIGHT, assign_torso, normalize_weights

AROUND = 12
TORSO_AROUND = 16
# Torso columns either side of each socket's centre column (the socket patch
# spans 2 * SOCKET_HALF_COLS quads around and two rows up: 12 boundary vertices).
SOCKET_HALF_COLS = 2
# Crotch chain: interior vertices between the back and front of the opening.
CROTCH_CHAIN = 3
# Deltoid rings: (sweep from lateral toward the humerus, share of the reach
# from the joint out toward the span, radius scale). The section stays in
# the socket's plane so the bridge does not twist when the arm lifts.
# Vertical size is below the old pad (that pad read as a shelf) and above
# the half-height cap (that one folded in forward flexion).
CAP_RINGS = ((0.0, 0.45, 1.0), (0.3, 0.85, 0.92))
CAP_VERTICAL = 0.75
# Cap rings whose front also flows from the socket to the arm: none. Flowed,
# the outer cap ring's front nearly coincided with the first arm ring and
# folded the girdle in Godot (90° flexion, the guard across the arc); the
# inner ring's alone opened a 7.9 cm step into the outer one.
CAP_FRONT_FLOW = ()
# Thigh rings whose depth flows from the pelvis opening into the thigh.
HIP_FLOW_RINGS = 2
CAP_RING_REGIONS = ("deltoid", "deltoid_outer")
# Limb rings carry explicit station weights; their regions are labels.
ARM_RING_REGIONS = ("upper_arm", "upper_arm", "elbow", "elbow", "elbow", "forearm", "wrist", "hand", "hand")
LEG_RING_REGIONS = ("thigh", "thigh", "thigh", "knee", "knee", "knee", "calf", "calf", "ankle", "foot", "foot")


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def _mul(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _unit(a):
    length = math.sqrt(_dot(a, a))
    return _mul(a, 1.0 / length)


def _lerp(a, b, t):
    return _add(a, _mul(_sub(b, a), t))


def _smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def _centroid(points):
    n = float(len(points))
    return (sum(p[0] for p in points) / n, sum(p[1] for p in points) / n, sum(p[2] for p in points) / n)


def _torso_stations(points, anatomy):
    """(z, half-width, half-depth, tag) up the body, the pelvis opening to the crown.

    The shoulders and hips are one heroic V-taper: the acromion ring reaches
    the acromion, and above it the trapezius ridge climbs to the mantle top
    beside the neck (Model A's high mantle) instead of dropping to the neck.
    """
    s = anatomy.sizes
    shoulder = anatomy.shoulders["L"]
    axilla_z, mid_z, acromion_z = shoulder.socket_z
    acromion_x = shoulder.acromion[0]
    neck_x, mantle_z = anatomy.neck_root
    groin = anatomy.pelvis["L"].groin
    iliac = anatomy.pelvis["L"].iliac_z
    hips = points["Hips"][0][2]
    chest = points["Chest"][0][2]
    head = points["Head"][0][2]
    crown = points["Head"][1][2]
    head_h = crown - head
    # The opening sits flush with the thigh tops' outer surface (no ledge).
    opening_w = max(s["pelvis"] * 1.12, abs(anatomy.pelvis["L"].hip[0]) + s["thigh"] * 0.98)
    return (
        (groin[2] + 0.005, opening_w, s["pelvis_d"] * 0.90, "pelvis_opening"),
        (hips - 0.04, opening_w * 0.97, s["pelvis_d"], None),
        (hips + 0.03, s["pelvis"] * 1.04, s["pelvis_d"] * 1.0, None),
        (iliac, s["waist"], s["waist_d"], None),
        (chest - 0.04, s["waist"] * 1.03, s["waist_d"] * 1.02, None),
        (chest + 0.04, s["chest"], s["chest_d"], None),
        (axilla_z, s["chest"] * 1.08, s["chest_d"] * 1.03, "axilla"),
        (mid_z, (s["chest"] * 1.08 + acromion_x) * 0.5, s["chest_d"] * 1.0, "socket_mid"),
        (acromion_z, acromion_x, s["chest_d"] * 0.86, "acromion"),
        ((acromion_z + mantle_z) * 0.5, (acromion_x + neck_x) * 0.5, s["chest_d"] * 0.74, None),
        (mantle_z, neck_x, s["neck_d"] * 1.45, "mantle_top"),
        (mantle_z + 0.03, s["neck"] * 1.12, s["neck_d"] * 1.1, None),
        (head + 0.02, s["neck"] * 1.02, s["neck_d"] * 1.04, None),
        (head + head_h * 0.18, s["head"] * 0.78, s["head_d"] * 0.80, None),
        (head + head_h * 0.38, s["head"] * 0.96, s["head_d"] * 0.96, None),
        (head + head_h * 0.56, s["head"], s["head_d"], None),
        (head + head_h * 0.74, s["head"] * 0.94, s["head_d"] * 0.95, None),
        (head + head_h * 0.88, s["head"] * 0.74, s["head_d"] * 0.76, None),
        (head + head_h * 0.97, s["head"] * 0.40, s["head_d"] * 0.42, None),
    ), crown


# Glute mass behind the pelvis rings: (ring tag or index, metres behind the
# glute landmark). The surface covers the rear thigh tops, so the hip reads
# as a seat over the legs rather than two columns under a box.
GLUTE_REAR_M = {0: 0.035, 1: 0.05, 2: 0.03}


def _rear_depths(stations, anatomy):
    """Per-ring rear half-depth (+Y). Pelvis rings follow the glute landmark;
    every other ring is a plain ellipse."""
    glute_y = anatomy.pelvis["L"].glute[1]
    rear = [half_d for _z, _w, half_d, _tag in stations]
    for ring, behind in GLUTE_REAR_M.items():
        rear[ring] = max(rear[ring], glute_y + behind)
    return rear


def _deltoid_cap(points, shoulder, side, _sizes):
    """A short cap in the socket's plane, reaching toward the shoulder span.

    The ring is not a tall pad and not a tube centered on the joint. Its
    outer face is pulled onto the span afterwards, together with the first
    shaft ring. The shaft beyond that stays on the humerus.
    """
    joint = points["UpperArm." + side][0]
    centre = shoulder.deltoid_center
    humerus = _unit(_sub(points["UpperArm." + side][1], joint))
    lateral = (1.0 if side == "L" else -1.0, 0.0, 0.0)
    vertical = shoulder.deltoid_radii[0] * CAP_VERTICAL
    front_back = shoulder.deltoid_radii[1]
    reach = abs(shoulder.deltoid_outer_extent[0] - centre[0])
    rings = []
    for (sweep, share, scale), region in zip(CAP_RINGS, CAP_RING_REGIONS):
        direction = _unit(_lerp(lateral, humerus, sweep))
        rings.append((_add(centre, _mul(direction, reach * share)), vertical * scale, front_back * scale,
                      (lambda d, r=region: region_affinity(r, side, d[2])), region))
    return tuple(rings)


def _arm_stations(points, side, s):
    """(centre, half-width, half-depth, weights) from the upper arm to the grip.
    The deltoid cap ring that precedes these comes from the landmarks."""
    joint, elbow = points["UpperArm." + side]
    wrist = points["Forearm." + side][1]
    grip = points["Hand." + side][1]
    upper, fore, hand = "UpperArm." + side, "Forearm." + side, "Hand." + side
    return (
        (_lerp(joint, elbow, DELTOID_HANDOFF), s["arm"], s["arm"] * 0.96, ((upper, 1.0),)),
        (_lerp(joint, elbow, 0.62), s["arm_end"] * 1.10, s["arm_end"] * 1.04, ((upper, 1.0),)),
        (_lerp(joint, elbow, 0.90), s["arm_end"], s["arm_end"], ((upper, 0.85), (fore, 0.15))),
        (elbow, s["arm_end"] * 0.97, s["arm_end"] * 0.97, ((upper, 0.5), (fore, 0.5))),
        (_lerp(elbow, wrist, 0.10), s["fore"] * 0.98, s["fore"] * 0.98, ((upper, 0.15), (fore, 0.85))),
        (_lerp(elbow, wrist, 0.32), s["fore"], s["fore"] * 0.94, ((fore, 1.0),)),
        (wrist, s["fore_end"], s["fore_end"] * 0.86, ((fore, 0.5), (hand, 0.5))),
        (_lerp(wrist, grip, 0.55), s["hand"], s["hand"] * 0.7, ((hand, 1.0),)),
        (grip, s["hand"] * 0.75, s["hand"] * 0.55, ((hand, 1.0),)),
    )


def _leg_stations(points, side, s):
    hip, knee = points["UpperLeg." + side]
    ankle = points["LowerLeg." + side][1]
    toe = points["Foot." + side][1]
    thigh, shin, foot = "UpperLeg." + side, "LowerLeg." + side, "Foot." + side
    sole = (ankle[0], ankle[1], ankle[2] - 0.005)
    return (
        (_lerp(hip, knee, 0.25), s["thigh"], s["thigh"], ((thigh, 0.75), ("Hips", 0.25))),
        (_lerp(hip, knee, 0.50), s["thigh"] * 0.96, s["thigh"] * 0.96, ((thigh, 0.92), ("Hips", 0.08))),
        (_lerp(hip, knee, 0.72), s["thigh_end"] * 1.06, s["thigh_end"] * 1.06, ((thigh, 1.0),)),
        (_lerp(hip, knee, 0.92), s["knee"], s["knee"], ((thigh, 0.85), (shin, 0.15))),
        (knee, s["knee"], s["knee"], ((thigh, 0.5), (shin, 0.5))),
        (_lerp(knee, ankle, 0.08), s["knee"], s["knee"], ((thigh, 0.15), (shin, 0.85))),
        (_lerp(knee, ankle, 0.30), s["calf"], s["calf"], ((shin, 1.0),)),
        (_lerp(knee, ankle, 0.70), (s["calf"] + s["ankle"]) * 0.5, (s["calf"] + s["ankle"]) * 0.5, ((shin, 1.0),)),
        (sole, s["ankle"], s["ankle"], ((shin, 0.5), (foot, 0.5))),
        (_lerp(sole, toe, 0.55), s["foot"], s["foot_tall"], ((foot, 1.0),)),
        (toe, s["foot"] * 0.8, s["foot_tall"] * 0.75, ((foot, 1.0),)),
    )


def _frames(centres):
    """A rotation-minimizing (u, v) per centre; u x v is the tube's direction."""
    tangents = []
    for i in range(len(centres)):
        a = centres[max(0, i - 1)]
        b = centres[min(len(centres) - 1, i + 1)]
        tangents.append(_unit(_sub(b, a)))
    ref = (0.0, -1.0, 0.0) if abs(tangents[0][2]) > 0.95 else (0.0, 0.0, 1.0)
    u = _unit(_cross(tangents[0], ref))
    frames = []
    for t in tangents:
        u = _unit(_sub(u, _mul(t, _dot(u, t))))
        frames.append((u, _cross(t, u)))
    return frames


def _socket_columns(centre):
    return [(centre + offset) % TORSO_AROUND for offset in range(-SOCKET_HALF_COLS, SOCKET_HALF_COLS + 1)]


class _Body:
    def __init__(self):
        self.vertices = []
        self.faces = []
        self.weights = []
        self.regions = []
        self.pieces = []
        self._directed = set()

    def vertex(self, position, weights, region=""):
        self.vertices.append(position)
        self.weights.append(weights)
        self.regions.append(region)
        return len(self.vertices) - 1

    def face(self, *corners):
        self.faces.append(tuple(corners))
        for i, a in enumerate(corners):
            self._directed.add((a, corners[(i + 1) % len(corners)]))

    def oriented(self, loop):
        """``loop`` ordered so the faces already on it run the other way, which
        is the order a bridge needs for consistent winding."""
        for i, a in enumerate(loop):
            b = loop[(i + 1) % len(loop)]
            if (b, a) in self._directed:
                return list(loop)
            if (a, b) in self._directed:
                return list(reversed(loop))
        raise ValueError("loop shares no edge with the surface")

    def bridge(self, loop, ring):
        n = len(loop)
        for k in range(n):
            self.face(loop[k], loop[(k + 1) % n], ring[(k + 1) % n], ring[k])

    def cap(self, ring, apex):
        n = len(ring)
        for k in range(n):
            self.face(apex, ring[k], ring[(k + 1) % n])


def _meet_outer_face(vertices, start, count, target_x):
    """Move one ring's lateral extreme onto ``target_x``. The medial extreme
    stays, and Y/Z stay, so the shaft is not translated."""
    indices = range(start, start + count)
    xs = [vertices[i][0] for i in indices]
    if target_x >= 0.0:
        outer, inner = max(xs), min(xs)
    else:
        outer, inner = min(xs), max(xs)
    span = outer - inner
    if abs(span) < 1e-9:
        return
    for index, x in zip(indices, xs):
        y, z = vertices[index][1], vertices[index][2]
        t = (x - inner) / span
        vertices[index] = (inner + t * (target_x - inner), y, z)


def _span_y(vertices, indices):
    ys = [vertices[i][1] for i in indices]
    return min(ys), max(ys)


def _flow_depth(vertices, start, count, front, back):
    """Remap one ring's front-to-back extent onto [front, back] (Y only)."""
    indices = range(start, start + count)
    lo, hi = _span_y(vertices, indices)
    if hi - lo < 1e-9:
        return
    for index in indices:
        x, y, z = vertices[index]
        vertices[index] = (x, front + (y - lo) / (hi - lo) * (back - front), z)


def _limb(body, loop, stations, ellipse_axis):
    """Weld a limb onto an oriented boundary ``loop``. Ring angles start at the
    loop vertices' own angles (so the first band does not twist) and settle to
    an even spacing by the third ring. ``stations`` are (centre, half_w, half_d,
    weights, region), where weights may be a function of the vertex's unit
    direction from its ring centre (an angular gradient around a joint);
    ``ellipse_axis(index)`` gives a ring the world axis its half-width lies
    along (half-depth across it), or None to use the ring's frame."""
    loop_points = [body.vertices[i] for i in loop]
    origin = _centroid(loop_points)
    frames = _frames([origin] + [station[0] for station in stations])
    u0, v0 = frames[0]
    angles = [math.atan2(_dot(_sub(p, origin), v0), _dot(_sub(p, origin), u0)) for p in loop_points]
    turn = sum(math.remainder(angles[(k + 1) % len(angles)] - angles[k], 2.0 * math.pi) for k in range(len(angles)))
    direction = 1.0 if turn > 0.0 else -1.0
    even = [angles[0] + direction * 2.0 * math.pi * k / len(loop) for k in range(len(loop))]
    previous = loop
    for index, ((centre, half_w, half_d, weights, region), (u, v)) in enumerate(zip(stations, frames[1:])):
        settle = _smooth(index / 2.0)
        ring = []
        for k in range(len(loop)):
            angle = angles[k] + math.remainder(even[k] - angles[k], 2.0 * math.pi) * settle
            d = _add(_mul(u, math.cos(angle)), _mul(v, math.sin(angle)))
            axis = ellipse_axis(index)
            if axis is None:
                radius = half_w * half_d / math.hypot(half_d * math.cos(angle), half_w * math.sin(angle))
            else:
                along = _dot(d, axis)
                radius = 1.0 / math.sqrt((along / half_w) ** 2 + (1.0 - along * along) / half_d ** 2)
            ring_weights = weights(d) if callable(weights) else weights
            ring.append(body.vertex(_add(centre, _mul(d, radius)), normalize_weights(ring_weights), region))
        body.bridge(previous, ring)
        previous = ring
    end = stations[-1]
    body.cap(previous, body.vertex(end[0], normalize_weights(end[3]), end[4]))


def build(resolved, rig):
    """The production body for one resolved profile on one rig contract.

    Returns ``vertices``, ``faces`` (quads and cap triangles, outward winding),
    ``weights`` (per vertex, at most four ``(bone, weight)`` summing to one),
    ``pieces`` ((region, first, end) vertex ranges), ``crown`` (the head top),
    ``sockets`` (side -> the boundary loop each arm is welded to) and
    ``landmarks`` (the ``AnatomyLandmarks`` it was built around).
    """
    points = rig_points(rig)
    anatomy = derive_anatomy(resolved, rig)
    stations, crown = _torso_stations(points, anatomy)
    tags = {tag: index for index, (_z, _w, _d, tag) in enumerate(stations) if tag}
    body = _Body()
    n = TORSO_AROUND

    # Torso grid: rings of TORSO_AROUND, the bottom ring left open for the legs.
    rear = _rear_depths(stations, anatomy)
    for (z, half_w, half_d, _tag), back in zip(stations, rear):
        for c in range(n):
            angle = 2.0 * math.pi * c / n
            depth = back if math.sin(angle) > 0.0 else half_d
            body.vertex((half_w * math.cos(angle), depth * math.sin(angle), z), ())

    def at(ring, column):
        return ring * n + column % n

    axilla = tags["axilla"]
    socket_cols = {"L": _socket_columns(0), "R": _socket_columns(n // 2)}
    removed = {(row, col) for cols in socket_cols.values() for row in (axilla, axilla + 1) for col in cols[:-1]}
    for i in range(len(stations) - 1):
        for c in range(n):
            if (i, c) not in removed:
                body.face(at(i, c), at(i, c + 1), at(i + 1, c + 1), at(i, c) + n)
    body.cap([at(len(stations) - 1, c) for c in range(n)], body.vertex((0.0, 0.0, crown), ()))
    torso_end = len(body.vertices)

    sockets = {}
    for side, cols in socket_cols.items():
        top = axilla + 2
        loop = ([at(axilla, c) for c in cols] + [at(axilla + 1, cols[-1])]
                + [at(top, c) for c in reversed(cols)] + [at(axilla + 1, cols[0])])
        sockets[side] = body.oriented(loop)

    # Crotch chain across the pelvis opening, back to front, shared by both legs.
    opening = tags["pelvis_opening"]
    back, front = at(opening, n // 4), at(opening, 3 * n // 4)
    groin = anatomy.pelvis["L"].groin
    chain = []
    for k in range(1, CROTCH_CHAIN + 1):
        t = k / (CROTCH_CHAIN + 1.0)
        y = body.vertices[back][1] + (body.vertices[front][1] - body.vertices[back][1]) * t
        chain.append(body.vertex((0.0, y, groin[2]), ()))
    leg_loops = {
        "L": [at(opening, c) for c in range(3 * n // 4, n + n // 4 + 1)] + chain,
        "R": [at(opening, c) for c in range(n // 4, 3 * n // 4 + 1)] + list(reversed(chain)),
    }

    assign_torso(body.vertices, body.weights, body.regions, points, anatomy, stations, torso_end, chain,
                 sockets, TORSO_AROUND)
    body.pieces.append(("Torso", 0, len(body.vertices)))

    for side in ("L", "R"):
        first = len(body.vertices)
        arm = tuple(s + (r,) for s, r in zip(_arm_stations(points, side, anatomy.sizes), ARM_RING_REGIONS))
        _limb(body, sockets[side], _deltoid_cap(points, anatomy.shoulders[side], side, anatomy.sizes) + arm,
              lambda index: (0.0, 0.0, 1.0) if index < len(CAP_RINGS) else None)
        target = anatomy.shoulders[side].deltoid_outer_extent[0]
        _meet_outer_face(body.vertices, first + AROUND, AROUND, target)
        _meet_outer_face(body.vertices, first + 2 * AROUND, AROUND, target)
        # The posterior deltoid flows from the socket into the upper arm: each
        # cap ring's back is its share of the way between them. Centred on the
        # joint, the rear cap jutted 4 cm behind the socket and collapsed 7 cm
        # in one ring (the arm leaving the back).
        socket = _span_y(body.vertices, sockets[side])
        shaft = _span_y(body.vertices, range(first + len(CAP_RINGS) * AROUND, first + (len(CAP_RINGS) + 1) * AROUND))
        for ring in range(len(CAP_RINGS)):
            share = (ring + 1.0) / (len(CAP_RINGS) + 1.0)
            own = _span_y(body.vertices, range(first + ring * AROUND, first + (ring + 1) * AROUND))
            front = socket[0] + (shaft[0] - socket[0]) * share if ring in CAP_FRONT_FLOW else own[0]
            _flow_depth(body.vertices, first + ring * AROUND, AROUND, front, socket[1] + (shaft[1] - socket[1]) * share)
        body.pieces.append(("Arm." + side, first, len(body.vertices)))
    for side in ("L", "R"):
        first = len(body.vertices)
        loop = body.oriented(leg_loops[side])
        leg = tuple(s + (r,) for s, r in zip(_leg_stations(points, side, anatomy.sizes), LEG_RING_REGIONS))
        _limb(body, loop, leg, lambda _index: None)
        # The pelvis flows into the thigh: the stance sets each thigh fore or
        # aft of the centred opening, and the first thigh ring stepped away
        # from it (a 5.3 cm ledge in front of the trailing thigh, a 10.8 cm
        # shelf under the glute behind the lead one). The proximal rings take
        # their share of the way from the opening's half to the thigh below.
        opening = _span_y(body.vertices, loop)
        below = _span_y(body.vertices, range(first + HIP_FLOW_RINGS * AROUND, first + (HIP_FLOW_RINGS + 1) * AROUND))
        for ring in range(HIP_FLOW_RINGS):
            share = (ring + 1.0) / (HIP_FLOW_RINGS + 1.0)
            _flow_depth(body.vertices, first + ring * AROUND, AROUND, opening[0] + (below[0] - opening[0]) * share,
                        opening[1] + (below[1] - opening[1]) * share)
        body.pieces.append(("Leg." + side, first, len(body.vertices)))

    return {
        "vertices": body.vertices,
        "faces": body.faces,
        "weights": body.weights,
        "regions": body.regions,
        "pieces": body.pieces,
        "crown": crown,
        "sockets": sockets,
        "landmarks": anatomy,
    }


def triangle_count(faces):
    return sum(len(face) - 2 for face in faces)


def volume(mesh):
    """Signed volume of the closed body (divergence theorem). Positive means
    the faces wind outward; a flipped body would be negative."""
    total = 0.0
    for face in mesh["faces"]:
        a = mesh["vertices"][face[0]]
        for i in range(1, len(face) - 1):
            b = mesh["vertices"][face[i]]
            c = mesh["vertices"][face[i + 1]]
            total += _dot(a, _cross(b, c)) / 6.0
    return total
